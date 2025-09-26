import 'package:lualike_test/test.dart';

/// A simple built-in function that adds two numbers.
class AddBuiltinFunction extends BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) {
      throw Exception("AddBuiltinFunction expects 2 arguments");
    }
    return Value((args[0] as Value).raw + ((args[1] as Value).raw as num));
  }
}

void main() {
  group('BuiltinFunction', () {
    test('AddBuiltinFunction adds two numbers correctly', () async {
      var vm = Interpreter();
      // Define the built-in function "add" in the global environment.
      vm.globals.define("add", AddBuiltinFunction());

      // Create a function call: add(10, 20) which should yield 30.
      var funcCall = FunctionCall(Identifier("add"), [
        NumberLiteral(10),
        NumberLiteral(20),
      ]);

      var result = await funcCall.accept(vm);
      expect(result, equals(Value(30)));
    });
  });
}
