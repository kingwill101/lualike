import 'dart:math' as math;

import 'chunk.dart';
import 'instruction.dart';
import '../number_limits.dart';
import '../number_utils.dart';
import 'opcode.dart';

const int luaBytecodeMaxShortStringLength = 40;

final class LuaBytecodeChunkBuilder {
  LuaBytecodeChunkBuilder.foundation({
    required String chunkName,
    String? sourceName,
  }) : mainPrototype = LuaBytecodePrototypeBuilder.main(
         source: sourceName ?? _normalizeChunkSource(chunkName),
       );

  final LuaBytecodePrototypeBuilder mainPrototype;

  LuaBytecodeBinaryChunk build() {
    return LuaBytecodeBinaryChunk(
      header: const LuaBytecodeChunkHeader.official(),
      rootUpvalueCount: mainPrototype.upvalues.length,
      mainPrototype: mainPrototype.build(),
    );
  }
}

final class LuaBytecodePrototypeBuilder {
  LuaBytecodePrototypeBuilder({
    required this.lineDefined,
    required this.lastLineDefined,
    required this.parameterCount,
    required this.flags,
    required this.source,
  });

  factory LuaBytecodePrototypeBuilder.main({required String source}) {
    final builder = LuaBytecodePrototypeBuilder(
      lineDefined: 0,
      lastLineDefined: 0,
      parameterCount: 0,
      flags: LuaBytecodePrototypeFlags.hasHiddenVarargs,
      source: source,
    );
    builder.addUpvalue(
      const LuaBytecodeUpvalueDescriptor(
        inStack: true,
        index: 0,
        kind: LuaBytecodeUpvalueKind.localRegister,
        name: '_ENV',
      ),
    );
    return builder;
  }

  final int lineDefined;
  final int lastLineDefined;
  final int parameterCount;
  final int flags;
  final String source;
  final List<LuaBytecodeInstructionWord> _code = <LuaBytecodeInstructionWord>[];
  final List<LuaBytecodeConstant> _constants = <LuaBytecodeConstant>[];
  final List<LuaBytecodeUpvalueDescriptor> upvalues =
      <LuaBytecodeUpvalueDescriptor>[];
  final List<LuaBytecodePrototypeBuilder> children =
      <LuaBytecodePrototypeBuilder>[];
  final List<LuaBytecodeLocalVariableDebugInfo> _localVariables =
      <LuaBytecodeLocalVariableDebugInfo>[];
  final Map<Object, int> _constantIndexes = <Object, int>{};
  var _maxStackSize = 2;

  int get currentPc => _code.length;
  int get maxStackSize => _maxStackSize;

  void ensureStack(int registers) {
    _maxStackSize = math.max(_maxStackSize, math.max(2, registers));
  }

  void addUpvalue(LuaBytecodeUpvalueDescriptor upvalue) {
    upvalues.add(upvalue);
  }

  int addChildPrototype(LuaBytecodePrototypeBuilder child) {
    final index = children.length;
    children.add(child);
    return index;
  }

  void addLocalVariable({
    required String name,
    required int startPc,
    required int endPc,
  }) {
    _localVariables.add(
      LuaBytecodeLocalVariableDebugInfo(
        name: name,
        startPc: startPc,
        endPc: endPc,
      ),
    );
  }

  int addConstant(LuaBytecodeConstant constant) {
    final key = switch (constant) {
      LuaBytecodeNilConstant() => ('nil',),
      LuaBytecodeBooleanConstant(value: final value) => ('bool', value),
      LuaBytecodeIntegerConstant(value: final value) => ('int', value),
      LuaBytecodeFloatConstant(value: final value) => ('float', value),
      LuaBytecodeStringConstant(value: final value, isLong: final isLong) => (
        'string',
        value,
        isLong,
      ),
    };
    final existing = _constantIndexes[key];
    if (existing != null) {
      return existing;
    }

    final index = _constants.length;
    _constants.add(constant);
    _constantIndexes[key] = index;
    return index;
  }

  int addStringConstant(String value) {
    return addConstant(
      LuaBytecodeStringConstant(
        value,
        isLong: value.codeUnits.length > luaBytecodeMaxShortStringLength,
      ),
    );
  }

  void emitVarargPrep({int register = 0}) {
    emitAbc('VARARGPREP', a: register, b: 0, c: 0);
  }

