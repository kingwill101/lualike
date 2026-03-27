import 'package:lualike_test/test.dart';
import 'package:lualike/src/ir/loop_compiler.dart';

void main() {
  group('Loop lualike IR compiler', () {
    test('compiles simple numeric for loop assignments', () {
      final compiler = LoopIrCompiler(
        loopVarName: 'i',
        startValue: 1,
        endValue: 3,
        stepValue: 1,
      );
      final chunk = compiler.compile([
        Assignment(
          [Identifier('sum')],
          [BinaryExpression(Identifier('sum'), '+', Identifier('i'))],
        ),
      ]);

      expect(chunk, isNotNull);
      expect(chunk!.mainPrototype.instructions, isNotEmpty);
    });

    test('returns null for unsupported statements', () {
      final compiler = LoopIrCompiler(
        loopVarName: 'i',
        startValue: 1,
        endValue: 3,
        stepValue: 1,
      );
      final chunk = compiler.compile([
        LocalDeclaration([Identifier('tmp')], [''], [Identifier('i')]),
      ]);

      expect(chunk, isNull);
    });

    test('compiles table index assignment', () {
      final compiler = LoopIrCompiler(
        loopVarName: 'i',
        startValue: 1,
        endValue: 3,
        stepValue: 1,
      );
      final chunk = compiler.compile([
        Assignment(
          [TableAccessExpr(Identifier('counts'), Identifier('i'))],
          [Identifier('i')],
        ),
      ]);

      expect(chunk, isNotNull);
      expect(chunk!.mainPrototype.instructions, isNotEmpty);
    });
  });

  group('Numeric for loop fast path', () {
    test('sums a range without locals', () async {
      final vm = Interpreter();
      final init = Assignment([Identifier('sum')], [NumberLiteral(0)]);
      final loop = ForLoop(
        Identifier('i'),
        NumberLiteral(1),
        NumberLiteral(5),
        NumberLiteral(1),
        [
          Assignment(
            [Identifier('sum')],
            [BinaryExpression(Identifier('sum'), '+', Identifier('i'))],
          ),
        ],
      );

      await vm.run([init, loop]);
      final result = await Identifier('sum').accept(vm) as Value;
      expect(result.raw, equals(15));
    });

    test('falls back when locals are declared in the body', () async {
      final vm = Interpreter();
      final init = Assignment([Identifier('sum')], [NumberLiteral(0)]);
      final loop = ForLoop(
        Identifier('i'),
        NumberLiteral(1),
        NumberLiteral(4),
        NumberLiteral(1),
        [
          LocalDeclaration([Identifier('tmp')], [''], [Identifier('i')]),
          Assignment(
            [Identifier('sum')],
            [BinaryExpression(Identifier('sum'), '+', Identifier('tmp'))],
          ),
        ],
      );

      await vm.run([init, loop]);
      final result = await Identifier('sum').accept(vm) as Value;
      expect(result.raw, equals(10));
    });

    test('increments dense table slots', () async {
      final vm = Interpreter();
      final program = parse('''
        counts = {0, 0, 0, 0, 0}
        for i = 1, 5, 1 do
          counts[i] = counts[i] + 1
        end
      ''');

      await vm.run(program.statements);
      final Value countsValue = await Identifier('counts').accept(vm) as Value;
      final Map<dynamic, dynamic> rawCounts =
          countsValue.raw as Map<dynamic, dynamic>;
      for (var idx = 1; idx <= 5; idx++) {
        final dynamic entry = rawCounts[idx];
        final Value valueEntry = entry is Value ? entry : Value(entry);
        expect(
          valueEntry.raw,
          equals(1),
          reason: 'counts[$idx] should increment to 1',
        );
      }
    });
  });

  group('ipairs for-in fast path', () {
    test('iterates sequential array values', () async {
      final vm = Interpreter();
      final init = Assignment([Identifier('sum')], [NumberLiteral(0)]);
      final iterator = FunctionCall(Identifier('ipairs'), [
        TableConstructor([
          TableEntryLiteral(NumberLiteral(1)),
          TableEntryLiteral(NumberLiteral(3)),
          TableEntryLiteral(NumberLiteral(5)),
        ]),
      ]);
      final loop = ForInLoop(
        [Identifier('idx'), Identifier('value')],
        [iterator],
        [
          Assignment(
            [Identifier('sum')],
            [BinaryExpression(Identifier('sum'), '+', Identifier('value'))],
          ),
        ],
      );

      await vm.run([init, loop]);
      final result = await Identifier('sum').accept(vm) as Value;
      expect(result.raw, equals(9));
    });

    test('falls back when the body declares locals', () async {
      final vm = Interpreter();
      final init = Assignment([Identifier('sum')], [NumberLiteral(0)]);
      final iterator = FunctionCall(Identifier('ipairs'), [
        TableConstructor([
          TableEntryLiteral(NumberLiteral(2)),
          TableEntryLiteral(NumberLiteral(4)),
          TableEntryLiteral(NumberLiteral(6)),
        ]),
      ]);
      final loop = ForInLoop(
        [Identifier('idx'), Identifier('value')],
        [iterator],
        [
          LocalDeclaration([Identifier('shadow')], [''], [Identifier('value')]),
          Assignment(
            [Identifier('sum')],
            [BinaryExpression(Identifier('sum'), '+', Identifier('shadow'))],
          ),
        ],
      );

      await vm.run([init, loop]);
      final result = await Identifier('sum').accept(vm) as Value;
      expect(result.raw, equals(12));
    });
  });
}
