/// Fuzz tests for the IR/SSA/bytecode compiler pipeline.
///
/// Generates random Lua programs using `property_testing` generators and
/// verifies the compiler handles them without crashing or exceeding the
/// register budget.
library;

import 'dart:math';

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/ir/register_budget.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/parse.dart';
import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

/// Compile [source] through the full pipeline, returning null on success
/// or an error message on failure.
String? _compile(String label, String source) {
  try {
    final program = parse(source, url: 'fuzz_$label.lua');
    final pipeline = CompilePipeline(
      config: CompilePipelineConfig.luaBytecodeOptimized(),
    );
    final artifact = pipeline.compile(program) as LuaBytecodeArtifact;
    final proto = artifact.chunk.mainPrototype;

    if (proto.maxStackSize > IrBytecodeRegisterBudget.maxRegisterIndex + 1) {
      return 'maxStackSize ${proto.maxStackSize} exceeds bytecode limit';
    }
    // Sanity-check that disassembly works.
    const LuaBytecodeDisassembler().render(artifact.chunk);
    return null;
  } on IrRegisterBudgetExceeded {
    return null; // Expected for extreme register pressure.
  } catch (e) {
    return e.toString();
  }
}

void main() {
  group('fuzz', () {
    test('many local variables', () {
      // Generate a range of local variable counts via property_testing.
      final gen = Gen.integer(min: 10, max: 250);
      final rng = Random(42);

      for (var i = 0; i < 30; i++) {
        final n = gen.generate(rng).value;
        final decls = List.generate(
          n,
          (j) => 'local v${j}_$i = ${j % 100};',
        ).join('\n');
        final sum = List.generate(n, (j) => 'v${j}_$i').join(' + ');
        final source = '$decls\nreturn $sum';
        final err = _compile('locals_${n}_$i', source);
        expect(err, isNull, reason: 'locals_${n}_$i: $err');
      }
    });

    test('deeply nested expressions', () {
      final gen = Gen.integer(min: 1, max: 200);
      final rng = Random(99);

      // Linear nesting (not exponential): depth 200 = 200 ADD nodes.
      String nest(int d) =>
          d <= 0 ? '1' : '(${nest(d - 1)} + 1)';

      for (var i = 0; i < 20; i++) {
        final depth = gen.generate(rng).value;
        final source = 'return ${nest(depth)}';
        final err = _compile('nest_${depth}_$i', source);
        expect(err, isNull, reason: 'nest_${depth}_$i: $err');
      }
    });

    test('large function parameters', () {
      final gen = Gen.integer(min: 1, max: 250);
      final rng = Random(77);

      for (var i = 0; i < 20; i++) {
        final n = gen.generate(rng).value;
        final params = List.generate(n, (j) => 'p${j}_$i').join(', ');
        final body =
            List.generate(n, (j) => 'local x${j}_$i = p${j}_$i + 1;').join('\n');
        final sum = List.generate(n, (j) => 'x${j}_$i').join(' + ');
        final args = List.generate(n, (j) => '$j').join(', ');
        final source = '''
          local function f($params)
            $body
            return $sum
          end
          return f($args)
        ''';
        final err = _compile('params_${n}_$i', source);
        expect(err, isNull, reason: 'params_${n}_$i: $err');
      }
    });

    test('random expression trees', () {
      final depthGen = Gen.integer(min: 1, max: 8);
      final varCountGen = Gen.integer(min: 2, max: 10);
      final rng = Random(2026);

      String randExpr(int depth, List<String> vars, Random r) {
        if (depth > 6 || r.nextDouble() < 0.3) {
          return vars[r.nextInt(vars.length)];
        }
        return switch (r.nextInt(4)) {
          0 => '(${randExpr(depth + 1, vars, r)} + ${randExpr(depth + 1, vars, r)})',
          1 => '(${randExpr(depth + 1, vars, r)} * ${randExpr(depth + 1, vars, r)})',
          2 => '(${randExpr(depth + 1, vars, r)} - ${randExpr(depth + 1, vars, r)})',
          _ => '(${randExpr(depth + 1, vars, r)} / ${randExpr(depth + 1, vars, r)})',
        };
      }

      for (var i = 0; i < 50; i++) {
        final depth = depthGen.generate(rng).value;
        final nVars = varCountGen.generate(rng).value;
        final vars = List.generate(nVars, (j) => 'v${j}_$i');
        final decls =
            vars.map((v) => 'local $v = ${rng.nextInt(100)};').join('\n');
        final expr = randExpr(depth, vars, rng);
        final source = '$decls\nreturn $expr';
        final err = _compile('rand_${i}_${depth}_${nVars}', source);
        expect(err, isNull, reason: 'rand_${i}_${depth}_${nVars}: $err');
      }
    });
  });
}
