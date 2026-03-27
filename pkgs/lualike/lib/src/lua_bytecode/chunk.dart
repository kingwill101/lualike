import 'instruction.dart';

abstract final class LuaBytecodeChunkSentinels {
  static const List<int> signature = <int>[0x1b, 0x4c, 0x75, 0x61];
  static const List<int> luacData = <int>[0x19, 0x93, 0x0d, 0x0a, 0x1a, 0x0a];

  // Upstream Lua stores major/minor in a single byte.
  static const int officialVersion = 0x55;
  static const int officialFormat = 0;
  static const int intSize = 4;
  static const int instructionSize = 4;
  static const int luaIntegerSize = 8;
  static const int luaNumberSize = 8;
  static const int luacInt = -0x5678;
  static const int luacInstruction = 0x12345678;
  static const double luacNumber = -370.5;
}

abstract final class LuaBytecodePrototypeFlags {
  static const int hasHiddenVarargs = 0x01;
  static const int hasVarargTable = 0x02;
  static const int fixedMemory = 0x04;
}

abstract final class LuaBytecodeDebugLayout {
  static const int absLineInfoMarker = -0x80;
  static const int maxInstructionsWithoutAbsoluteLineInfo = 128;
}

final class LuaBytecodeChunkHeader {
  const LuaBytecodeChunkHeader({
    required this.signature,
    required this.version,
    required this.format,
    required this.luacData,
    required this.intSize,
    required this.instructionSize,
    required this.luaIntegerSize,
    required this.luaNumberSize,
    required this.luacInt,
    required this.luacInstruction,
    required this.luacNumber,
  });

  const LuaBytecodeChunkHeader.official()
    : this(
        signature: LuaBytecodeChunkSentinels.signature,
        version: LuaBytecodeChunkSentinels.officialVersion,
        format: LuaBytecodeChunkSentinels.officialFormat,
        luacData: LuaBytecodeChunkSentinels.luacData,
        intSize: LuaBytecodeChunkSentinels.intSize,
        instructionSize: LuaBytecodeChunkSentinels.instructionSize,
        luaIntegerSize: LuaBytecodeChunkSentinels.luaIntegerSize,
        luaNumberSize: LuaBytecodeChunkSentinels.luaNumberSize,
        luacInt: LuaBytecodeChunkSentinels.luacInt,
        luacInstruction: LuaBytecodeChunkSentinels.luacInstruction,
        luacNumber: LuaBytecodeChunkSentinels.luacNumber,
      );

  final List<int> signature;
  final int version;
  final int format;
  final List<int> luacData;
  final int intSize;
  final int instructionSize;
  final int luaIntegerSize;
  final int luaNumberSize;
  final int luacInt;
  final int luacInstruction;
  final double luacNumber;

  bool get matchesOfficial =>
      _listEquals(signature, LuaBytecodeChunkSentinels.signature) &&
      version == LuaBytecodeChunkSentinels.officialVersion &&
      format == LuaBytecodeChunkSentinels.officialFormat &&
      _listEquals(luacData, LuaBytecodeChunkSentinels.luacData) &&
      intSize == LuaBytecodeChunkSentinels.intSize &&
      instructionSize == LuaBytecodeChunkSentinels.instructionSize &&
      luaIntegerSize == LuaBytecodeChunkSentinels.luaIntegerSize &&
      luaNumberSize == LuaBytecodeChunkSentinels.luaNumberSize &&
      luacInt == LuaBytecodeChunkSentinels.luacInt &&
      luacInstruction == LuaBytecodeChunkSentinels.luacInstruction &&
      luacNumber == LuaBytecodeChunkSentinels.luacNumber;
}

enum LuaBytecodeConstantTag {
  nil(0x00),
  falseValue(0x01),
  trueValue(0x11),
  integer(0x03),
  float(0x13),
  shortString(0x04),
  longString(0x14);

  const LuaBytecodeConstantTag(this.value);

  final int value;
}

sealed class LuaBytecodeConstant {
  const LuaBytecodeConstant();

  LuaBytecodeConstantTag get tag;
}

final class LuaBytecodeNilConstant extends LuaBytecodeConstant {
  const LuaBytecodeNilConstant();

  @override
  LuaBytecodeConstantTag get tag => LuaBytecodeConstantTag.nil;
}

final class LuaBytecodeBooleanConstant extends LuaBytecodeConstant {
  const LuaBytecodeBooleanConstant(this.value);

  final bool value;

  @override
  LuaBytecodeConstantTag get tag => value
      ? LuaBytecodeConstantTag.trueValue
      : LuaBytecodeConstantTag.falseValue;
}

final class LuaBytecodeIntegerConstant extends LuaBytecodeConstant {
  const LuaBytecodeIntegerConstant(this.value);

  final int value;

  @override
  LuaBytecodeConstantTag get tag => LuaBytecodeConstantTag.integer;
}

final class LuaBytecodeFloatConstant extends LuaBytecodeConstant {
  const LuaBytecodeFloatConstant(this.value);

  final double value;

  @override
  LuaBytecodeConstantTag get tag => LuaBytecodeConstantTag.float;
}

final class LuaBytecodeStringConstant extends LuaBytecodeConstant {
  const LuaBytecodeStringConstant(this.value, {required this.isLong});

  final String value;
  final bool isLong;

