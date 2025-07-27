import 'bytecode.dart';
import 'opcode.dart';

/// Bytecode optimization passes
class BytecodeOptimizer {
  /// Run all optimization passes on a chunk
  static BytecodeChunk optimize(BytecodeChunk chunk) {
    var instructions = List.of(chunk.instructions);

    instructions = _eliminateDeadCode(instructions);
    instructions = _peepholeOptimize(instructions);
    instructions = _foldConstants(instructions, chunk.constants);
    instructions = _eliminateNoOps(instructions);

    return BytecodeChunk(
      instructions: instructions,
      constants: chunk.constants,
      numRegisters: chunk.numRegisters,
      name: chunk.name,
      isMainChunk: chunk.isMainChunk,
    );
  }

  /// Eliminate unreachable code after unconditional jumps and returns
  static List<Instruction> _eliminateDeadCode(List<Instruction> instructions) {
    final result = <Instruction>[];
    var reachable = true;

    for (var i = 0; i < instructions.length; i++) {
      final instruction = instructions[i];

      // Reset reachability at labels
      if (_isLabel(instruction)) {
        reachable = true;
      }

      if (reachable) {
        result.add(instruction);

        // Code after these is unreachable until next label
        if (instruction.op == OpCode.RETURN || instruction.op == OpCode.JMP) {
          reachable = false;
        }
      }
    }

    return result;
  }

  /// Peephole optimizations - replace common instruction patterns
  static List<Instruction> _peepholeOptimize(List<Instruction> instructions) {
    final result = <Instruction>[];

    for (var i = 0; i < instructions.length; i++) {
      // Check for LOAD followed by immediate STORE to same register
      if (i < instructions.length - 1 &&
          instructions[i].op == OpCode.LOAD_LOCAL &&
          instructions[i + 1].op == OpCode.STORE_LOCAL &&
          instructions[i].operands[0] == instructions[i + 1].operands[0]) {
        // Skip the redundant load
        result.add(instructions[i + 1]);
        i++;
        continue;
      }

      // Check for conditional jumps with constant conditions
      if ((instructions[i].op == OpCode.JMPF ||
              instructions[i].op == OpCode.JMPT) &&
          i > 0 &&
          instructions[i - 1].op == OpCode.LOAD_CONST) {
        final condition = instructions[i - 1].operands[0];
        if (condition is bool) {
          if ((instructions[i].op == OpCode.JMPF && !condition) ||
              (instructions[i].op == OpCode.JMPT && condition)) {
            // Replace with unconditional jump
            result.removeLast(); // Remove the LOAD_CONST
            result.add(Instruction(OpCode.JMP, instructions[i].operands));
            continue;
          } else {
            // Remove dead branch
            result.removeLast(); // Remove the LOAD_CONST
            continue;
          }
        }
      }

      result.add(instructions[i]);
    }

    return result;
  }

  /// Fold constant expressions at compile time
  static List<Instruction> _foldConstants(
    List<Instruction> instructions,
    List<dynamic> constants,
  ) {
    final result = <Instruction>[];

    for (var i = 0; i < instructions.length; i++) {
      if (i < instructions.length - 2 &&
          instructions[i].op == OpCode.LOAD_CONST &&
          instructions[i + 1].op == OpCode.LOAD_CONST) {
        final a = constants[instructions[i].operands[0]];
        final b = constants[instructions[i + 1].operands[0]];

        // Try to fold arithmetic operations on constants
        if (instructions[i + 2].op == OpCode.ADD && a is num && b is num) {
          constants.add(a + b);
          result.add(Instruction(OpCode.LOAD_CONST, [constants.length - 1]));
          i += 2;
          continue;
        }
        if (instructions[i + 2].op == OpCode.MUL && a is num && b is num) {
          constants.add(a * b);
          result.add(Instruction(OpCode.LOAD_CONST, [constants.length - 1]));
          i += 2;
          continue;
        }
        // Add more constant folding cases here...
      }

      result.add(instructions[i]);
    }

    return result;
  }

  /// Eliminate no-op instructions
  static List<Instruction> _eliminateNoOps(List<Instruction> instructions) {
    return instructions.where((inst) {
      // Remove jumps of 0
      if (inst.op == OpCode.JMP && inst.operands[0] == 0) return false;

      // Remove moves to same register
      if (inst.op == OpCode.MOVE && inst.operands[0] == inst.operands[1]) {
        return false;
      }

      return true;
    }).toList();
  }

  static bool _isLabel(Instruction instruction) {
    // Add logic to identify label pseudo-instructions if needed
    return false;
  }
}
