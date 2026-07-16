import 'package:lualike/src/ast.dart';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/llvm_lowering.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:lualike/src/ir/ssa_type_analysis.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

/// Tests for LLVM IR emission from lualike IR prototypes.
void main() {
  group('LLVM lowering — basic arithmetic', () {
    test('emits fadd for numeric addition', () {
      final llvm = _compileToLlvm('1 + 2');
      expect(llvm, contains('fadd double'));
      expect(llvm, contains('ret double'));
    });

    test('emits fsub for subtraction', () {
      final llvm = _compileToLlvm('5 - 3');
      expect(llvm, contains('fsub double'));
    });

    test('emits fmul for multiplication', () {
      final llvm = _compileToLlvm('2 * 3');
      expect(llvm, contains('fmul double'));
    });

    test('emits fdiv for division', () {
      final llvm = _compileToLlvm('10 / 2');
      expect(llvm, contains('fdiv double'));
    });

    test('emits fneg for unary minus', () {
      final llvm = _compileToLlvm('-5');
      expect(llvm, contains('fneg double'));
    });
  });

  group('LLVM lowering — comparison', () {
    test('emits fcmp for equality', () {
      final llvm = _compileToLlvm('1 == 1');
      expect(llvm, contains('fcmp oeq double'));
    });

    test('emits fcmp for less than', () {
      final llvm = _compileToLlvm('1 < 2');
      expect(llvm, contains('fcmp olt double'));
    });

    test('emits fcmp for less or equal', () {
      final llvm = _compileToLlvm('1 <= 2');
      expect(llvm, contains('fcmp ole double'));
    });
  });

  group('LLVM lowering — booleans', () {
    test('emits not on false', () {
      final llvm = _compileToLlvm('not false');
      // `not false` → true.  The compiler may fold it or emit a NOT.
      expect(llvm, anyOf(contains('xor i8'), contains('i8 1')));
    });

    test('emits i8 0 for not on number', () {
      final llvm = _compileToLlvm('not 42');
      expect(llvm, contains('i8 0'));
    });
  });

  group('LLVM lowering — module structure', () {
    test('emits module header with declarations', () {
      final llvm = _compileToLlvm('1');
      expect(llvm, contains('target datalayout'));
      expect(llvm, contains('declare double @pow'));
      expect(llvm, contains('declare void @lualike_abort'));
    });

    test('emits function definition', () {
      final llvm = _compileToLlvm('1');
      expect(llvm, contains('define double @_lua_fn_0'));
      expect(llvm, contains('ret double'));
    });

    test('uses SSA register names', () {
      final llvm = _compileToLlvm('1');
      expect(llvm, contains(RegExp(r'%r\d+_v\d+')));
    });
  });

  group('LLVM lowering — abort on unsupported', () {
    test('emits abort for function call', () {
      final llvm = _compileToLlvm('math.sin(1)');
      expect(llvm, contains('lualike_abort'));
    });

    test('emits abort for string literal', () {
      final llvm = _compileToLlvm('"hello"');
      expect(llvm, contains('lualike_abort'));
    });
  });

  group('LLVM lowering — type analysis integration', () {
    test('classifies arithmetic and move as number', () {
      final chunk = _compileToIr('1 + 2');
      final ssa = LualikeIrSsaFunction.fromPrototype(
        chunk.mainPrototype,
      ).simplifyTrivialPhis();
      final analysis = analyzeLualikeIrSsaTypes(chunk.mainPrototype, ssa);
      // All instruction-defined values should be number.
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
