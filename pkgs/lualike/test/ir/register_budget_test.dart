@TestOn('!browser')
@Tags(['ir'])
library;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/register_budget.dart';
import 'package:test/test.dart';

LualikeIrPrototype _proto({
  required int registerCount,
  List<LualikeIrInstruction> instructions = const [],
}) {
  return LualikeIrPrototype(
    registerCount: registerCount,
    paramCount: 0,
    isVararg: true,
    upvalueDescriptors: const [],
    instructions: instructions,
    constants: const [],
    prototypes: const [],
    lineDefined: 0,
    lastLineDefined: 0,
    registerConstFlags: List<bool>.filled(registerCount, false),
    constSealPoints: const {},
  );
}

void main() {
  group('IrBytecodeRegisterBudget', () {
    test('accepts a small valid prototype', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(
          registerCount: 4,
          instructions: [
            AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 0, sBx: 1),
            ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
          ],
        ),
      );

      expect(() => validateIrChunkRegisterBudget(chunk), returnsNormally);
    });

    test('rejects registerCount that cannot fit maxstack temps', () {
      final tooMany = IrBytecodeRegisterBudget.maxRegisterCount + 1;
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(registerCount: tooMany),
      );

      expect(
        () => validateIrChunkRegisterBudget(chunk),
        throwsA(isA<IrRegisterBudgetExceeded>()),
      );
    });

    test('rejects register operands beyond declared slots + temps', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(
          registerCount: 2,
          instructions: [
            AsBxInstruction(opcode: LualikeIrOpcode.loadI, a: 10, sBx: 1),
          ],
        ),
      );

      expect(
        () => validateIrChunkRegisterBudget(chunk),
        throwsA(isA<IrRegisterBudgetExceeded>()),
      );
    });

    test('does not treat CALL B count field as a register index', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(
          registerCount: 4,
          instructions: [
            ABCInstruction(opcode: LualikeIrOpcode.call, a: 0, b: 3, c: 1),
          ],
        ),
      );

      expect(() => validateIrChunkRegisterBudget(chunk), returnsNormally);
    });
  });
}
