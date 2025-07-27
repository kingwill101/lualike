import 'package:lualike_test/test.dart';

void main() {
  group('Function Parameters', () {
    test('function with parameters returns correct result', () async {
      // Define a function: function add(a, b) return a + b end
      var funcDef = FunctionDef(
        FunctionName(Identifier("add"), [], null),
        FunctionBody(
          [Identifier("a"), Identifier("b")],
          [
            ReturnStatement([
              BinaryExpression(Identifier("a"), "+", Identifier("b")),
            ]),
          ],
          false,
        ),
      );
      var vm = Interpreter();
      // Store the function definition in the environment.
      await funcDef.accept(vm);
      // Call the function add(10, 15) and check if the result is 25.
      var funcCall = FunctionCall(Identifier("add"), [
        NumberLiteral(10),
        NumberLiteral(15),
      ]);
      var result = await funcCall.accept(vm);
      expect(result, equals(Value(25)));
    });
  });
}
