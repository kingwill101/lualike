import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler calls', () {
    test('function call emits CALL opcode', () {
      final program = parse('fn(1)');
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasCall = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.call,
      );

      expect(hasCall, isTrue);
    });

    test('returning function call emits TAILCALL', () {
      final program = parse('return fn(1)');
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasTailCall = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.tailCall,
      );

      expect(hasTailCall, isTrue);
    });
  });
}
