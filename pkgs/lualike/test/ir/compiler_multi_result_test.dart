@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler multi-result support', () {
    test('returning multiple values encodes result count', () {
      final program = parse('local a, b = 1, 2; return a, b');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;
      final retInstruction = instructions.last as ABCInstruction;

      expect(retInstruction.opcode, LualikeIrOpcode.ret);
      expect(retInstruction.b, equals(3)); // 2 results => B = count + 1
      expect(retInstruction.c, equals(0));
    });

    test('returning trailing call forwards dynamic results', () {
      final program = parse('''
local function helper() return 1, 2, 3 end
local a = 10
return a, helper()
''');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;
      final retInstruction = instructions.last as ABCInstruction;

      expect(retInstruction.opcode, LualikeIrOpcode.ret);
      expect(retInstruction.b, equals(0));
      expect(retInstruction.c, equals(1)); // one fixed value before the call
    });

    test('multi-target assignment requests sufficient call results', () {
      final program = parse('''
local function pair() return 4, 5 end
local a, b
a, b = pair()
''');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;
      final callInstruction =
          instructions.firstWhere(
                (instruction) => instruction.opcode == LualikeIrOpcode.call,
              )
              as ABCInstruction;

      expect(callInstruction.c, equals(3)); // expects two results => C = 3
    });

    test('local declaration propagates vararg results across names', () {
      final program = parse('''
local function f(...) return ... end
local x, y, z = f(1, 2, 3)
''');
      final chunk = LualikeIrCompiler().compile(program);
      final callInstruction =
          chunk.mainPrototype.instructions.firstWhere(
                (instruction) => instruction.opcode == LualikeIrOpcode.call,
              )
              as ABCInstruction;

      expect(callInstruction.c, equals(4)); // expect three results => C = 4
    });
  });
}
