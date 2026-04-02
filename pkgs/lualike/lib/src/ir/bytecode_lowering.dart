import 'dart:math' as math;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';

LuaBytecodeBinaryChunk lowerIrChunkToLuaBytecodeChunk(
  LualikeIrChunk chunk, {
  String? chunkName,
}) {
  final mainPrototype = lowerIrPrototypeToLuaBytecodePrototype(
    chunk.mainPrototype,
    sourceName:
        chunk.mainPrototype.debugInfo?.absoluteSourcePath ??
        chunkName ??
        '=(lualike_ir)',
    isMainPrototype: true,
  );
  return LuaBytecodeBinaryChunk(
    header: const LuaBytecodeChunkHeader.official(),
    rootUpvalueCount: mainPrototype.upvalues.length,
    mainPrototype: mainPrototype,
  );
}

LuaBytecodePrototype lowerIrPrototypeToLuaBytecodePrototype(
  LualikeIrPrototype prototype, {
  required String sourceName,
  bool isMainPrototype = false,
}) {
  final debugInfo = prototype.debugInfo;
  final tempBase = prototype.registerCount;
  final loweredInstructions = _lowerInstructions(
    prototype.instructions,
    tempBase: tempBase,
  );
  final instructions = loweredInstructions.instructions;
  final pcMap = loweredInstructions.pcMap;
  final constants = List<LuaBytecodeConstant>.unmodifiable(
    prototype.constants.map(_lowerConstant),
  );
  final loweredUpvalueNames = List<String?>.from(
    debugInfo?.upvalueNames ?? const <String>[],
    growable: true,
  );
  final loweredUpvalues = List<LuaBytecodeUpvalueDescriptor>.generate(
    prototype.upvalueDescriptors.length,
    (index) => _lowerUpvalueDescriptor(
      prototype.upvalueDescriptors[index],
      name: index < loweredUpvalueNames.length ? loweredUpvalueNames[index] : null,
    ),
    growable: true,
  );
  if (isMainPrototype && loweredUpvalues.isEmpty) {
    loweredUpvalues.add(
      const LuaBytecodeUpvalueDescriptor(
        inStack: true,
        index: 0,
        kind: LuaBytecodeUpvalueKind.localRegister,
        name: '_ENV',
      ),
    );
    if (loweredUpvalueNames.isEmpty) {
      loweredUpvalueNames.add('_ENV');
    }
  }
  final upvalues = List<LuaBytecodeUpvalueDescriptor>.unmodifiable(
    loweredUpvalues,
  );
  final children = List<LuaBytecodePrototype>.unmodifiable(
    prototype.prototypes.map(
      (child) => lowerIrPrototypeToLuaBytecodePrototype(
        child,
        sourceName: child.debugInfo?.absoluteSourcePath ?? sourceName,
      ),
    ),
  );
  final debugLines = _lowerDebugLines(debugInfo?.lineInfo, instructions.length);
  final locals = List<LuaBytecodeLocalVariableDebugInfo>.unmodifiable(
    (debugInfo?.localNames ?? const <LocalDebugEntry>[]).map(
      (entry) => LuaBytecodeLocalVariableDebugInfo(
        name: entry.name,
        startPc: _remapPc(entry.startPc, pcMap),
        endPc: _remapPc(entry.endPc, pcMap),
        register: entry.register,
      ),
    ),
  );
  final upvalueNames = List<String?>.unmodifiable(loweredUpvalueNames);

  return LuaBytecodePrototype(
    lineDefined: prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    parameterCount: prototype.paramCount,
    flags: _prototypeFlags(prototype, isMainPrototype: isMainPrototype),
    maxStackSize: math.max(2, prototype.registerCount + 2),
    code: List<LuaBytecodeInstructionWord>.unmodifiable(instructions),
    constants: constants,
    upvalues: upvalues,
    prototypes: children,
    source: debugInfo?.absoluteSourcePath ?? sourceName,
    lineInfo: debugLines.lineInfo,
    absoluteLineInfo: debugLines.absoluteLineInfo,
    localVariables: locals,
    upvalueNames: upvalueNames,
  );
}

