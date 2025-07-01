import 'package:lualike/testing.dart';

void main() {
  group('FunctionCall', () {
    test('function call returns computed value', () async {
      // Define a function: function foo() return 100 end
      var funcDef = FunctionDef(
        FunctionName(Identifier("foo"), [], null),
        FunctionBody([], [
          ReturnStatement([NumberLiteral(100)]),
        ], false),
      );
      var vm = Interpreter();
      // Store the function definition in the environment.
      await funcDef.accept(vm);
      // Create a FunctionCall node to call foo.
      var funcCall = FunctionCall(Identifier("foo"), []);
      var result = await funcCall.accept(vm);
      expect(result, equals(Value(100)));
    });
  });
}
