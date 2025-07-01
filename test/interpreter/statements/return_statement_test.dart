import 'package:lualike/testing.dart';

void main() {
  group('ReturnStatement', () {
    test('evaluates and returns the expression value', () async {
      var returnStmt = ReturnStatement([NumberLiteral(42)]);
      var vm = Interpreter();
      try {
        // This call is expected to throw ReturnException.
        await returnStmt.accept(vm);
        fail('Expected ReturnException to be thrown.');
      } on ReturnException catch (e) {
        expect(e.value, equals(Value(42)));
      }
    });
  });
}
