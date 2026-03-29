import 'package:lualike/parsers.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrReader', () {
    test('parses prototypes, metadata, and nested functions', () {
      const source = '''
      // Structured textual IR fixture.
      chunk has_constant_hash=true {
        prototype main
          register_count=3
          param_count=1
          is_vararg=true
          named_vararg_register=2
          line_defined=10
          last_line_defined=12 {
          upvalue_descriptors {
            upvalue in_stack=0 index=0 kind=1;
          }
          constants {
            nil;
            bool true;
            int 7;
            number -1.5e2;
            short "hi";
            long 'hello\\nworld';
          }
          register_const_flags [true, false, true];
          const_seal_points {
            seal instruction_index=0 registers=[2];
          }
          instructions {
            abc VARARGPREP a=1 b=0 c=0;
            abx LOADK a=0 bx=2;
            abc RETURN1 a=0 b=0 c=0;
            ax EXTRAARG ax=99;
          }
          debug_info {
            line_info [10, 11, 12, 12];
            absolute_source_path "/tmp/main.lua";
            preferred_name "main";
            preferred_name_what "global";
            local_names {
              local name="value" start_pc=0 end_pc=2;
            }
            upvalue_names ["_ENV"];
          }
          prototype child register_count=1 param_count=0 is_vararg=false {
            instructions {
              abc RETURN0 a=0 b=0 c=0;
            }
          }
        }
      }
      ''';

      final chunk = LualikeIrReader.parse(source);
      final proto = chunk.mainPrototype;

      expect(chunk.flags.hasConstantHash, isTrue);
      expect(chunk.flags.hasDebugInfo, isTrue);
      expect(proto.registerCount, equals(3));
      expect(proto.paramCount, equals(1));
      expect(proto.isVararg, isTrue);
      expect(proto.namedVarargRegister, equals(2));
      expect(proto.lineDefined, equals(10));
      expect(proto.lastLineDefined, equals(12));

      expect(proto.upvalueDescriptors, hasLength(1));
      expect(proto.upvalueDescriptors.first.inStack, equals(0));
      expect(proto.upvalueDescriptors.first.index, equals(0));
      expect(proto.upvalueDescriptors.first.kind, equals(1));

      expect(proto.constants, hasLength(6));
      expect(proto.constants[0], isA<NilConstant>());
      expect(
        proto.constants[1],
        isA<BooleanConstant>().having((value) => value.value, 'value', isTrue),
      );
      expect(
        proto.constants[2],
        isA<IntegerConstant>().having((value) => value.value, 'value', 7),
      );
      expect(
        proto.constants[3],
        isA<NumberConstant>().having((value) => value.value, 'value', -150.0),
      );
      expect(
        proto.constants[4],
        isA<ShortStringConstant>().having(
          (value) => value.value,
          'value',
          'hi',
        ),
      );
      expect(
        proto.constants[5],
        isA<LongStringConstant>().having(
          (value) => value.value,
          'value',
          'hello\nworld',
        ),
      );

      expect(proto.registerConstFlags, equals(<bool>[true, false, true]));
      expect(
        proto.constSealPoints,
        equals(<int, List<int>>{
          0: <int>[2],
        }),
      );

      expect(proto.instructions, hasLength(4));
      expect(proto.instructions[0], isA<ABCInstruction>());
      expect(proto.instructions[1], isA<ABxInstruction>());
      expect(proto.instructions[2], isA<ABCInstruction>());
      expect(proto.instructions[3], isA<AxInstruction>());

      final debugInfo = proto.debugInfo;
      expect(debugInfo, isNotNull);
      expect(debugInfo!.lineInfo, equals(<int>[10, 11, 12, 12]));
      expect(debugInfo.absoluteSourcePath, equals('/tmp/main.lua'));
      expect(debugInfo.preferredName, equals('main'));
      expect(debugInfo.preferredNameWhat, equals('global'));
      expect(debugInfo.upvalueNames, equals(<String>['_ENV']));
      expect(debugInfo.localNames, hasLength(1));
      expect(debugInfo.localNames.first.name, equals('value'));
      expect(debugInfo.localNames.first.startPc, equals(0));
      expect(debugInfo.localNames.first.endPc, equals(2));

      expect(proto.prototypes, hasLength(1));
      expect(proto.prototypes.single.registerCount, equals(1));
      expect(proto.prototypes.single.paramCount, equals(0));
      expect(proto.prototypes.single.isVararg, isFalse);
      expect(
        proto.prototypes.single.instructions.single,
        isA<ABCInstruction>(),
      );
    });

    test('executes a parsed chunk through the IR VM', () async {
      const source = '''
      chunk {
        prototype main register_count=1 param_count=0 is_vararg=true {
          constants {
            int 42;
          }
          instructions {
            abc VARARGPREP a=0 b=0 c=0;
            abx LOADK a=0 bx=0;
            abc RETURN1 a=0 b=0 c=0;
          }
        }
      }
      ''';

      final chunk = LualikeIrReader.parse(source);
      final result = await LualikeIrVm().execute(chunk);

      expect(chunk.flags.hasDebugInfo, isFalse);
      expect(result, equals(42));
    });

    test('rejects duplicate prototype properties', () {
      const source = '''
      chunk {
        prototype main register_count=1 register_count=2 {
          instructions {
            abc RETURN0 a=0 b=0 c=0;
          }
        }
      }
      ''';

      expect(
        () => LualikeIrReader.parse(source),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
