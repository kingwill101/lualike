@Tags(['bytecode'])
import 'package:test/test.dart';
import 'package:lualike/bytecode.dart';

void main() {
  group('BytecodeOptimizer', () {
    test('eliminates dead code', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]),
          Instruction(OpCode.RETURN),
          Instruction(OpCode.LOAD_CONST, [1]), // Dead code
        ],
        constants: [1, 2],
        numRegisters: 1,
      );

      final optimized = BytecodeOptimizer.optimize(chunk);
      expect(optimized.instructions.length, equals(2));
      expect(optimized.instructions.last.op, equals(OpCode.RETURN));
    });

    test('performs constant folding', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]), // Load 10
          Instruction(OpCode.LOAD_CONST, [1]), // Load 20
          Instruction(OpCode.ADD), // Should be folded to 30
        ],
        constants: [10, 20],
        numRegisters: 1,
      );

      final optimized = BytecodeOptimizer.optimize(chunk);
      expect(optimized.instructions.length, equals(1));
      expect(optimized.instructions[0].op, equals(OpCode.LOAD_CONST));
      expect(optimized.constants.last, equals(30));
    });

    test('eliminates redundant loads/stores', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_LOCAL, [0]),
          Instruction(OpCode.STORE_LOCAL, [0]), // Redundant store
          Instruction(OpCode.LOAD_LOCAL, [0]), // Redundant load
        ],
        constants: [],
        numRegisters: 1,
      );

      final optimized = BytecodeOptimizer.optimize(chunk);
      expect(optimized.instructions.length, equals(1));
      expect(optimized.instructions[0].op, equals(OpCode.LOAD_LOCAL));
    });

    test('optimizes conditional jumps with constant conditions', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]), // Load true
          Instruction(OpCode.JMPF, [1]), // Should be eliminated
          Instruction(OpCode.LOAD_CONST, [1]),
        ],
        constants: [true, 42],
        numRegisters: 1,
      );

      final optimized = BytecodeOptimizer.optimize(chunk);
      expect(optimized.instructions.length, equals(1));
      expect(optimized.instructions[0].op, equals(OpCode.LOAD_CONST));
      expect(optimized.instructions[0].operands[0], equals(1));
    });
  });
}