int _prototypeFlags(
  LualikeIrPrototype prototype, {
  required bool isMainPrototype,
}) {
  var flags = 0;
  if (prototype.isVararg || isMainPrototype) {
    flags |= LuaBytecodePrototypeFlags.hasHiddenVarargs;
  }
  if (prototype.namedVarargRegister != null) {
    flags |= LuaBytecodePrototypeFlags.hasVarargTable;
  }
  return flags;
}

LuaBytecodeConstant _lowerConstant(LualikeIrConstant constant) {
  return switch (constant) {
    NilConstant() => const LuaBytecodeNilConstant(),
    BooleanConstant(:final value) => LuaBytecodeBooleanConstant(value),
    IntegerConstant(:final value) => LuaBytecodeIntegerConstant(value),
    NumberConstant(:final value) => LuaBytecodeFloatConstant(value),
    ShortStringConstant(:final value) => LuaBytecodeStringConstant(
      value,
      isLong: false,
    ),
    LongStringConstant(:final value) => LuaBytecodeStringConstant(
      value,
      isLong: true,
    ),
  };
}

LuaBytecodeUpvalueDescriptor _lowerUpvalueDescriptor(
  LualikeIrUpvalueDescriptor descriptor,
  {String? name}
) {
  return LuaBytecodeUpvalueDescriptor(
    inStack: descriptor.inStack != 0,
    index: descriptor.index,
    kind: LuaBytecodeUpvalueKind.fromValue(descriptor.kind),
    name: name,
  );
}

LuaBytecodeInstructionWord _lowerInstruction(LualikeIrInstruction instruction) {
  final opcode = LuaBytecodeOpcodes.byName(instruction.opcode.name);
  return instruction.when(
    abc: (instr) => _lowerAbcInstruction(instr, opcode.code),
    abx: (instr) => LuaBytecodeInstructionWord.abx(
      opcode: opcode.code,
      a: instr.a,
      bx: instr.bx,
    ),
    asbx: (instr) => LuaBytecodeInstructionWord.asBx(
      opcode: opcode.code,
      a: instr.a,
      sBx: instr.sBx,
    ),
    ax: (instr) =>
        LuaBytecodeInstructionWord.ax(opcode: opcode.code, ax: instr.ax),
    asj: (instr) =>
        LuaBytecodeInstructionWord.sj(opcode: opcode.code, sJ: instr.sJ),
    avbc: (instr) => LuaBytecodeInstructionWord.vabc(
      opcode: opcode.code,
      a: instr.a,
      b: instr.vB,
      c: instr.vC,
      k: instr.k,
    ),
  );
}

LuaBytecodeInstructionWord _lowerAbcInstruction(
  ABCInstruction instruction,
  int opcode,
) {
  if (instruction.opcode == LualikeIrOpcode.setUpval) {
    return LuaBytecodeInstructionWord.abc(
      opcode: opcode,
      a: instruction.c,
      b: instruction.b,
      c: 0,
      k: instruction.k,
    );
  }
  return LuaBytecodeInstructionWord.abc(
    opcode: opcode,
    a: instruction.a,
    b: _encodeBOperand(instruction.opcode, instruction.b),
    c: _encodeCOperand(instruction.opcode, instruction.c),
    k: instruction.k,
  );
}

int _encodeBOperand(LualikeIrOpcode opcode, int operand) {
  if (_usesSignedBImmediate(opcode)) {
    return operand + LuaBytecodeInstructionLayout.offsetSB;
  }
  return operand;
}

int _encodeCOperand(LualikeIrOpcode opcode, int operand) {
  if (_usesSignedCImmediate(opcode)) {
    return operand + LuaBytecodeInstructionLayout.offsetSC;
  }
  return operand;
}

bool _usesSignedBImmediate(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.eqI ||
    LualikeIrOpcode.ltI ||
    LualikeIrOpcode.leI ||
    LualikeIrOpcode.gtI ||
    LualikeIrOpcode.geI ||
    LualikeIrOpcode.mmBinI => true,
    _ => false,
  };
}