  void emitMove({required int target, required int source}) {
    ensureStack(math.max(target, source) + 1);
    emitAbc('MOVE', a: target, b: source, c: 0);
  }

  void emitGetTabUp({
    required int target,
    required int upvalue,
    required int constantIndex,
  }) {
    ensureStack(target + 1);
    emitAbc('GETTABUP', a: target, b: upvalue, c: constantIndex);
  }

  void emitGetUpvalue({required int target, required int upvalue}) {
    ensureStack(target + 1);
    emitAbc('GETUPVAL', a: target, b: upvalue, c: 0);
  }

  void emitGetTable({
    required int target,
    required int table,
    required int key,
  }) {
    ensureStack(math.max(target, math.max(table, key)) + 1);
    emitAbc('GETTABLE', a: target, b: table, c: key);
  }

  void emitGetI({required int target, required int table, required int index}) {
    ensureStack(math.max(target, table) + 1);
    emitAbc('GETI', a: target, b: table, c: index);
  }

  void emitGetField({
    required int target,
    required int table,
    required int constantIndex,
  }) {
    ensureStack(math.max(target, table) + 1);
    emitAbc('GETFIELD', a: target, b: table, c: constantIndex);
  }

  void emitSelf({
    required int target,
    required int receiver,
    required int constantIndex,
  }) {
    ensureStack(math.max(target + 2, receiver + 1));
    emitAbc('SELF', a: target, b: receiver, c: constantIndex);
  }

  void emitSetUpvalue({required int source, required int upvalue}) {
    ensureStack(source + 1);
    emitAbc('SETUPVAL', a: source, b: upvalue, c: 0);
  }

  void emitSetTabUp({
    required int upvalue,
    required int constantIndex,
    required int source,
  }) {
    ensureStack(source + 1);
    emitAbc('SETTABUP', a: upvalue, b: constantIndex, c: source);
  }

  void emitSetField({
    required int table,
    required int constantIndex,
    required int source,
  }) {
    ensureStack(math.max(table, source) + 1);
    emitAbc('SETFIELD', a: table, b: constantIndex, c: source);
  }

  void emitSetI({required int table, required int index, required int source}) {
    ensureStack(math.max(table, source) + 1);
    emitAbc('SETI', a: table, b: index, c: source);
  }

  void emitSetTable({
    required int table,
    required int key,
    required int source,
  }) {
    ensureStack(math.max(table, math.max(key, source)) + 1);
    emitAbc('SETTABLE', a: table, b: key, c: source);
  }

  void emitSetList({
    required int table,
    required int count,
    required int startIndex,
  }) {
    ensureStack(table + (count > 0 ? count : 1) + 1);
    final startMinusOne = startIndex > 1 ? startIndex - 1 : 0;
    final extraUnit = LuaBytecodeInstructionLayout.maxArgVC + 1;
    final extraArg = startMinusOne ~/ extraUnit;
    final inlineOffset = startMinusOne % extraUnit;
    emitVabc('SETLIST', a: table, b: count, c: inlineOffset, k: extraArg != 0);
    if (extraArg != 0) {
      emitExtraArg(ax: extraArg);
    }
  }

  void emitNewTable({required int target, int arraySize = 0}) {
    ensureStack(target + 1);
    final normalizedArraySize = math.max(0, arraySize);
    final extraUnit = LuaBytecodeInstructionLayout.maxArgVC + 1;
    final extraArg = normalizedArraySize ~/ extraUnit;
    final inlineArraySize = normalizedArraySize % extraUnit;
    emitVabc('NEWTABLE', a: target, b: 0, c: inlineArraySize, k: extraArg != 0);
    emitExtraArg(ax: extraArg);
  }

  void emitLoadNil({required int target, int count = 1}) {
    if (count <= 0) {
      return;
    }
    ensureStack(target + count);
    emitAbc('LOADNIL', a: target, b: count - 1, c: 0);
  }

