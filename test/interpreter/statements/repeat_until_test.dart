import 'package:lualike/testing.dart';

void main() {
  group('RepeatUntilLoop', () {
    test(
      'repeat-until loop executes at least once and stops when condition is true',
      () async {
        // local a = 0; then repeat { a = 1 } until true; a should be 1 afterward

        var localDeclaration = LocalDeclaration(
          [Identifier('a')],
          [],
          [NumberLiteral(0)],
        );
        var assignOne = Assignment([Identifier('a')], [NumberLiteral(1)]);

        // The condition is always true, so the loop should execute exactly once.
        var repeatUntil = RepeatUntilLoop([assignOne], BooleanLiteral(true));

        var vm = Interpreter();
        await vm.run([localDeclaration, repeatUntil]);

        // a should be updated to 1.
        var result = await Identifier('a').accept(vm);
        expect(result, equals(Value(1)));
      },
    );
  });
}