bool _usesSignedCImmediate(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.addI || LualikeIrOpcode.shlI || LualikeIrOpcode.shrI =>
      true,
    _ => false,
  };
}

({List<LuaBytecodeInstructionWord> instructions, List<int> pcMap})
_lowerInstructions(
  List<LualikeIrInstruction> instructions,
  {required int tempBase}
) {
  final lowered = <LuaBytecodeInstructionWord>[];
  final pcMap = List<int>.filled(instructions.length + 1, 0, growable: false);

  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    pcMap[oldPc] = lowered.length;
    try {
      lowered.addAll(
        _lowerInstructionSequence(instructions[oldPc], tempBase: tempBase),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError(
          'failed to lower IR instruction at pc=$oldPc: '
          '${instructions[oldPc].opcode.name} ${instructions[oldPc]} '
          '(tempBase=$tempBase): $error',
        ),
        stackTrace,
      );
    }
  }
  pcMap[instructions.length] = lowered.length;

  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    final instruction = instructions[oldPc];
    final newPc = pcMap[oldPc];
    switch (instruction) {
      case AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: final sJ):
        final targetOldPc = oldPc + 1 + sJ;
        final targetNewPc = pcMap[targetOldPc];
        lowered[newPc] = LuaBytecodeInstructionWord.sj(
          opcode: LuaBytecodeOpcodes.byName('JMP').code,
          sJ: targetNewPc - newPc - 1,
        );
      case AsBxInstruction(opcode: final opcode, a: final a, sBx: final sBx)
          when opcode == LualikeIrOpcode.forPrep ||
              opcode == LualikeIrOpcode.forLoop:
        final targetOldPc = oldPc + 1 + sBx;
        final targetNewPc = opcode == LualikeIrOpcode.forPrep
            ? pcMap[targetOldPc + 1]
            : pcMap[targetOldPc];
        final bx = opcode == LualikeIrOpcode.forPrep
            ? targetNewPc - newPc - 2
            : newPc + 1 - targetNewPc;
        lowered[newPc] = LuaBytecodeInstructionWord.abx(
          opcode: LuaBytecodeOpcodes.byName(opcode.name).code,
          a: a,
          bx: bx,
        );
      case AsBxInstruction(opcode: final opcode, a: final a, sBx: final sBx)
          when opcode == LualikeIrOpcode.tForPrep ||
              opcode == LualikeIrOpcode.tForLoop:
        final targetOldPc = oldPc + 1 + sBx;
        final targetNewPc = pcMap[targetOldPc];
        final bx = opcode == LualikeIrOpcode.tForPrep
            ? targetNewPc - newPc - 1
            : newPc + 1 - targetNewPc;
        lowered[newPc] = LuaBytecodeInstructionWord.abx(
          opcode: LuaBytecodeOpcodes.byName(opcode.name).code,
          a: a,
          bx: bx,
        );
      case _:
        break;
    }
  }

  return (
    instructions: List<LuaBytecodeInstructionWord>.unmodifiable(lowered),
    pcMap: List<int>.unmodifiable(pcMap),
  );
}

List<LuaBytecodeInstructionWord> _lowerInstructionSequence(
  LualikeIrInstruction instruction, {
  required int tempBase,
}
) {
  final arithmetic = _lowerArithmeticMetamethodSequence(instruction);
  if (arithmetic != null) {
    return arithmetic;
  }
  final highConstant = _lowerHighConstantSequence(instruction, tempBase: tempBase);
  if (highConstant != null) {
    return highConstant;
  }
  final table = _lowerTableInstructionSequence(instruction);
  if (table != null) {
    return table;
  }
  if (instruction is ABCInstruction) {
    final compare = _lowerCompareSequence(instruction, tempBase: tempBase);
    if (compare != null) {
      return compare;
    }
  }
  return <LuaBytecodeInstructionWord>[_lowerInstruction(instruction)];
}

