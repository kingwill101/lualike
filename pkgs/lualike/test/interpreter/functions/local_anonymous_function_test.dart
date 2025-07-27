import 'package:lualike_test/test.dart';

void main() {
  group('Local Functions and Anonymous Functions', () {
    test('LocalFunctionDef is callable', () async {
      // local function foo() return 42 end
      var localFunc = LocalFunctionDef(
        Identifier("foo"),
        FunctionBody([], [
          ReturnStatement([NumberLiteral(42)]),
        ], false),
      );
      var vm = Interpreter();
      await localFunc.accept(vm);
      var call = FunctionCall(Identifier("foo"), []);
      var result = await call.accept(vm);
      expect(result, equals(Value(42)));
    });

    test('Anonymous function literal retains its value', () async {
      // Anonymous function: function (x) return x * x end
      var anonFunc = FunctionLiteral(
        FunctionBody(
          [Identifier("x")],
          [
            ReturnStatement([
              BinaryExpression(Identifier("x"), "*", Identifier("x")),
            ]),
          ],
          false,
        ),
      );
      var vm = Interpreter();
      // The anonymous function, when visited, simply returns itself.
      await anonFunc.accept(vm);

      final assignment = Assignment([Identifier("f")], [anonFunc]);
      await assignment.accept(vm);
      var val = await FunctionCall(Identifier("f"), [
        NumberLiteral(5),
      ]).accept(vm);
      expect(val, equals(Value(25)));
    });

    test('Anonymous function can be stored and called', () async {
      // Store an anonymous function in a variable and then call it.
      var anonFunc = FunctionLiteral(
        FunctionBody(
          [Identifier("y")],
          [
            ReturnStatement([
              BinaryExpression(Identifier("y"), "+", NumberLiteral(10)),
            ]),
          ],
          false,
        ),
      );
      var assignFunc = LocalDeclaration([Identifier("f")], [], [anonFunc]);
      var vm = Interpreter();
      await assignFunc.accept(vm);
      var call = FunctionCall(Identifier("f"), [NumberLiteral(5)]);
      var result = await call.accept(vm);
      expect(result, equals(Value(15)));
    });
  });

  test('Function with print statement works', () async {
    // sayHello = function(name) print('Hello, ' .. name .. '!') end
    var funcDef = FunctionLiteral(
      FunctionBody(
        [Identifier("name")],
        [
          ExpressionStatement(
            FunctionCall(Identifier("print"), [
              BinaryExpression(
                BinaryExpression(
                  StringLiteral("Hello, "),
                  "..",
                  Identifier("name"),
                ),
                "..",
                StringLiteral("!"),
              ),
            ]),
          ),
        ],
        false,
      ),
    );

    var vm = Interpreter();

    // Assign function to sayHello
    await Assignment([Identifier("sayHello")], [funcDef]).accept(vm);

    // Call sayHello('John')
    var result = await FunctionCall(Identifier("sayHello"), [
      StringLiteral("John"),
    ]).accept(vm);

    // No return value, but function should execute without error
    expect(result, equals(null));
  });
}
