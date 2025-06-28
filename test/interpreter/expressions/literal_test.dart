@Tags(['expressions'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Literal Evaluations', () {
    test('NumberLiteral evaluates to correct numeric value', () async {
      var numLiteral = NumberLiteral(123);
      var vm = Interpreter();
      var result = await numLiteral.accept(vm);
      expect(result, equals(Value(123)));
    });

    test('StringLiteral evaluates to correct string value', () async {
      var strLiteral = StringLiteral("test");
      var vm = Interpreter();
      var result = await strLiteral.accept(vm);
      expect(result, equals(Value("test")));
    });

    test('BooleanLiteral(true) evaluates to true', () async {
      var boolLiteral = BooleanLiteral(true);
      var vm = Interpreter();
      var result = await boolLiteral.accept(vm);
      expect(result, equals(Value(true)));
    });

    test('BooleanLiteral(false) evaluates to false', () async {
      var boolLiteral = BooleanLiteral(false);
      var vm = Interpreter();
      var result = await boolLiteral.accept(vm);
      expect(result, equals(Value(false)));
    });

    test('NilValue evaluates to null', () async {
      var nilNode = NilValue();
      var vm = Interpreter();
      var result = await nilNode.accept(vm);
      expect(result, equals(Value(null)));
    });
  });
}
