@Tags(['bytecode'])
import 'package:test/test.dart';
import 'package:lualike/bytecode.dart';

void main() {
  group('BytecodeSerializer', () {
    test('serializes and deserializes simple chunk', () {
      final original = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_CONST, [0]),
          Instruction(OpCode.RETURN),
        ],
        constants: [42],
        numRegisters: 1,
        name: 'test',
      );

      final bytes = BytecodeSerializer.serialize(original);
      final deserialized = BytecodeSerializer.deserialize(bytes);

      expect(deserialized.name, equals(original.name));
      expect(deserialized.numRegisters, equals(original.numRegisters));
      expect(deserialized.constants.length, equals(original.constants.length));
      expect(deserialized.constants[0], equals(original.constants[0]));
      expect(
        deserialized.instructions.length,
        equals(original.instructions.length),
      );
      expect(
        deserialized.instructions[0].op,
        equals(original.instructions[0].op),
      );
      expect(
        deserialized.instructions[0].operands,
        equals(original.instructions[0].operands),
      );
    });

    test('handles nested chunks (for closures)', () {
      final innerChunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.LOAD_LOCAL, [0]),
          Instruction(OpCode.RETURN),
        ],
        constants: [],
        numRegisters: 1,
        name: 'inner',
      );

      final outerChunk = BytecodeChunk(
        instructions: [
          Instruction(OpCode.CLOSURE, [0]),
          Instruction(OpCode.RETURN),
        ],
        constants: [innerChunk],
        numRegisters: 1,
        name: 'outer',
      );

      final bytes = BytecodeSerializer.serialize(outerChunk);
      final deserialized = BytecodeSerializer.deserialize(bytes);

      // Verify outer chunk
      expect(deserialized.name, equals(outerChunk.name));
      expect(deserialized.constants.length, equals(1));

      // Verify inner chunk was properly serialized
      final deserializedInner = deserialized.constants[0] as BytecodeChunk;
      expect(deserializedInner.name, equals(innerChunk.name));
      expect(
        deserializedInner.instructions.length,
        equals(innerChunk.instructions.length),
      );
    });

    test('handles all constant types', () {
      final chunk = BytecodeChunk(
        instructions: [Instruction(OpCode.RETURN)],
        constants: [
          null, // nil
          true, // boolean
          42, // number
          "hello", // string
          BytecodeChunk(
            // nested chunk
            instructions: [Instruction(OpCode.RETURN)],
            constants: [],
            numRegisters: 1,
            name: 'nested',
          ),
        ],
        numRegisters: 1,
        name: 'constants_test',
      );

      final bytes = BytecodeSerializer.serialize(chunk);
      final deserialized = BytecodeSerializer.deserialize(bytes);

      expect(deserialized.constants[0], isNull);
      expect(deserialized.constants[1], isTrue);
      expect(deserialized.constants[2], equals(42));
      expect(deserialized.constants[3], equals("hello"));
      expect(deserialized.constants[4], isA<BytecodeChunk>());
    });
  });
}
