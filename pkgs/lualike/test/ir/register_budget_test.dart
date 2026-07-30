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

    test('does not treat upvalue indices as register operands', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(
          registerCount: 3,
          instructions: [
            ABCInstruction(opcode: LualikeIrOpcode.getUpval, a: 2, b: 5, c: 0),
            ABCInstruction(opcode: LualikeIrOpcode.setUpval, a: 0, b: 5, c: 2),
            ABCInstruction(opcode: LualikeIrOpcode.setTabUp, a: 0, b: 5, c: 2),
          ],
        ),
      );

      expect(() => validateIrChunkRegisterBudget(chunk), returnsNormally);
    });

    test('does not treat SETFIELD/SETI k=true C as a register (Kst value)', () {
      // Table-literal fields compile as SETFIELD with k=true and C=Kst index.
      // High constant pools put C well above registerCount; that must not fail
      // budget validation (relic_breach / example browser regressions).
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(
          registerCount: 4,
          instructions: [
            ABCInstruction(
              opcode: LualikeIrOpcode.setField,
              a: 0,
              b: 10,
              c: 130,
              k: true,
            ),
            ABCInstruction(
              opcode: LualikeIrOpcode.setI,
              a: 1,
              b: 1,
              c: 99,
              k: true,
            ),
            ABCInstruction(
              opcode: LualikeIrOpcode.setTabUp,
              a: 0,
              b: 5,
              c: 80,
              k: true,
            ),
          ],
        ),
      );

      expect(() => validateIrChunkRegisterBudget(chunk), returnsNormally);
    });

    test('still treats SETFIELD k=false C as a register', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: _proto(
          registerCount: 2,
          instructions: [
            ABCInstruction(
              opcode: LualikeIrOpcode.setField,
              a: 0,
              b: 1,
              c: 10,
              k: false,
            ),
          ],
        ),
      );

      expect(
        () => validateIrChunkRegisterBudget(chunk),
        throwsA(isA<IrRegisterBudgetExceeded>()),
      );
    });
  });
}
