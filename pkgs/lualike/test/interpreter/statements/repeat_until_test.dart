import 'package:lualike_test/test.dart';

void main() {
  group('RepeatUntilLoop', () {
    test(
      'repeat-until loop executes at least once and stops when condition is true',
      () async {
        // local a = 0; then repeat { a = 1 } until true; a should be 1 afterward

        var assignment = Assignment([Identifier('a')], [NumberLiteral(0)]);
        var assignOne = Assignment([Identifier('a')], [NumberLiteral(1)]);

        // The condition is always true, so the loop should execute exactly once.
        var repeatUntil = RepeatUntilLoop([assignOne], BooleanLiteral(true));

        var vm = Interpreter();
        await vm.run([assignment, repeatUntil]);

        // a should be updated to 1.
        expect(vm.globals.get('a'), equals(Value(1)));
      },
    );
  });
}