List<LuaBytecodeInstructionWord>? _lowerArithmeticMetamethodSequence(
  LualikeIrInstruction instruction,
) {
  if (instruction is! ABCInstruction) {
    return null;
  }

  final event = _binaryMetamethodEvent(instruction.opcode);
  if (event == null) {
    return null;
  }

  final primary = _lowerInstruction(instruction);
  final followup = switch (instruction.opcode) {
    LualikeIrOpcode.addI ||
    LualikeIrOpcode.shlI ||
    LualikeIrOpcode.shrI => LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBINI').code,
      a: instruction.a,
      b: _encodeCOperand(instruction.opcode, instruction.c),
      c: event,
      k: instruction.k,
    ),
    LualikeIrOpcode.addK ||
    LualikeIrOpcode.subK ||
    LualikeIrOpcode.mulK ||
    LualikeIrOpcode.modK ||
    LualikeIrOpcode.powK ||
    LualikeIrOpcode.divK ||
    LualikeIrOpcode.idivK ||
    LualikeIrOpcode.bandK ||
    LualikeIrOpcode.borK ||
    LualikeIrOpcode.bxorK => LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBINK').code,
      a: instruction.a,
      b: instruction.c,
      c: event,
      k: instruction.k,
    ),
    _ => LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBIN').code,
      a: instruction.b,
      b: instruction.c,
      c: event,
      k: instruction.k,
    ),
  };
  return <LuaBytecodeInstructionWord>[primary, followup];
}

int? _binaryMetamethodEvent(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.add || LualikeIrOpcode.addI || LualikeIrOpcode.addK => 6,
    LualikeIrOpcode.sub || LualikeIrOpcode.subK => 7,
    LualikeIrOpcode.mul || LualikeIrOpcode.mulK => 8,
    LualikeIrOpcode.mod || LualikeIrOpcode.modK => 9,
    LualikeIrOpcode.pow || LualikeIrOpcode.powK => 10,
    LualikeIrOpcode.div || LualikeIrOpcode.divK => 11,
    LualikeIrOpcode.idiv || LualikeIrOpcode.idivK => 12,
    LualikeIrOpcode.band || LualikeIrOpcode.bandK => 13,
    LualikeIrOpcode.bor || LualikeIrOpcode.borK => 14,
    LualikeIrOpcode.bxor || LualikeIrOpcode.bxorK => 15,
    LualikeIrOpcode.shl || LualikeIrOpcode.shlI => 16,
    LualikeIrOpcode.shr || LualikeIrOpcode.shrI => 17,
    _ => null,
  };
}

List<LuaBytecodeInstructionWord>? _lowerHighConstantSequence(
  LualikeIrInstruction instruction, {
  required int tempBase,
}) {
  if (instruction is! ABCInstruction) {
    return null;
  }

  List<LuaBytecodeInstructionWord> loadKey(int register, int constantIndex) =>
      _loadConstantToRegisterSequence(register, constantIndex);

  return switch (instruction.opcode) {
    LualikeIrOpcode.getField
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC => <LuaBytecodeInstructionWord>[
          ...loadKey(tempBase, instruction.c),
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('GETTABLE').code,
            a: instruction.a,
            b: instruction.b,
            c: tempBase,
          ),
        ],
    LualikeIrOpcode.setField
        when instruction.b > LuaBytecodeInstructionLayout.maxArgB => <LuaBytecodeInstructionWord>[
          ...loadKey(tempBase, instruction.b),
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('SETTABLE').code,
            a: instruction.a,
            b: tempBase,
            c: instruction.c,
          ),
        ],
    LualikeIrOpcode.getTabUp
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC => <LuaBytecodeInstructionWord>[
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('GETUPVAL').code,
            a: instruction.a,
            b: instruction.b,
            c: 0,
          ),
          ...loadKey(tempBase, instruction.c),
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('GETTABLE').code,
            a: instruction.a,
            b: instruction.a,
            c: tempBase,
          ),
        ],
    LualikeIrOpcode.setTabUp
        when instruction.b > LuaBytecodeInstructionLayout.maxArgB => <LuaBytecodeInstructionWord>[
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('GETUPVAL').code,
            a: tempBase,
            b: instruction.a,
            c: 0,
          ),
          ...loadKey(tempBase + 1, instruction.b),
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('SETTABLE').code,
            a: tempBase,
            b: tempBase + 1,
            c: instruction.c,
          ),
        ],
    LualikeIrOpcode.selfOp
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC => <LuaBytecodeInstructionWord>[
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('MOVE').code,
            a: instruction.a + 1,
            b: instruction.b,
            c: 0,
          ),
          ...loadKey(tempBase, instruction.c),
          LuaBytecodeInstructionWord.abc(
            opcode: LuaBytecodeOpcodes.byName('GETTABLE').code,
            a: instruction.a,
            b: instruction.b,
            c: tempBase,
          ),
        ],
    _ => null,
  };
}

