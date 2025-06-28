import 'package:lualike/src/value_class.dart';
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

/// A simple built-in function that multiplies two numbers.
class MultiplyFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 3) {
      throw Exception("MultiplyFunction expects 2 arguments");
    }
    return ((args[1] as Value).raw as num) * ((args[2] as Value).raw as num);
  }
}

void main() {
  Logger.setEnabled(true);
  group('Method Calls', () {
    test('Invokes method on table using dot syntax', () async {
      // Create a table (Map) with a method 'mul'
      final table = ValueClass.table({'mul': MultiplyFunction()});
      final vm = Interpreter();
      // Define the table in globals.
      vm.globals.define("myTable", table);

      // Create a MethodCall: myTable.mul(4, 5) should yield 20.
      var methodCall = MethodCall(Identifier("myTable"), Identifier("mul"), [
        NumberLiteral(4),
        NumberLiteral(5),
      ]);
      var result = await methodCall.accept(vm);
      expect(result, equals(20));
    });

    test('Throws exception for undefined method', () {
      final table = <String, Object?>{};
      final vm = Interpreter();
      vm.globals.define("myTable", table);

      var methodCall = MethodCall(
        Identifier("myTable"),
        Identifier("nonExist"),
        [NumberLiteral(1)],
      );
      expect(() async => await methodCall.accept(vm), throwsException);
    });
  });
}
