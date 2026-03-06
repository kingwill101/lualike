@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler calls', () {
    test('function call emits CALL opcode', () {
      final program = parse('fn(1)');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasCall = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.call,
      );

      expect(hasCall, isTrue);
    });

    test('returning function call emits TAILCALL', () {
      final program = parse('return fn(1)');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasTailCall = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.tailCall,
      );

      expect(hasTailCall, isTrue);
    });
  });
}
