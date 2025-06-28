import 'opcode.dart';

/// A bytecode instruction
class Instruction {
  final OpCode op;
  final List<dynamic> operands;

  const Instruction(this.op, [this.operands = const []]);

  @override
  String toString() => '$op ${operands.join(" ")}';
}

/// A sequence of bytecode instructions making up a program or function
class BytecodeChunk {
  final List<Instruction> instructions;
  final List<dynamic> constants;
  final int numRegisters;
  final String name;
  final bool isMainChunk;

  BytecodeChunk({
    required this.instructions,
    required this.constants,
    required this.numRegisters,
    this.name = '',
    this.isMainChunk = false,
  });

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('$name:');
    for (var i = 0; i < instructions.length; i++) {
      sb.writeln('$i: ${instructions[i]}');
    }
    return sb.toString();
  }
}
