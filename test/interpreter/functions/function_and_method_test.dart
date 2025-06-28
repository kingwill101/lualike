import 'package:lualike/lualike.dart';
import 'package:lualike/src/value_class.dart';
import 'package:test/test.dart';

/// A simple builtin function that increments a number.
class IncFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) {
      throw Exception("IncFunction expects 1 argument");
    }
    return Value(((args[1] as Value).raw as num) + 1);
  }
}

void main() {
  group('Local Functions', () {
    test('LocalFunctionDef is stored and callable', () async {
      // Define a local function: local function foo() return 42 end
      var localFunc = LocalFunctionDef(
        Identifier("foo"),
        FunctionBody([], [
          ReturnStatement([NumberLiteral(42)]),
        ], false),
      );
      var vm = Interpreter();
      // Store the local function in globals.
      await localFunc.accept(vm);
      // Later, call the function foo.
      var funcCall = FunctionCall(Identifier("foo"), []);
      var result = await funcCall.accept(vm);
      expect(result, equals(Value(42)));
    });
  });

  test('Anonymous Functions ', () async {
    // Define an anonymous function: function (x) return x * x end
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
    final call = await FunctionCall(anonFunc, [NumberLiteral(5)]).accept(vm);
    // Calling accept on a FunctionLiteral returns the literal itself.
    expect(call, equals(Value(25)));
  });

  group('Method Calls', () {
    test('MethodCall invokes a method on a table', () async {
      // Create a table (a Map) with a method 'inc'.
      var table = ValueClass.table({'inc': IncFunction()});
      var vm = Interpreter();
      // Define the table in globals.
      vm.globals.define("table", table);
      // Create a method call: table: inc(5)
      var methodCall = MethodCall(Identifier("table"), Identifier("inc"), [
        NumberLiteral(5),
      ]);
      var result = await methodCall.accept(vm);
      expect(result, equals(Value(6)));
    });
  });
}
