import 'dart:math' as math;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/instruction.dart';
import 'package:lualike/src/lua_bytecode/opcode.dart';

/// Mechanically lowers finalized lualike IR into Lua 5.5 bytecode.
///
/// This is **not** an optimization pass. By the time a chunk reaches this
/// layer, register allocation, call shape, closure capture, and control flow
/// must already be decided in IR/SSA (see `doc/decisions.md` IR contract).
///
/// ## Opcode expansion
///
/// Several IR opcodes have no direct bytecode equivalent and are expanded
/// here into 2-3 instruction sequences:
///
/// | IR opcode | Expansion | Reason |
/// |-----------|-----------|--------|
/// | `SHLI a,b,c` | `LOADI tmp,c; SHL a,b,tmp; MMBIN b,tmp,__shl` | IR means `R(b) << c`; Lua SHLI means `c << R(b)` |
/// | `SUBI a,b,c` | `ADDI a,b,-c; MMBINI b,-c,__sub` | ADDI always does `+`; SUBI negates and uses __sub |
/// | `*K` with high C | `LOADK/KX tmp,C; * a,b,tmp; MMBIN …` | C field too small for large constant indices |
/// | `GETFIELD/etc` with high C | `LOADK tmp,C; GETTABLE … tmp` | C field too small |
///
/// These expansions are purely mechanical — they do not introduce new
/// policy decisions. All shape choices are finalized in IR/SSA.
///
/// Debug obligations at this boundary:
/// * Copy IR [LocalDebugEntry] ranges through program-counter remapping.
/// * Preserve [LocalDebugEntry.register] so in-memory prototypes work before
///   serialize; after load, local-register inference recovers them again.
/// * Force main [LuaBytecodePrototype.lineDefined] to `0` (Lua main chunk
///   convention) so the VM does not treat main as a regular function and inject
///   a synthetic `(vararg table)` local for `debug.getlocal`.
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

