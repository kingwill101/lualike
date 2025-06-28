@Tags(['statements'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  Logger.setEnabled(true);
  group('IfStatement', () {
    test('executes thenBlock when condition is true', () async {
      // if true then y = 100 else y = 5
      var condition = BooleanLiteral(true);
      var thenAssign = Assignment([Identifier("y")], [NumberLiteral(100)]);
      var elseAssign = Assignment([Identifier("y")], [NumberLiteral(5)]);
      var ifStmt = IfStatement(condition, [], [thenAssign], [elseAssign]);

      var vm = Interpreter();

      // First declare y with a nil value directly in the global environment
      vm.globals.define("y", Value(null));

      // Run the if statement
      await vm.run([ifStmt]);

      // Read value of y from the global environment
      var result = vm.globals.get("y");
      expect(result, equals(Value(100)));
    });

    test('executes elseBlock when condition is false', () async {
      // if false then y = 100 else y = 5
      var condition = BooleanLiteral(false);
      var thenAssign = Assignment([Identifier("y")], [NumberLiteral(100)]);
      var elseAssign = Assignment([Identifier("y")], [NumberLiteral(5)]);
      var ifStmt = IfStatement(condition, [], [thenAssign], [elseAssign]);

      var vm = Interpreter();

      // First declare y with a nil value directly in the global environment
      vm.globals.define("y", Value(null));

      // Run the if statement
      await vm.run([ifStmt]);

      // Read value of y from the global environment
      var result = vm.globals.get("y");
      expect(result, equals(Value(5)));
    });
  });
}
