import 'package:meta/meta.dart';

import 'instruction.dart';

/// Flags applied to a lualike IR chunk/header.
class LualikeIrChunkFlags {
  const LualikeIrChunkFlags({
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

  static LualikeIrChunkFlags fromByte(int data) {
    return LualikeIrChunkFlags(
      hasDebugInfo: (data & 0x01) != 0,
      hasConstantHash: (data & 0x02) != 0,
    );
  }
}

/// Representation of a constant used within a lualike IR prototype.
@immutable
sealed class LualikeIrConstant {
  const LualikeIrConstant();
}

class NilConstant extends LualikeIrConstant {
  const NilConstant();
}

class BooleanConstant extends LualikeIrConstant {
  const BooleanConstant(this.value);

  final bool value;
}

class IntegerConstant extends LualikeIrConstant {
  const IntegerConstant(this.value);

  final int value;
}

class NumberConstant extends LualikeIrConstant {
  const NumberConstant(this.value);

  final double value;
}

class ShortStringConstant extends LualikeIrConstant {
  const ShortStringConstant(this.value);

  final String value;
}

class LongStringConstant extends LualikeIrConstant {
  const LongStringConstant(this.value);

  final String value;
}

/// Descriptor for an upvalue captured by a prototype.
class LualikeIrUpvalueDescriptor {
  const LualikeIrUpvalueDescriptor({
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
class LualikeIrDebugInfo {
  const LualikeIrDebugInfo({
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

/// A lualike IR prototype (function), mirroring Lua's Proto structure.
class LualikeIrPrototype {
  LualikeIrPrototype({
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
  final List<LualikeIrUpvalueDescriptor> upvalueDescriptors;
  final List<LualikeIrInstruction> instructions;
  final List<LualikeIrConstant> constants;
  final List<LualikeIrPrototype> prototypes;
  final int lineDefined;
  final int lastLineDefined;
  final LualikeIrDebugInfo? debugInfo;
  final List<bool> registerConstFlags;
  final Map<int, List<int>> constSealPoints;

  int get upvalueCount => upvalueDescriptors.length;
}

/// Complete lualike IR chunk ready for serialization/execution.
class LualikeIrChunk {
  const LualikeIrChunk({required this.flags, required this.mainPrototype});

  final LualikeIrChunkFlags flags;
  final LualikeIrPrototype mainPrototype;
}
