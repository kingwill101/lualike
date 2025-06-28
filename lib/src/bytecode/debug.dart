import 'bytecode.dart';

/// Debug information for a bytecode instruction
class DebugInfo {
  final String sourceLine; // Original source code line
  final int lineNumber; // Line number in source file
  final int columnStart; // Starting column in source
  final int columnEnd; // Ending column in source
  final String sourceFile; // Source file name/path

  const DebugInfo({
    required this.sourceLine,
    required this.lineNumber,
    required this.columnStart,
    required this.columnEnd,
    required this.sourceFile,
  });

  @override
  String toString() =>
      '$sourceFile:$lineNumber:$columnStart-$columnEnd: $sourceLine';
}

/// Extended instruction that includes debug information
class DebugInstruction extends Instruction {
  final DebugInfo? debugInfo;

  const DebugInstruction(super.op, [super.operands = const [], this.debugInfo]);

  @override
  String toString() {
    if (debugInfo != null) {
      return '${super.toString()} // ${debugInfo!.sourceLine}';
    }
    return super.toString();
  }
}

/// Extended chunk that includes debug information
class DebugChunk extends BytecodeChunk {
  final Map<String, String> sourceFiles; // Map of file ID to contents
  final List<String> localNames; // Names of local variables
  final List<String> upvalueNames; // Names of upvalues

  DebugChunk({
    required super.instructions,
    required super.constants,
    required super.numRegisters,
    super.name = '',
    super.isMainChunk = false,
    this.sourceFiles = const {},
    this.localNames = const [],
    this.upvalueNames = const [],
  });

  /// Get debug information for a specific instruction
  DebugInfo? getDebugInfo(int pc) {
    if (pc >= 0 && pc < instructions.length) {
      final instruction = instructions[pc];
      if (instruction is DebugInstruction) {
        return instruction.debugInfo;
      }
    }
    return null;
  }

  /// Get local variable name at index
  String? getLocalName(int index) =>
      index >= 0 && index < localNames.length ? localNames[index] : null;

  /// Get upvalue name at index
  String? getUpvalueName(int index) =>
      index >= 0 && index < upvalueNames.length ? upvalueNames[index] : null;
}