  void emitLoadLiteral({required int target, required Object? literal}) {
    ensureStack(target + 1);
    switch (literal) {
      case null:
        emitLoadNil(target: target);
      case bool value:
        emitAbc(value ? 'LOADTRUE' : 'LOADFALSE', a: target, b: 0, c: 0);
      case int value when _canUseSignedBxLiteral(value):
        emitAsBx('LOADI', a: target, sBx: value);
      case int value:
        emitLoadConstant(
          target: target,
          constant: LuaBytecodeIntegerConstant(value),
        );
      case BigInt value:
        final narrowed = _toLuaInteger(value);
        if (_canUseSignedBxLiteral(narrowed)) {
          emitAsBx('LOADI', a: target, sBx: narrowed);
        } else {
          emitLoadConstant(
            target: target,
            constant: LuaBytecodeIntegerConstant(narrowed),
          );
        }
      case double value:
        emitLoadConstant(
          target: target,
          constant: LuaBytecodeFloatConstant(value),
        );
      case String value:
        emitLoadConstant(
          target: target,
          constant: LuaBytecodeStringConstant(
            value,
            isLong: value.codeUnits.length > luaBytecodeMaxShortStringLength,
          ),
        );
      default:
        throw UnsupportedError(
          'Unsupported emitted literal type ${literal.runtimeType}',
        );
    }
  }

  void emitLoadConstant({
    required int target,
    required LuaBytecodeConstant constant,
  }) {
    ensureStack(target + 1);
    final index = addConstant(constant);
    emitAbx('LOADK', a: target, bx: index);
  }

  void emitReturn({required int firstRegister, required int resultCount}) {
    ensureStack(firstRegister + math.max(resultCount, 1));
    emitAbc('RETURN', a: firstRegister, b: resultCount + 1, c: 1);
  }

  void emitCall({
    required int baseRegister,
    required int argumentCount,
    required int resultCount,
  }) {
    ensureStack(
      baseRegister + math.max(argumentCount + 1, math.max(resultCount, 1)),
    );
    emitAbc(
      'CALL',
      a: baseRegister,
      b: argumentCount + 1,
      c: resultCount == 0 ? 1 : resultCount + 1,
    );
  }

  void emitCallWithOpenResults({
    required int baseRegister,
    required int argumentCount,
  }) {
    ensureStack(baseRegister + argumentCount + 1);
    emitAbc('CALL', a: baseRegister, b: argumentCount + 1, c: 0);
  }

  void emitCallWithOpenArguments({
    required int baseRegister,
    required int resultCount,
  }) {
    ensureStack(baseRegister + 1);
    emitAbc(
      'CALL',
      a: baseRegister,
      b: 0,
      c: resultCount == 0 ? 1 : resultCount + 1,
    );
  }

  void emitCallWithOpenArgumentsAndResults({required int baseRegister}) {
    ensureStack(baseRegister + 1);
    emitAbc('CALL', a: baseRegister, b: 0, c: 0);
  }

  void emitTailCall({required int baseRegister, required int argumentCount}) {
    ensureStack(baseRegister + argumentCount + 1);
    emitAbc('TAILCALL', a: baseRegister, b: argumentCount + 1, c: 1);
  }

  void emitTailCallWithOpenArguments({required int baseRegister}) {
    ensureStack(baseRegister + 1);
    emitAbc('TAILCALL', a: baseRegister, b: 0, c: 1);
  }

  void emitOpenReturn({required int firstRegister}) {
    ensureStack(firstRegister + 1);
    emitAbc('RETURN', a: firstRegister, b: 0, c: 1);
  }

  void emitVararg({required int target, required int resultCount}) {
    ensureStack(target + math.max(resultCount, 1));
    emitAbc(
      'VARARG',
      a: target,
      b: 0,
      c: resultCount == 0 ? 0 : resultCount + 1,
    );
  }

  int emitTForPrepPlaceholder({required int baseRegister}) {
    return emitAbxPlaceholder('TFORPREP', a: baseRegister);
  }

  void emitTForCall({
    required int baseRegister,
    required int loopVariableCount,
  }) {
    ensureStack(baseRegister + 4 + loopVariableCount);
    emitAbc('TFORCALL', a: baseRegister, b: 0, c: loopVariableCount);
  }

  void emitTForLoop({required int baseRegister, required int bx}) {
    ensureStack(baseRegister + 4);
    emitAbx('TFORLOOP', a: baseRegister, bx: bx);
  }

  void emitClose({required int fromRegister}) {
    ensureStack(fromRegister + 1);
    emitAbc('CLOSE', a: fromRegister, b: 0, c: 0);
  }

  void emitTest({required int register, required bool kFlag}) {
    ensureStack(register + 1);
    emitAbc('TEST', a: register, b: 0, c: 0, k: kFlag);
  }

  void emitClosure({required int target, required int childIndex}) {
    ensureStack(target + 1);
    emitAbx('CLOSURE', a: target, bx: childIndex);
  }