  @override
  LuaBytecodeConstantTag get tag => isLong
      ? LuaBytecodeConstantTag.longString
      : LuaBytecodeConstantTag.shortString;
}

enum LuaBytecodeUpvalueKind {
  localRegister(0),
  localConstant(1),
  varargParameter(2),
  toBeClosed(3),
  compileTimeConstant(4),
  globalRegister(5),
  globalConstant(6);

  const LuaBytecodeUpvalueKind(this.value);

  final int value;

  static LuaBytecodeUpvalueKind fromValue(int value) => switch (value) {
    0 => localRegister,
    1 => localConstant,
    2 => varargParameter,
    3 => toBeClosed,
    4 => compileTimeConstant,
    5 => globalRegister,
    6 => globalConstant,
    _ => throw RangeError.value(value, 'value', 'Unknown upvalue kind'),
  };
}

final class LuaBytecodeUpvalueDescriptor {
  const LuaBytecodeUpvalueDescriptor({
    required this.inStack,
    required this.index,
    required this.kind,
    this.name,
  });

  final bool inStack;
  final int index;
  final LuaBytecodeUpvalueKind kind;
  final String? name;
}

final class LuaBytecodeAbsLineInfo {
  const LuaBytecodeAbsLineInfo({required this.pc, required this.line});

  final int pc;
  final int line;
}

final class LuaBytecodeLocalVariableDebugInfo {
  const LuaBytecodeLocalVariableDebugInfo({
    required this.name,
    required this.startPc,
    required this.endPc,
    this.register,
  });

  final String? name;
  final int startPc;
  final int endPc;
  final int? register;
}

final class LuaBytecodePrototype {
  const LuaBytecodePrototype({
    required this.lineDefined,
    required this.lastLineDefined,
    required this.parameterCount,
    required this.flags,
    required this.maxStackSize,
    this.code = const <LuaBytecodeInstructionWord>[],
    this.constants = const <LuaBytecodeConstant>[],
    this.upvalues = const <LuaBytecodeUpvalueDescriptor>[],
    this.prototypes = const <LuaBytecodePrototype>[],
    this.source,
    this.lineInfo = const <int>[],
    this.absoluteLineInfo = const <LuaBytecodeAbsLineInfo>[],
    this.localVariables = const <LuaBytecodeLocalVariableDebugInfo>[],
    this.upvalueNames = const <String?>[],
  });

  final int lineDefined;
  final int lastLineDefined;
  final int parameterCount;
  final int flags;
  final int maxStackSize;
  final List<LuaBytecodeInstructionWord> code;
  final List<LuaBytecodeConstant> constants;
  final List<LuaBytecodeUpvalueDescriptor> upvalues;
  final List<LuaBytecodePrototype> prototypes;
  final String? source;
  final List<int> lineInfo;
  final List<LuaBytecodeAbsLineInfo> absoluteLineInfo;
  final List<LuaBytecodeLocalVariableDebugInfo> localVariables;
  final List<String?> upvalueNames;

  bool get hasHiddenVarargs =>
      (flags & LuaBytecodePrototypeFlags.hasHiddenVarargs) != 0;
  bool get needsVarargTable =>
      (flags & LuaBytecodePrototypeFlags.hasVarargTable) != 0;
  bool get isVararg => hasHiddenVarargs || needsVarargTable;
  bool get isFixedMemory =>
      (flags & LuaBytecodePrototypeFlags.fixedMemory) != 0;
  bool get hasDebugInfo => lineInfo.isNotEmpty;

  /// Returns the cached source line for [pc].
  ///
  /// The VM consults this in the main dispatch loop, so precomputing the
  /// per-PC mapping avoids repeating the checkpoint walk on every instruction.
  int? lineForPc(int pc) {
    if (!hasDebugInfo || pc < 0 || pc >= code.length) {
      return null;
    }
    return _linesByPcFor(this)[pc];
  }

  List<int?> _buildLinesByPc() {
    if (!hasDebugInfo) {
      return List<int?>.filled(code.length, null, growable: false);
    }
    final absoluteLines = <int, int>{
      for (final checkpoint in absoluteLineInfo) checkpoint.pc: checkpoint.line,
    };
    final lines = List<int?>.filled(code.length, null, growable: false);
    var currentLine = lineDefined;
    var basePc = -1;
    for (var pc = 0; pc < code.length; pc++) {
      if (absoluteLines[pc] case final absoluteLine?) {
        currentLine = absoluteLine;
        basePc = pc;
      } else if (pc > basePc) {
        currentLine += pc < lineInfo.length ? lineInfo[pc] : 0;
      }
      lines[pc] = currentLine;
    }
    return lines;
  }

}

final Expando<List<int?>> _prototypeLinesByPc = Expando<List<int?>>(
  'luaBytecodePrototypeLinesByPc',
);

List<int?> _linesByPcFor(LuaBytecodePrototype prototype) {
  final cached = _prototypeLinesByPc[prototype];
  if (cached != null) {
    return cached;
  }
  final built = prototype._buildLinesByPc();
  _prototypeLinesByPc[prototype] = built;
  return built;
}

final class LuaBytecodeBinaryChunk {
  const LuaBytecodeBinaryChunk({
    required this.header,
    required this.rootUpvalueCount,
    required this.mainPrototype,
  });

  final LuaBytecodeChunkHeader header;
  final int rootUpvalueCount;
  final LuaBytecodePrototype mainPrototype;
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}
