import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/bytecode/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler tables', () {
    test('compiles table field access', () {
      final program = parse('return tbl.value');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final fieldIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'value',
      );
      expect(fieldIndex, isNonNegative);

      final getField = instructions[1] as ABCInstruction;
      expect(getField.opcode, BytecodeOpcode.getField);
      expect(getField.b, equals(0));
      expect(getField.c, equals(fieldIndex));
    });

    test('compiles table index access with integer literal', () {
      final program = parse('return arr[1]');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final getI = instructions[1] as ABCInstruction;
      expect(getI.opcode, BytecodeOpcode.getI);
      expect(getI.a, equals(0));
      expect(getI.b, equals(0));
      expect(getI.c, equals(1));
    });

    test('compiles table index access with dynamic key', () {
      final program = parse('return arr[idx]');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(4));

      final getTable = instructions[2] as ABCInstruction;
      expect(getTable.opcode, BytecodeOpcode.getTable);
      expect(getTable.a, equals(0));
      expect(getTable.b, equals(0));
      expect(getTable.c, equals(1));
    });

    test('compiles empty table constructor', () {
      final program = parse('return {}');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final newTable = instructions[0] as ABCInstruction;
      expect(newTable.opcode, BytecodeOpcode.newTable);
      expect(newTable.a, equals(0));

      final ret = instructions.last as ABCInstruction;
      expect(ret.opcode, BytecodeOpcode.return1);
      expect(ret.a, equals(0));
    });

    test('compiles mixed table constructor entries', () {
      final program = parse('return {1, foo = 2, [bar()] = 3, 4}');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.newTable,
        ),
        isTrue,
      );
      final setListInstructions = instructions
          .where((instruction) => instruction.opcode == BytecodeOpcode.setList)
          .cast<ABCInstruction>()
          .toList();
      expect(setListInstructions, hasLength(2));
      expect(setListInstructions[0].b, equals(1));
      expect(setListInstructions[0].c, equals(1));
      expect(setListInstructions[1].b, equals(1));
      expect(setListInstructions[1].c, equals(2));

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setField,
        ),
        isTrue,
      );
      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setTable,
        ),
        isTrue,
      );
    });

    test('compiles table constructor with vararg tail', () {
      final program = parse('local function build(...) return {1, 2, ...} end');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype.prototypes.first;
      final instructions = _stripVarArgPrep(proto);

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setList,
        ),
        isTrue,
      );
      final setListInstructions = instructions
          .where((instruction) => instruction.opcode == BytecodeOpcode.setList)
          .cast<ABCInstruction>()
          .toList();
      expect(setListInstructions.last.b, equals(0));
    });

    test('emits sizing hints for NEWTABLE', () {
      final program = parse('return {1, 2, foo = 3, [bar()] = 4}');
      final chunk = BytecodeCompiler().compile(program);
      final instructions = _stripVarArgPrep(chunk.mainPrototype);

      final newTable = instructions.first as ABCInstruction;
      expect(newTable.opcode, BytecodeOpcode.newTable);
      expect(newTable.b, equals(2));
      expect(newTable.c, equals(2));
    });

    test(
      'splits large sequential constructor into multiple SETLIST batches',
      () {
        final literals = List<String>.generate(
          60,
          (index) => '${index + 1}',
        ).join(', ');
        final program = parse('return {$literals}');
        final chunk = BytecodeCompiler().compile(program);
        final instructions = _stripVarArgPrep(chunk.mainPrototype);

        final setListInstructions = instructions
            .where(
              (instruction) => instruction.opcode == BytecodeOpcode.setList,
            )
            .cast<ABCInstruction>()
            .toList();

        expect(setListInstructions.length, equals(2));
        expect(setListInstructions[0].b, equals(50));
        expect(setListInstructions[0].c, equals(1));
        expect(setListInstructions[1].b, equals(10));
        expect(setListInstructions[1].c, equals(51));
      },
    );
  });
}

List<BytecodeInstruction> _stripVarArgPrep(BytecodePrototype proto) {
  final instructions = proto.instructions;
  if (instructions.isNotEmpty &&
      instructions.first.opcode == BytecodeOpcode.varArgPrep) {
    return instructions.sublist(1);
  }
  return instructions;
}
