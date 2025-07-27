@Tags(['bytecode'])
library;

import 'package:lualike/bytecode.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeVM', () {
    late BytecodeVM vm;

    setUp(() {
      vm = BytecodeVM();
    });

    test('executes basic arithmetic', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]), // Push 10
          Instruction(OpCode.LOAD_CONST, [1]), // Push 20
          Instruction(OpCode.ADD), // Add them
          Instruction(OpCode.RETURN), // Return result
        ],
        constants: [10, 20],
        numRegisters: 1,
        name: 'arithmetic_test',
      );

      final result = vm.execute(chunk);
      expect(result, equals(Value.number(30)));
    });

    test('handles local variables', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]), // Push 42
          Instruction(OpCode.STORE_LOCAL, [0]), // Store in R0
          Instruction(OpCode.LOAD_LOCAL, [0]), // Load from R0
          Instruction(OpCode.RETURN), // Return it
        ],
        constants: [42],
        numRegisters: 1,
        name: 'locals_test',
      );

      final result = vm.execute(chunk);
      expect(result, equals(Value.number(42)));
    });

    test('executes conditional jumps', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]), // Push true
          Instruction(OpCode.JMPF, [2]), // Jump if false (shouldn't jump)
          Instruction(OpCode.LOAD_CONST, [1]), // Push 1 (should execute)
          Instruction(OpCode.RETURN), // Return
          Instruction(OpCode.LOAD_CONST, [2]), // Push 2 (shouldn't execute)
          Instruction(OpCode.RETURN), // Return
        ],
        constants: [true, 1, 2],
        numRegisters: 1,
        name: 'conditional_test',
      );

      final result = vm.execute(chunk);
      expect(result, equals(Value.number(1)));
    });

    test('creates and manipulates tables', () {
      final chunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.NEWTABLE), // Create empty table
          Instruction(OpCode.LOAD_CONST, [0]), // Push key "x"
          Instruction(OpCode.LOAD_CONST, [1]), // Push value 42
          Instruction(OpCode.SETTABLE), // Set table["x"] = 42
          Instruction(OpCode.LOAD_CONST, [0]), // Push key "x" again
          Instruction(OpCode.GETTABLE), // Get table["x"]
          Instruction(OpCode.RETURN), // Return result
        ],
        constants: ["x", 42],
        numRegisters: 1,
        name: 'table_test',
      );

      final result = vm.execute(chunk);
      expect(result, equals(Value.number(42)));
    });

    test('handles function calls and returns', () {
      // Create a function that adds its two arguments
      final functionChunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_LOCAL, [0]), // Load first arg
          Instruction(OpCode.LOAD_LOCAL, [1]), // Load second arg
          Instruction(OpCode.ADD), // Add them
          Instruction(OpCode.RETURN), // Return result
        ],
        constants: [],
        numRegisters: 2,
        name: 'add_function',
      );

      // Main chunk that creates closure and calls it
      final mainChunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.CLOSURE, [0]), // Create closure from prototype
          Instruction(OpCode.LOAD_CONST, [1]), // Push 10
          Instruction(OpCode.LOAD_CONST, [2]), // Push 20
          Instruction(OpCode.CALL, [2]), // Call with 2 args
          Instruction(OpCode.RETURN), // Return result
        ],
        constants: [functionChunk, 10, 20],
        numRegisters: 1,
        name: 'main',
      );

      final result = vm.execute(mainChunk);
      expect(result, equals(Value.number(30)));
    });
  });
}
