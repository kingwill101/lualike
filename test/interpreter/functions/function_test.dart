@Tags(['functions'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Function Definition and Call', () {
    test('Function with no parameters returns single value', () async {
      // Define a function: function foo() return 100 end
      var funcDef = FunctionDef(
        FunctionName(Identifier("foo"), [], null),
        FunctionBody([], [
          ReturnStatement([NumberLiteral(100)]),
        ], false),
      );
      var vm = Interpreter();
      // Store the function definition in the globals.
      await funcDef.accept(vm);
      // Call the function foo with no arguments.
      var funcCall = FunctionCall(Identifier("foo"), []);
      var result = await funcCall.accept(vm);
      expect(result, equals(Value(100)));
    });

    test('Function with parameters returns correct sum', () async {
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
      await funcDef.accept(vm);
      // Call the function add(10, 15) expecting 25.
      var funcCall = FunctionCall(Identifier("add"), [
        NumberLiteral(10),
        NumberLiteral(15),
      ]);
      var result = await funcCall.accept(vm);
      expect(result, equals(Value(25)));
    });

    test('Function returns multiple values as list', () async {
      print("testttt");
      //TODO figure the equivalent of Value.multi  when just testing the ast
      // Define a function: function multi() return 1, 2 end
      var funcDef = FunctionDef(
        FunctionName(Identifier("multi"), [], null),
        FunctionBody([], [
          ReturnStatement([NumberLiteral(1), NumberLiteral(2)]),
        ], false),
      );
      var vm = Interpreter();
      await funcDef.accept(vm);
      // Call the function multi and expect a list [1, 2]
      var funcCall = FunctionCall(Identifier("multi"), []);
      var result = await funcCall.accept(vm);
      expect((result as Value).unwrap(), equals([Value(1), Value(2)]));
    });
  });
}
