import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler closures and varargs', () {
    test(
      'emits child prototypes and upvalue descriptors for nested closure',
      () {
        final program = parse(
          'local function outer(x) return function() return x end end',
        );
        final chunk = BytecodeCompiler().compile(program);
        final mainPrototype = chunk.mainPrototype;

        expect(mainPrototype.prototypes, hasLength(1));
        final outerPrototype = mainPrototype.prototypes.first;
        expect(outerPrototype.paramCount, equals(1));

        expect(outerPrototype.prototypes, hasLength(1));
        final innerPrototype = outerPrototype.prototypes.first;
        expect(innerPrototype.upvalueDescriptors, hasLength(1));

        final descriptor = innerPrototype.upvalueDescriptors.first;
        expect(descriptor.inStack, equals(1));
        expect(descriptor.index, equals(0));

        expect(
          mainPrototype.instructions.any(
            (instruction) => instruction.opcode == BytecodeOpcode.closure,
          ),
          isTrue,
        );
      },
    );

    test(
      'marks function body as vararg and lowers return ... to VARARG/RET',
      () {
        final program = parse('local function collect(...) return ... end');
        final chunk = BytecodeCompiler().compile(program);
        final collectPrototype = chunk.mainPrototype.prototypes.first;

        expect(collectPrototype.isVararg, isTrue);
        expect(
          collectPrototype.instructions.first.opcode,
          equals(BytecodeOpcode.varArgPrep),
        );
        expect(
          collectPrototype.instructions.any(
            (instruction) => instruction.opcode == BytecodeOpcode.varArg,
          ),
          isTrue,
        );
        expect(
          collectPrototype.instructions.any(
            (instruction) => instruction.opcode == BytecodeOpcode.ret,
          ),
          isTrue,
        );
      },
    );

    test('emits SETUPVAL when closure mutates captured local', () {
      final program = parse(
        'local count = 0;\nlocal function bump() count = count + 1 return count end',
      );
      final chunk = BytecodeCompiler().compile(program);
      final bumpPrototype = chunk.mainPrototype.prototypes.single;

      expect(
        bumpPrototype.instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setUpval,
        ),
        isTrue,
      );
    });

    test('emits table store for method definition', () {
      final program = parse('function t:foo(v) self.value = v end');
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setField,
        ),
        isTrue,
      );
    });

    test('uses SETTABUP for _ENV assignments', () {
      final program = parse('_ENV.result = 11');
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setTabUp,
        ),
        isTrue,
      );
    });
  });
}
