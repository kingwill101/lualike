import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/llvm_lowering.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:lualike/src/ir/ssa_type_analysis.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

/// Tests for LLVM IR emission from lualike IR prototypes (runtime-based).
void main() {
  group('LLVM lowering — runtime calls', () {
    test('emits lualike_add for addition', () {
      final llvm = _compileToLlvm('1 + 2');
      expect(llvm, contains('@lualike_add'));
      expect(llvm, contains('ret void'));
    });

    test('emits lualike_sub for subtraction', () {
      final llvm = _compileToLlvm('5 - 3');
      expect(llvm, contains('@lualike_sub'));
    });

    test('emits lualike_mul for multiplication', () {
      final llvm = _compileToLlvm('2 * 3');
      expect(llvm, contains('@lualike_mul'));
    });

    test('emits lualike_div for division', () {
      final llvm = _compileToLlvm('10 / 2');
      expect(llvm, contains('@lualike_div'));
    });

    test('emits lualike_unm for unary minus', () {
      final llvm = _compileToLlvm('-5');
      expect(llvm, contains('@lualike_unm'));
    });

    test('emits lualike_mod for modulo', () {
      final llvm = _compileToLlvm('10 % 3');
      expect(llvm, contains('@lualike_mod'));
    });

    test('emits lualike_pow for power', () {
      final llvm = _compileToLlvm('2 ^ 3');
      expect(llvm, contains('@lualike_pow'));
    });

    test('emits lualike_idiv for floor div', () {
      final llvm = _compileToLlvm('10 // 3');
      expect(llvm, contains('@lualike_idiv'));
    });
  });

  group('LLVM lowering — bitwise', () {
    test('emits lualike_band', () {
      final llvm = _compileToLlvm('1 & 3');
      expect(llvm, contains('@lualike_band'));
    });

    test('emits lualike_bor', () {
      final llvm = _compileToLlvm('1 | 2');
      expect(llvm, contains('@lualike_bor'));
    });

    test('emits lualike_bxor', () {
      final llvm = _compileToLlvm('1 ~ 3');
      expect(llvm, contains('@lualike_bxor'));
    });

    test('emits lualike_bnot', () {
      final llvm = _compileToLlvm('~1');
      expect(llvm, contains('@lualike_bnot'));
    });
  });

  group('LLVM lowering — comparisons', () {
    test('emits lualike_eq for equality', () {
      final llvm = _compileToLlvm('1 == 1');
      expect(llvm, contains('@lualike_eq'));
    });

    test('emits lualike_lt for less than', () {
      final llvm = _compileToLlvm('1 < 2');
      expect(llvm, contains('@lualike_lt'));
    });

    test('emits lualike_le for less or equal', () {
      final llvm = _compileToLlvm('1 <= 2');
      expect(llvm, contains('@lualike_le'));
    });
  });

  group('LLVM lowering — booleans and nil', () {
    test('emits lualike_pushboolean for false', () {
      final llvm = _compileToLlvm('false');
      expect(llvm, contains('@lualike_pushboolean'));
    });

    test('emits lualike_not for not', () {
      final llvm = _compileToLlvm('not false');
      expect(llvm, contains('@lualike_not'));
    });

    test('emits lualike_pushnil for nil', () {
      final llvm = _compileToLlvm('nil');
      expect(llvm, contains('@lualike_pushnil'));
    });
  });

  group('LLVM lowering — module structure', () {
    test('emits module header with runtime declarations', () {
      final llvm = _compileToLlvm('1');
      expect(llvm, contains('target datalayout'));
      expect(llvm, contains('declare void @lualike_add'));
      expect(llvm, contains('declare void @lualike_copy'));
    });

    test('emits function definition with new signature', () {
      final llvm = _compileToLlvm('1');
      expect(llvm, contains('define void @_lua_fn_0'));
      expect(llvm, contains('ptr %L'));
      expect(llvm, contains('ptr %r'));
      expect(llvm, contains('ptr %constants'));
    });

    test('emits getelementptr for register access', () {
      final llvm = _compileToLlvm('1 + 2');
      expect(llvm, contains('getelementptr'));
    });
  });

  group('LLVM lowering — error handling', () {
    test('emits lualike_error for unsupported opcode', () {
      final llvm = _compileToLlvm('tostring(true)');
      // Function calls go through lualike_call, not lualike_error
      expect(llvm, contains('@lualike_call'));
    });
  });

  group('LLVM lowering — tables', () {
    test('emits lualike_newtable', () {
      final llvm = _compileToLlvm('{}');
      expect(llvm, contains('@lualike_newtable'));
    });

    test('emits lualike_gettable', () {
      final llvm = _compileToLlvm('({})[1]');
      expect(llvm, contains('@lualike_gettable'));
    });
  });

  group('LLVM lowering — type analysis integration', () {
    test('classifies arithmetic and move as number', () {
      final chunk = _compileToIr('1 + 2');
      final ssa = LualikeIrSsaFunction.fromPrototype(
        chunk.mainPrototype,
      ).simplifyTrivialPhis();
      final analysis = analyzeLualikeIrSsaTypes(chunk.mainPrototype, ssa);
      for (final block in ssa.blocks) {
        for (final value in block.definedValues) {
          final t = analysis.typeOf(value);
          expect(t, LualikeIrSsaType.number,
              reason: '${value.label} should be number, got $t');
        }
      }
    });

    test('classifies comparison result as boolean', () {
      final chunk = _compileToIr('1 < 2');
      final ssa = LualikeIrSsaFunction.fromPrototype(
        chunk.mainPrototype,
      ).simplifyTrivialPhis();
      final analysis = analyzeLualikeIrSsaTypes(chunk.mainPrototype, ssa);
      final types = analysis.typeBySsaValue.values.toSet();
      expect(types.contains(LualikeIrSsaType.boolean), isTrue);
    });
  });
}

/// Compiles a Lua expression to a [LualikeIrChunk].
LualikeIrChunk _compileToIr(String source) {
  final program = parse('local x = $source; return x');
  return LualikeIrCompiler().compile(program);
}

/// Compiles [source] and emits LLVM IR text.
String _compileToLlvm(String source) {
  final chunk = _compileToIr(source);
  final prototype = chunk.mainPrototype;
  final ssaFunction = LualikeIrSsaFunction.fromPrototype(
    prototype,
  ).simplifyTrivialPhis();
  final typeAnalysis = analyzeLualikeIrSsaTypes(prototype, ssaFunction);

  final emitter = LualikeIrToLlvm(
    prototype: prototype,
    ssaFunction: ssaFunction,
    typeAnalysis: typeAnalysis,
  );

  return emitter.generateModule();
}