List<LuaBytecodeInstructionWord> _loadConstantToRegisterSequence(
  int register,
  int constantIndex,
) {
  if (constantIndex <= LuaBytecodeInstructionLayout.maxArgBx) {
    return <LuaBytecodeInstructionWord>[
      LuaBytecodeInstructionWord.abx(
        opcode: LuaBytecodeOpcodes.byName('LOADK').code,
        a: register,
        bx: constantIndex,
      ),
    ];
  }
  return <LuaBytecodeInstructionWord>[
    LuaBytecodeInstructionWord.abx(
      opcode: LuaBytecodeOpcodes.byName('LOADKX').code,
      a: register,
      bx: 0,
    ),
    LuaBytecodeInstructionWord.ax(
      opcode: LuaBytecodeOpcodes.byName('EXTRAARG').code,
      ax: constantIndex,
    ),
  ];
}

List<LuaBytecodeInstructionWord>? _lowerCompareSequence(
  ABCInstruction instruction,
  {required int tempBase}
) {
  LuaBytecodeInstructionWord compareWord(
    String opcodeName, {
    required int a,
    required int b,
    int c = 0,
  }) {
    return LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName(opcodeName).code,
      a: a,
      b: _encodeBOperand(instruction.opcode, b),
      c: _encodeCOperand(instruction.opcode, c),
      k: true,
    );
  }

  final target = instruction.a;
  List<LuaBytecodeInstructionWord> materializeBool(
    LuaBytecodeInstructionWord compare,
  ) {
    return <LuaBytecodeInstructionWord>[
      compare,
      LuaBytecodeInstructionWord.sj(
        opcode: LuaBytecodeOpcodes.byName('JMP').code,
        sJ: 1,
      ),
      LuaBytecodeInstructionWord.abc(
        opcode: LuaBytecodeOpcodes.byName('LFALSESKIP').code,
        a: target,
        b: 0,
        c: 0,
      ),
      LuaBytecodeInstructionWord.abc(
        opcode: LuaBytecodeOpcodes.byName('LOADTRUE').code,
        a: target,
        b: 0,
        c: 0,
      ),
    ];
  }

  bool signedImmediateFits(int value) =>
      value >= -LuaBytecodeInstructionLayout.offsetSB &&
      value <= LuaBytecodeInstructionLayout.offsetSB;

  LuaBytecodeInstructionWord registerCompare(
    String opcodeName, {
    required int left,
    required int right,
  }) {
    return LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName(opcodeName).code,
      a: left,
      b: right,
      c: 0,
      k: true,
    );
  }

  switch (instruction.opcode) {
    case LualikeIrOpcode.eqK
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC:
      return <LuaBytecodeInstructionWord>[
        ..._loadConstantToRegisterSequence(tempBase, instruction.c),
        ...materializeBool(
          registerCompare('EQ', left: instruction.b, right: tempBase),
        ),
      ];
    case LualikeIrOpcode.eqI
        when !signedImmediateFits(instruction.c):
      return <LuaBytecodeInstructionWord>[
        LuaBytecodeInstructionWord.asBx(
          opcode: LuaBytecodeOpcodes.byName('LOADI').code,
          a: tempBase,
          sBx: instruction.c,
        ),
        ...materializeBool(
          registerCompare('EQ', left: instruction.b, right: tempBase),
        ),
      ];
    case LualikeIrOpcode.ltI
        when !signedImmediateFits(instruction.c):
      return <LuaBytecodeInstructionWord>[
        LuaBytecodeInstructionWord.asBx(
          opcode: LuaBytecodeOpcodes.byName('LOADI').code,
          a: tempBase,
          sBx: instruction.c,
        ),
        ...materializeBool(
          registerCompare('LT', left: instruction.b, right: tempBase),
        ),
      ];
    case LualikeIrOpcode.leI
        when !signedImmediateFits(instruction.c):
      return <LuaBytecodeInstructionWord>[
        LuaBytecodeInstructionWord.asBx(
          opcode: LuaBytecodeOpcodes.byName('LOADI').code,
          a: tempBase,
          sBx: instruction.c,
        ),
        ...materializeBool(
          registerCompare('LE', left: instruction.b, right: tempBase),
        ),
      ];
    case LualikeIrOpcode.gtI
        when !signedImmediateFits(instruction.c):
      return <LuaBytecodeInstructionWord>[
        LuaBytecodeInstructionWord.asBx(
          opcode: LuaBytecodeOpcodes.byName('LOADI').code,
          a: tempBase,
          sBx: instruction.c,
        ),
        ...materializeBool(
          registerCompare('LT', left: tempBase, right: instruction.b),
        ),
      ];
    case LualikeIrOpcode.geI
        when !signedImmediateFits(instruction.c):
      return <LuaBytecodeInstructionWord>[
        LuaBytecodeInstructionWord.asBx(
          opcode: LuaBytecodeOpcodes.byName('LOADI').code,
          a: tempBase,
          sBx: instruction.c,
        ),
        ...materializeBool(
          registerCompare('LE', left: tempBase, right: instruction.b),
        ),
      ];
    default:
      break;
  }

  final compare = switch (instruction.opcode) {
    LualikeIrOpcode.eq => compareWord('EQ', a: instruction.b, b: instruction.c),
    LualikeIrOpcode.lt => compareWord('LT', a: instruction.b, b: instruction.c),
    LualikeIrOpcode.le => compareWord('LE', a: instruction.b, b: instruction.c),
    LualikeIrOpcode.eqK => compareWord(
      'EQK',
      a: instruction.b,
      b: instruction.c,
    ),
    LualikeIrOpcode.eqI => compareWord(
      'EQI',
      a: instruction.b,
      b: instruction.c,
    ),
    LualikeIrOpcode.ltI => compareWord(
      'LTI',
      a: instruction.b,
      b: instruction.c,
    ),
    LualikeIrOpcode.leI => compareWord(
      'LEI',
      a: instruction.b,
      b: instruction.c,
    ),
    LualikeIrOpcode.gtI => compareWord(
      'GTI',
      a: instruction.b,
      b: instruction.c,
    ),
    LualikeIrOpcode.geI => compareWord(
      'GEI',
      a: instruction.b,
      b: instruction.c,
    ),
    _ => null,
  };

  if (compare == null) {
    return null;
  }

  return materializeBool(compare);
}

