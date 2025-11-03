import 'package:meta/meta.dart';

import 'instruction.dart';

/// Flags applied to a bytecode chunk/header.
class BytecodeChunkFlags {
  const BytecodeChunkFlags({
    this.hasDebugInfo = false,
    this.hasConstantHash = false,
  });

  final bool hasDebugInfo;
  final bool hasConstantHash;

  int toByte() {
    var value = 0;
    if (hasDebugInfo) {
      value |= 0x01;
    }
    if (hasConstantHash) {
      value |= 0x02;
    }
    return value;
  }

  static BytecodeChunkFlags fromByte(int data) {
    return BytecodeChunkFlags(
      hasDebugInfo: (data & 0x01) != 0,
      hasConstantHash: (data & 0x02) != 0,
    );
  }
}

/// Representation of a constant used within a bytecode prototype.
@immutable
sealed class BytecodeConstant {
  const BytecodeConstant();
}

class NilConstant extends BytecodeConstant {
  const NilConstant();
}

class BooleanConstant extends BytecodeConstant {
  const BooleanConstant(this.value);

  final bool value;
}

class IntegerConstant extends BytecodeConstant {
  const IntegerConstant(this.value);

  final int value;
}

class NumberConstant extends BytecodeConstant {
  const NumberConstant(this.value);

  final double value;
}

class ShortStringConstant extends BytecodeConstant {
  const ShortStringConstant(this.value);

  final String value;
}

class LongStringConstant extends BytecodeConstant {
  const LongStringConstant(this.value);

  final String value;
}

/// Descriptor for an upvalue captured by a prototype.
class BytecodeUpvalueDescriptor {
  const BytecodeUpvalueDescriptor({
    required this.inStack,
    required this.index,
    this.kind = 0,
  });

  /// Whether the upvalue references the current stack (1) or an enclosing closure (0).
  final int inStack;

  /// Register or upvalue index depending on [inStack].
  final int index;

  /// Reserved for future use; mirrors Lua's "kind" byte.
  final int kind;
}

/// Debug info associated with a prototype.
class BytecodeDebugInfo {
  const BytecodeDebugInfo({
    required this.lineInfo,
    required this.absoluteSourcePath,
    this.localNames = const [],
    this.upvalueNames = const [],
  });

  /// Line number for each instruction (packed form optional).
  final List<int> lineInfo;

  /// Optional absolute source path for stack traces.
  final String? absoluteSourcePath;

  /// Local variable names with their lifetimes.
  final List<LocalDebugEntry> localNames;

  /// Upvalue names.
  final List<String> upvalueNames;
}

/// Local variable debug entry.
class LocalDebugEntry {
  const LocalDebugEntry({
    required this.name,
    required this.startPc,
    required this.endPc,
  });

  final String name;
  final int startPc;
  final int endPc;
}

/// A bytecode prototype (function), mirroring Lua's Proto structure.
class BytecodePrototype {
  BytecodePrototype({
    required this.registerCount,
    required this.paramCount,
    required this.isVararg,
    required this.upvalueDescriptors,
    required this.instructions,
    required this.constants,
    required this.prototypes,
    required this.lineDefined,
    required this.lastLineDefined,
    this.debugInfo,
    required this.registerConstFlags,
    required this.constSealPoints,
  });

  final int registerCount;
  final int paramCount;
  final bool isVararg;
  final List<BytecodeUpvalueDescriptor> upvalueDescriptors;
  final List<BytecodeInstruction> instructions;
  final List<BytecodeConstant> constants;
  final List<BytecodePrototype> prototypes;
  final int lineDefined;
  final int lastLineDefined;
  final BytecodeDebugInfo? debugInfo;
  final List<bool> registerConstFlags;
  final Map<int, List<int>> constSealPoints;

  int get upvalueCount => upvalueDescriptors.length;
}

/// Complete bytecode chunk ready for serialization/execution.
class BytecodeChunk {
  const BytecodeChunk({required this.flags, required this.mainPrototype});

  final BytecodeChunkFlags flags;
  final BytecodePrototype mainPrototype;
}
