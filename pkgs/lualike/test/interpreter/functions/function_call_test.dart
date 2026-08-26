import 'package:lualike_test/test.dart';

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

    test(
      'reused caller environments preserve escaped closure bindings',
      () async {
        final lua = LuaLike();
        await lua.execute('''
        local function identity(value)
          return value
        end

        local function makeAdder(amount)
          local captured = identity(amount)
          return function(value)
            return captured + value
          end
        end

        local addTwo = makeAdder(2)
        local addTen = makeAdder(10)
        result = addTwo(3) * 100 + addTen(4)
      ''');

        expect(lua.getGlobal('result').unwrap(), equals(514));
      },
    );
  });
}