List<LuaBytecodeInstructionWord>? _lowerTableInstructionSequence(
  LualikeIrInstruction instruction,
) {
  return switch (instruction) {
    ABCInstruction(opcode: LualikeIrOpcode.newTable, a: final a, b: final b) =>
      _lowerNewTableSequence(a: a, arraySize: b),
    ABCInstruction(
      opcode: LualikeIrOpcode.setList,
      a: final a,
      b: final b,
      c: final c,
    ) => _lowerSetListSequence(a: a, count: b, startIndex: c),
    ABCInstruction(
      opcode: LualikeIrOpcode.concat,
      a: final a,
      b: final b,
      c: final c,
    ) => _lowerConcatSequence(a: a, startRegister: b, endRegister: c),
    _ => null,
  };
}

List<LuaBytecodeInstructionWord> _lowerNewTableSequence({
  required int a,
  required int arraySize,
}) {
  final normalizedArraySize = math.max(0, arraySize);
  final extraUnit = LuaBytecodeInstructionLayout.maxArgVC + 1;
  final extraArg = normalizedArraySize ~/ extraUnit;
  final inlineArraySize = normalizedArraySize % extraUnit;
  return <LuaBytecodeInstructionWord>[
    LuaBytecodeInstructionWord.vabc(
      opcode: LuaBytecodeOpcodes.byName('NEWTABLE').code,
      a: a,
      b: 0,
      c: inlineArraySize,
      k: extraArg != 0,
    ),
    LuaBytecodeInstructionWord.ax(
      opcode: LuaBytecodeOpcodes.byName('EXTRAARG').code,
      ax: extraArg,
    ),
  ];
}