  void emitJump(int offset) {
    final opcode = LuaBytecodeOpcodes.byName('JMP');
    _code.add(LuaBytecodeInstructionWord.sj(opcode: opcode.code, sJ: offset));
  }

  int emitJumpPlaceholder() {
    final pc = currentPc;
    emitJump(0);
    return pc;
  }

  int emitAbxPlaceholder(String opcodeName, {required int a}) {
    final pc = currentPc;
    emitAbx(opcodeName, a: a, bx: 0);
    return pc;
  }

  void patchJumpTarget({required int instructionPc, required int targetPc}) {
    final opcodeValue = _code[instructionPc].opcodeValue;
    _code[instructionPc] = LuaBytecodeInstructionWord.sj(
      opcode: opcodeValue,
      sJ: targetPc - instructionPc - 1,
    );
  }

  void patchBx({required int instructionPc, required int bx}) {
    final word = _code[instructionPc];
    _code[instructionPc] = LuaBytecodeInstructionWord.abx(
      opcode: word.opcodeValue,
      a: word.a,
      bx: bx,
    );
  }

  void emitAbc(
    String opcodeName, {
    required int a,
    required int b,
    required int c,
    bool k = false,
  }) {
    final opcode = LuaBytecodeOpcodes.byName(opcodeName);
    _code.add(
      LuaBytecodeInstructionWord.abc(
        opcode: opcode.code,
        a: a,
        b: b,
        c: c,
        k: k,
      ),
    );
  }

  void emitAbx(String opcodeName, {required int a, required int bx}) {
    final opcode = LuaBytecodeOpcodes.byName(opcodeName);
    _code.add(
      LuaBytecodeInstructionWord.abx(opcode: opcode.code, a: a, bx: bx),
    );
  }

  void emitVabc(
    String opcodeName, {
    required int a,
    required int b,
    required int c,
    bool k = false,
  }) {
    final opcode = LuaBytecodeOpcodes.byName(opcodeName);
    _code.add(
      LuaBytecodeInstructionWord.vabc(
        opcode: opcode.code,
        a: a,
        b: b,
        c: c,
        k: k,
      ),
    );
  }

  void emitExtraArg({required int ax}) {
    final opcode = LuaBytecodeOpcodes.byName('EXTRAARG');
    _code.add(LuaBytecodeInstructionWord.ax(opcode: opcode.code, ax: ax));
  }

  void emitAsBx(String opcodeName, {required int a, required int sBx}) {
    final opcode = LuaBytecodeOpcodes.byName(opcodeName);
    _code.add(
      LuaBytecodeInstructionWord.asBx(opcode: opcode.code, a: a, sBx: sBx),
    );
  }

  LuaBytecodePrototype build() {
    return LuaBytecodePrototype(
      lineDefined: lineDefined,
      lastLineDefined: lastLineDefined,
      parameterCount: parameterCount,
      flags: flags,
      maxStackSize: _maxStackSize,
      code: List<LuaBytecodeInstructionWord>.unmodifiable(_code),
      constants: List<LuaBytecodeConstant>.unmodifiable(_constants),
      upvalues: List<LuaBytecodeUpvalueDescriptor>.unmodifiable(upvalues),
      prototypes: List<LuaBytecodePrototype>.unmodifiable([
        for (final child in children) child.build(),
      ]),
      source: source,
      localVariables: List<LuaBytecodeLocalVariableDebugInfo>.unmodifiable(
        _localVariables,
      ),
      upvalueNames: List<String?>.unmodifiable([
        for (final upvalue in upvalues) upvalue.name,
      ]),
    );
  }
}

String _normalizeChunkSource(String chunkName) {
  if (chunkName.isEmpty) {
    return '=(lua_bytecode emitter)';
  }
  if (chunkName.startsWith('@') || chunkName.startsWith('=')) {
    return chunkName;
  }
  return '@$chunkName';
}

bool _canUseSignedBxLiteral(int value) {
  return value >= -LuaBytecodeInstructionLayout.offsetSBx &&
      value <= LuaBytecodeInstructionLayout.offsetSBx;
}

int _toLuaInteger(BigInt value) {
  final integer = NumberUtils.toBigInt(value);
  if (integer < BigInt.from(NumberLimits.minInteger) ||
      integer > BigInt.from(NumberLimits.maxInteger)) {
    throw UnsupportedError(
      'Lua bytecode foundation only supports 64-bit integer literals',
    );
  }
  return integer.toInt();
}