/// Lowers one finalized IR prototype to a Lua bytecode prototype.
///
/// Only remaps finalized IR instructions and metadata into bytecode fields.
/// Do not add new analyses or heuristics here — put them in IR/SSA instead.
///
/// When [isMainPrototype] is true, [LualikeIrPrototype.lineDefined] is forced
/// to `0` regardless of IR source lines (required for correct main-chunk debug
/// behavior). The main IR prototype must also declare `_ENV` as upvalue 0 with
/// `inStack=1` and `index=0`; lowering validates this closure shape rather than
/// inventing missing metadata.
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
      name: index < loweredUpvalueNames.length
          ? loweredUpvalueNames[index]
          : null,
    ),
    growable: true,
  );
  if (isMainPrototype) {
    _validateRootEnvironmentUpvalue(prototype);
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
  final debugLines = _lowerDebugLines(
    debugInfo?.lineInfo,
    instructions.length,
    pcMap,
  );
  // Keep register + remapped PCs. Serialize drops register; parse re-infers.
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
    // Official Lua main chunks always report linedefined=0. The debug VM
    // uses that to distinguish main from regular Lua functions (e.g. so
    // debug.getlocal does not inject a synthetic "(vararg table)" entry).
    lineDefined: isMainPrototype ? 0 : prototype.lineDefined,
    lastLineDefined: prototype.lastLineDefined,
    parameterCount: prototype.paramCount,
    flags: _prototypeFlags(prototype, isMainPrototype: isMainPrototype),
    // Reserve only scratch slots actually used by mechanical expansions.
    // Do not scan raw ABC fields as registers: immediate and constant fields
    // can contain values that look like register indices.
    maxStackSize: math.max(
      2,
      prototype.registerCount + loweredInstructions.tempSlots,
    ),
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

void _validateRootEnvironmentUpvalue(LualikeIrPrototype prototype) {
  if (prototype.upvalueDescriptors.isEmpty) {
    throw StateError(
      'main IR prototype must declare _ENV as root upvalue 0 before lowering',
    );
  }
  final descriptor = prototype.upvalueDescriptors.first;
  final names = prototype.debugInfo?.upvalueNames ?? const <String>[];
  if (descriptor.inStack != 1 ||
      descriptor.index != 0 ||
      (names.isNotEmpty && names.first != '_ENV')) {
    throw StateError(
      'main IR prototype upvalue 0 must be _ENV with inStack=1 and index=0',
    );
  }
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
  LualikeIrUpvalueDescriptor descriptor, {
  String? name,
}) {
  return LuaBytecodeUpvalueDescriptor(
    inStack: descriptor.inStack != 0,
    index: descriptor.index,
    kind: LuaBytecodeUpvalueKind.fromValue(descriptor.kind),
    name: name,
  );
}

LuaBytecodeInstructionWord _lowerInstruction(LualikeIrInstruction instruction) {
  // SUBI lowers to ADDI with negated immediate: R[a] = R[b] + (-c).
  // The __sub event is carried by the MMBINI followup instead of __add.
  final bcOpcodeName = instruction.opcode == LualikeIrOpcode.subI
      ? 'ADDI'
      : instruction.opcode.name;
  final opcode = LuaBytecodeOpcodes.byName(bcOpcodeName);
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
  if (instruction.opcode == LualikeIrOpcode.varArg) {
    return LuaBytecodeInstructionWord.abc(
      opcode: opcode,
      a: instruction.a,
      b: 0,
      c: instruction.b,
      k: instruction.k,
    );
  }
  // SUBI → ADDI with negated C: bytecode ADDI does R[a]=R[b]+C_signed,
  // but SUBI means R[a]=R[b]-c. Emit ADDI with C = -c.
  if (instruction.opcode == LualikeIrOpcode.subI) {
    final negC = -instruction.c;
    return LuaBytecodeInstructionWord.abc(
      opcode: opcode,
      a: instruction.a,
      b: _encodeBOperand(instruction.opcode, instruction.b),
      c: _encodeCOperand(instruction.opcode, negC),
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
    LualikeIrOpcode.addI ||
    LualikeIrOpcode.subI ||
    LualikeIrOpcode.shlI ||
    LualikeIrOpcode.shrI => true,
    _ => false,
  };
}

({
  List<LuaBytecodeInstructionWord> instructions,
  List<int> pcMap,
  int tempSlots,
})
_lowerInstructions(
  List<LualikeIrInstruction> instructions, {
  required int tempBase,
}) {
  final lowered = <LuaBytecodeInstructionWord>[];
  final pcMap = List<int>.filled(instructions.length + 1, 0, growable: false);
  var tempSlots = 0;

  for (var oldPc = 0; oldPc < instructions.length; oldPc++) {
    pcMap[oldPc] = lowered.length;
    try {
      final sequence = _lowerInstructionSequence(
        instructions[oldPc],
        tempBase: tempBase,
      );
      lowered.addAll(sequence.instructions);
      tempSlots = math.max(tempSlots, sequence.tempSlots);
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
        final targetNewPc =
            pcMap[_checkedJumpTarget(
              targetOldPc,
              instructions.length,
              oldPc: oldPc,
              opcode: instruction.opcode,
            )];
        lowered[newPc] = LuaBytecodeInstructionWord.sj(
          opcode: LuaBytecodeOpcodes.byName('JMP').code,
          sJ: targetNewPc - newPc - 1,
        );
      case AsBxInstruction(opcode: final opcode, a: final a, sBx: final sBx)
          when opcode == LualikeIrOpcode.forPrep ||
              opcode == LualikeIrOpcode.forLoop:
        final targetOldPc = oldPc + 1 + sBx;
        final remappedTarget = opcode == LualikeIrOpcode.forPrep
            ? targetOldPc + 1
            : targetOldPc;
        final targetNewPc =
            pcMap[_checkedJumpTarget(
              remappedTarget,
              instructions.length,
              oldPc: oldPc,
              opcode: opcode,
            )];
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
        final targetNewPc =
            pcMap[_checkedJumpTarget(
              targetOldPc,
              instructions.length,
              oldPc: oldPc,
              opcode: opcode,
            )];
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
    tempSlots: tempSlots,
  );
}

int _checkedJumpTarget(
  int target,
  int instructionCount, {
  required int oldPc,
  required LualikeIrOpcode opcode,
}) {
  if (target < 0 || target > instructionCount) {
    throw StateError(
      'invalid ${opcode.name} target $target at IR pc=$oldPc '
      '(instruction count $instructionCount)',
    );
  }
  return target;
}

({List<LuaBytecodeInstructionWord> instructions, int tempSlots})
_lowerInstructionSequence(
  LualikeIrInstruction instruction, {
  required int tempBase,
}) {
  if (instruction is ABCInstruction) {
    final leftShiftImmediate = _lowerLeftShiftImmediateSequence(
      instruction,
      tempBase: tempBase,
    );
    if (leftShiftImmediate != null) {
      return (instructions: leftShiftImmediate, tempSlots: 1);
    }
  }

  final arithmetic = _lowerArithmeticMetamethodSequence(
    instruction,
    tempBase: tempBase,
  );
  if (arithmetic != null) {
    final usesTemp =
        instruction is ABCInstruction &&
        _registerArithmeticOpcode(instruction.opcode) != null &&
        instruction.c > LuaBytecodeInstructionLayout.maxArgC;
    return (instructions: arithmetic, tempSlots: usesTemp ? 1 : 0);
  }
  final highConstant = _lowerHighConstantSequence(
    instruction,
    tempBase: tempBase,
  );
  if (highConstant != null) {
    final slots = instruction.opcode == LualikeIrOpcode.setTabUp ? 2 : 1;
    return (instructions: highConstant, tempSlots: slots);
  }
  final table = _lowerTableInstructionSequence(instruction);
  if (table != null) {
    return (instructions: table, tempSlots: 0);
  }
  if (instruction is ABCInstruction) {
    final compare = _lowerCompareSequence(instruction, tempBase: tempBase);
    if (compare != null) {
      return (
        instructions: compare,
        tempSlots: _compareUsesTemp(instruction) ? 1 : 0,
      );
    }
  }
  return (
    instructions: <LuaBytecodeInstructionWord>[_lowerInstruction(instruction)],
    tempSlots: 0,
  );
}

List<LuaBytecodeInstructionWord>? _lowerLeftShiftImmediateSequence(
  ABCInstruction instruction, {
  required int tempBase,
}) {
  if (instruction.opcode != LualikeIrOpcode.shlI) {
    return null;
  }

  final immediate = instruction.c;
  return <LuaBytecodeInstructionWord>[
    LuaBytecodeInstructionWord.asBx(
      opcode: LuaBytecodeOpcodes.byName('LOADI').code,
      a: tempBase,
      sBx: immediate,
    ),
    LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('SHL').code,
      a: instruction.a,
      b: instruction.b,
      c: tempBase,
    ),
    LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBIN').code,
      a: instruction.b,
      b: tempBase,
      c: _binaryMetamethodEvent(LualikeIrOpcode.shl)!,
      k: instruction.k,
    ),
  ];
}

List<LuaBytecodeInstructionWord>? _lowerArithmeticMetamethodSequence(
  LualikeIrInstruction instruction, {
  required int tempBase,
}) {
  if (instruction is! ABCInstruction) {
    return null;
  }

  final event = _binaryMetamethodEvent(instruction.opcode);
  if (event == null) {
    return null;
  }

  final registerOpcode = _registerArithmeticOpcode(instruction.opcode);
  if (registerOpcode != null &&
      instruction.c > LuaBytecodeInstructionLayout.maxArgC) {
    return <LuaBytecodeInstructionWord>[
      ..._loadConstantToRegisterSequence(tempBase, instruction.c),
      LuaBytecodeInstructionWord.abc(
        opcode: LuaBytecodeOpcodes.byName(registerOpcode).code,
        a: instruction.a,
        b: instruction.b,
        c: tempBase,
      ),
      LuaBytecodeInstructionWord.abc(
        opcode: LuaBytecodeOpcodes.byName('MMBIN').code,
        a: instruction.b,
        b: tempBase,
        c: event,
        k: instruction.k,
      ),
    ];
  }

  final primary = _lowerInstruction(instruction);
  // MMBIN* A is the **left operand register** (luac55), not the arithmetic
  // destination. Destination is recovered from the previous instruction's A
  // when the metamethod path runs (see Opcode.mmBin* handlers).
  final followup = switch (instruction.opcode) {
    LualikeIrOpcode.addI => LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBINI').code,
      a: instruction.b,
      b: _encodeCOperand(instruction.opcode, instruction.c),
      c: event,
      k: instruction.k,
    ),
    // SUBI negates the immediate (ADDI does R[b]+C, SUBI is R[b]-c).
    LualikeIrOpcode.subI => LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBINI').code,
      a: instruction.b,
      b: _encodeCOperand(instruction.opcode, -instruction.c),
      c: event,
      k: instruction.k,
    ),
    LualikeIrOpcode.shlI ||
    LualikeIrOpcode.shrI => LuaBytecodeInstructionWord.abc(
      opcode: LuaBytecodeOpcodes.byName('MMBINI').code,
      a: instruction.b,
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
      a: instruction.b,
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

String? _registerArithmeticOpcode(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.addK => 'ADD',
    LualikeIrOpcode.subK => 'SUB',
    LualikeIrOpcode.mulK => 'MUL',
    LualikeIrOpcode.modK => 'MOD',
    LualikeIrOpcode.powK => 'POW',
    LualikeIrOpcode.divK => 'DIV',
    LualikeIrOpcode.idivK => 'IDIV',
    LualikeIrOpcode.bandK => 'BAND',
    LualikeIrOpcode.borK => 'BOR',
    LualikeIrOpcode.bxorK => 'BXOR',
    _ => null,
  };
}

int? _binaryMetamethodEvent(LualikeIrOpcode opcode) {
  return switch (opcode) {
    LualikeIrOpcode.add || LualikeIrOpcode.addI || LualikeIrOpcode.addK => 6,
    LualikeIrOpcode.sub || LualikeIrOpcode.subI || LualikeIrOpcode.subK => 7,
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
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC =>
      <LuaBytecodeInstructionWord>[
        ...loadKey(tempBase, instruction.c),
        LuaBytecodeInstructionWord.abc(
          opcode: LuaBytecodeOpcodes.byName('GETTABLE').code,
          a: instruction.a,
          b: instruction.b,
          c: tempBase,
        ),
      ],
    LualikeIrOpcode.setField
        when instruction.b > LuaBytecodeInstructionLayout.maxArgB =>
      <LuaBytecodeInstructionWord>[
        ...loadKey(tempBase, instruction.b),
        LuaBytecodeInstructionWord.abc(
          opcode: LuaBytecodeOpcodes.byName('SETTABLE').code,
          a: instruction.a,
          b: tempBase,
          c: instruction.c,
          k: instruction.k,
        ),
      ],
    LualikeIrOpcode.getTabUp
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC =>
      <LuaBytecodeInstructionWord>[
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
        when instruction.b > LuaBytecodeInstructionLayout.maxArgB =>
      <LuaBytecodeInstructionWord>[
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
          k: instruction.k,
        ),
      ],
    LualikeIrOpcode.selfOp
        when instruction.c > LuaBytecodeInstructionLayout.maxArgC =>
      <LuaBytecodeInstructionWord>[
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
  ABCInstruction instruction, {
  required int tempBase,
}) {
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
      // k=true: skip next when condition is FALSE (for `==`).
      // k=false: skip next when condition is TRUE (for `~=` / `!=`).
      k: instruction.k,
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
      LuaBytecodeInstructionLayout.fitsSignedArgC(value);

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
      k: instruction.k,
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
    case LualikeIrOpcode.eqI when !signedImmediateFits(instruction.c):
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
    case LualikeIrOpcode.ltI when !signedImmediateFits(instruction.c):
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
    case LualikeIrOpcode.leI when !signedImmediateFits(instruction.c):
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
    case LualikeIrOpcode.gtI when !signedImmediateFits(instruction.c):
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
    case LualikeIrOpcode.geI when !signedImmediateFits(instruction.c):
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

bool _compareUsesTemp(ABCInstruction instruction) {
  final signedImmediateFits = LuaBytecodeInstructionLayout.fitsSignedArgC(
    instruction.c,
  );
  return switch (instruction.opcode) {
    LualikeIrOpcode.eqK => instruction.c > LuaBytecodeInstructionLayout.maxArgC,
    LualikeIrOpcode.eqI ||
    LualikeIrOpcode.ltI ||
    LualikeIrOpcode.leI ||
    LualikeIrOpcode.gtI ||
    LualikeIrOpcode.geI => !signedImmediateFits,
    _ => false,
  };
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
    ) =>
      _lowerSetListSequence(a: a, count: b, startIndex: c),
    ABCInstruction(
      opcode: LualikeIrOpcode.concat,
      a: final a,
      b: final b,
      c: final c,
    ) =>
      _lowerConcatSequence(a: a, startRegister: b, endRegister: c),
    _ => null,
  };
}

List<LuaBytecodeInstructionWord> _lowerNewTableSequence({
  required int a,
  required int arraySize,
}) {
  if (arraySize < 0) {
    throw ArgumentError.value(arraySize, 'arraySize', 'must be non-negative');
  }
  final extraUnit = LuaBytecodeInstructionLayout.maxArgVC + 1;
  final extraArg = arraySize ~/ extraUnit;
  final inlineArraySize = arraySize % extraUnit;
  return <LuaBytecodeInstructionWord>[
    LuaBytecodeInstructionWord.vabc(
      opcode: LuaBytecodeOpcodes.byName('NEWTABLE').code,
      a: a,
      b: 0,
      c: inlineArraySize,
      k: extraArg != 0,
    ),
    if (extraArg != 0)
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
  if (endRegister < startRegister) {
    throw ArgumentError(
      'CONCAT end register $endRegister precedes start register '
      '$startRegister',
    );
  }
  final operandCount = endRegister - startRegister + 1;
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
  if (startIndex < 1) {
    throw ArgumentError.value(startIndex, 'startIndex', 'must be at least 1');
  }
  final startMinusOne = startIndex - 1;
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
_lowerDebugLines(List<int>? lines, int instructionCount, List<int> pcMap) {
  if (instructionCount == 0 ||
      lines == null ||
      lines.isEmpty ||
      !lines.any((line) => line > 0)) {
    return (
      lineInfo: const <int>[],
      absoluteLineInfo: const <LuaBytecodeAbsLineInfo>[],
    );
  }

  final normalized = List<int>.filled(instructionCount, 0, growable: false);
  final lineCount = math.min(lines.length, pcMap.length - 1);
  for (var oldPc = 0; oldPc < lineCount; oldPc++) {
    if (lines[oldPc] == 0) continue;
    final start = pcMap[oldPc];
    final end = (oldPc + 1 < pcMap.length)
        ? pcMap[oldPc + 1]
        : instructionCount;
    for (var newPc = start; newPc < end && newPc < instructionCount; newPc++) {
      normalized[newPc] = lines[oldPc];
    }
  }
  // forward-fill any zeros from the previous non-zero
  for (var i = 1; i < instructionCount; i++) {
    if (normalized[i] == 0 && normalized[i - 1] > 0) {
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