List<LuaBytecodeInstructionWord> _lowerConcatSequence({
  required int a,
  required int startRegister,
  required int endRegister,
}) {
  final operandCount = endRegister >= startRegister
      ? endRegister - startRegister + 1
      : 1;
  final words = <LuaBytecodeInstructionWord>[
    LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('CONCAT').code,
      a: startRegister,
      b: operandCount,
      c: 0,
    ),
  ];
  if (a != startRegister) {
    words.add(
      LuaBytecodeInstructionWord.abc(
        opcode: LuaBytecodeOpcodes.byName('MOVE').code,
        a: a,
        b: startRegister,
        c: 0,
      ),
    );
  }
  return words;
}

List<LuaBytecodeInstructionWord> _lowerSetListSequence({
  required int a,
  required int count,
  required int startIndex,
}) {
  final normalizedStartIndex = math.max(1, startIndex);
  final startMinusOne = normalizedStartIndex > 1 ? normalizedStartIndex - 1 : 0;
  final extraUnit = LuaBytecodeInstructionLayout.maxArgVC + 1;
  final extraArg = startMinusOne ~/ extraUnit;
  final inlineOffset = startMinusOne % extraUnit;

  final words = <LuaBytecodeInstructionWord>[
    LuaBytecodeInstructionWord.vabc(
      opcode: LuaBytecodeOpcodes.byName('SETLIST').code,
      a: a,
      b: count,
      c: inlineOffset,
      k: extraArg != 0,
    ),
  ];
  if (extraArg != 0) {
    words.add(
      LuaBytecodeInstructionWord.ax(
        opcode: LuaBytecodeOpcodes.byName('EXTRAARG').code,
        ax: extraArg,
      ),
    );
  }
  return words;
}

int _remapPc(int oldPc, List<int> pcMap) {
  if (oldPc <= 0) {
    return 0;
  }
  if (oldPc >= pcMap.length) {
    return pcMap.last;
  }
  return pcMap[oldPc];
}

({List<int> lineInfo, List<LuaBytecodeAbsLineInfo> absoluteLineInfo})
_lowerDebugLines(List<int>? lines, int instructionCount) {
  if (lines == null || lines.isEmpty || !lines.any((line) => line > 0)) {
    return (
      lineInfo: const <int>[],
      absoluteLineInfo: const <LuaBytecodeAbsLineInfo>[],
    );
  }

  final normalized = List<int>.filled(instructionCount, 0, growable: false);
  for (var i = 0; i < instructionCount; i++) {
    if (i < lines.length) {
      normalized[i] = lines[i];
    } else if (i > 0) {
      normalized[i] = normalized[i - 1];
    }
  }

  final lineInfo = List<int>.filled(instructionCount, 0, growable: false);
  final absoluteLineInfo = <LuaBytecodeAbsLineInfo>[
    LuaBytecodeAbsLineInfo(pc: 0, line: normalized.first),
  ];

  for (var index = 1; index < normalized.length; index++) {
    if (index % LuaBytecodeDebugLayout.maxInstructionsWithoutAbsoluteLineInfo ==
        0) {
      absoluteLineInfo.add(
        LuaBytecodeAbsLineInfo(pc: index, line: normalized[index]),
      );
      continue;
    }
    lineInfo[index] = normalized[index] - normalized[index - 1];
  }

  return (
    lineInfo: List<int>.unmodifiable(lineInfo),
    absoluteLineInfo: List<LuaBytecodeAbsLineInfo>.unmodifiable(
      absoluteLineInfo,
    ),
  );
}
