@Tags(['statements'])
import 'package:lualike/testing.dart';

void main() {
  group('WhileStatement', () {
    test('does not execute body when condition is false', () async {
      // local x = 10; while (false) do x = 20
      var localDeclaration = LocalDeclaration(
        [Identifier("x")],
        [],
        [NumberLiteral(10)],
      );
      var whileStmt = WhileStatement(BooleanLiteral(false), [
        Assignment([Identifier("x")], [NumberLiteral(20)]),
      ]);
      var vm = Interpreter();
      await vm.run([localDeclaration, whileStmt]);

      // x should remain 10 since the while loop body should not execute.
      var result = await Identifier("x").accept(vm);
      expect(result, equals(Value(10)));
    });
  });
}
