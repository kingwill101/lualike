@TestOn('!browser')
@Tags(['ir'])
library;

import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/ssa_escape_pass.dart';
import 'package:test/test.dart';

LualikeIrPrototype _prototype({
  required int registerCount,
  required List<LualikeIrInstruction> instructions,
  List<LualikeIrUpvalueDescriptor> upvalues = const [],
  List<LualikeIrPrototype> children = const [],
}) {
  return LualikeIrPrototype(
    registerCount: registerCount,
    paramCount: 0,
    isVararg: false,
    upvalueDescriptors: upvalues,
    instructions: instructions,
    constants: const [ShortStringConstant('field')],
    prototypes: children,
    lineDefined: 0,
    lastLineDefined: 0,
    registerConstFlags: List<bool>.filled(registerCount, false),
    constSealPoints: const {},
  );
}

void main() {
  group('SSA escape analysis', () {
    test('keeps a table copied through MOVE', () {
      final prototype = _prototype(
        registerCount: 3,
        instructions: const [
          ABCInstruction(opcode: LualikeIrOpcode.newTable, a: 0, b: 0, c: 0),
          ABCInstruction(opcode: LualikeIrOpcode.setField, a: 0, b: 0, c: 1),
          ABCInstruction(opcode: LualikeIrOpcode.move, a: 2, b: 0, c: 0),
          ABCInstruction(opcode: LualikeIrOpcode.return1, a: 2, b: 0, c: 0),
        ],
      );

      final optimized = replaceScalars(prototype);

      expect(optimized.instructions.first.opcode, LualikeIrOpcode.newTable);
      expect(optimized.instructions[1].opcode, LualikeIrOpcode.setField);
    });

    test('keeps a table captured by a child prototype', () {
      final child = _prototype(
        registerCount: 1,
        instructions: const [
          ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
        ],
        upvalues: const [LualikeIrUpvalueDescriptor(inStack: 1, index: 0)],
      );
      final prototype = _prototype(
        registerCount: 3,
        children: [child],
        instructions: const [
          ABCInstruction(opcode: LualikeIrOpcode.newTable, a: 0, b: 0, c: 0),
          ABCInstruction(opcode: LualikeIrOpcode.setField, a: 0, b: 0, c: 1),
          ABxInstruction(opcode: LualikeIrOpcode.closure, a: 2, bx: 0),
          ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
        ],
      );

      final optimized = replaceScalars(prototype);

      expect(optimized.instructions.first.opcode, LualikeIrOpcode.newTable);
      expect(optimized.instructions[1].opcode, LualikeIrOpcode.setField);
    });

    test('keeps an environment table read by CHECKGLOBAL', () {
      final prototype = _prototype(
        registerCount: 2,
        instructions: const [
          ABCInstruction(opcode: LualikeIrOpcode.newTable, a: 0, b: 0, c: 0),
          ABCInstruction(opcode: LualikeIrOpcode.setField, a: 0, b: 0, c: 1),
          ABxInstruction(opcode: LualikeIrOpcode.checkGlobal, a: 0, bx: 0),
          ABCInstruction(opcode: LualikeIrOpcode.return0, a: 0, b: 0, c: 0),
        ],
      );

      final optimized = replaceScalars(prototype);

      expect(optimized.instructions.first.opcode, LualikeIrOpcode.newTable);
      expect(optimized.instructions[1].opcode, LualikeIrOpcode.setField);
    });
  });
}
