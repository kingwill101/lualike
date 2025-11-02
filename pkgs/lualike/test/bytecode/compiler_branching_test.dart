import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler branching', () {
    test('if statement with elseif emits multiple tests and jumps', () {
      final program = parse(
        'if cond == 1 then tbl.value = 1 elseif cond == 2 then tbl.value = 2 else tbl.value = 3 end',
      );
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final tests = instructions.where((i) => i.opcode == BytecodeOpcode.test);
      expect(tests.length, greaterThanOrEqualTo(2));

      final jumps = instructions
          .whereType<AsJInstruction>()
          .map((instr) => instr.sJ)
          .toList();
      expect(jumps, isNotEmpty);
      expect(jumps.where((offset) => offset != 0), isNotEmpty);
    });

    test('while loop emits backward jump', () {
      final program = parse('while state.i < 3 do state.i = state.i + 1 end');
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasBackJump = instructions.whereType<AsJInstruction>().any(
        (instr) => instr.sJ < 0,
      );
      expect(hasBackJump, isTrue);
    });
  });
}
