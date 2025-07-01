import 'package:lualike/testing.dart';

void main() {
  group('BinaryExpression', () {
    test('evaluates addition', () async {
      // expression: 5 + 3
      var expr = BinaryExpression(NumberLiteral(5), '+', NumberLiteral(3));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(8)));
    });

    test('evaluates subtraction', () async {
      // expression: 10 - 4
      var expr = BinaryExpression(NumberLiteral(10), '-', NumberLiteral(4));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(6)));
    });

    test('evaluates multiplication', () async {
      // expression: 7 * 6
      var expr = BinaryExpression(NumberLiteral(7), '*', NumberLiteral(6));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(42)));
    });

    test('evaluates division', () async {
      // expression: 20 / 5
      var expr = BinaryExpression(NumberLiteral(20), '/', NumberLiteral(5));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(4)));
    });
    test('evaluates string concatenation', () async {
      // expression: "hello" .. "world"
      var expr = BinaryExpression(
        StringLiteral("hello"),
        '..',
        StringLiteral("world"),
      );
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value("helloworld")));

      // expression: "count: " .. 42
      expr = BinaryExpression(
        StringLiteral("count: "),
        '..',
        NumberLiteral(42),
      );
      result = await expr.accept(vm);
      expect(result, equals(Value("count: 42")));
    });
  });
}
