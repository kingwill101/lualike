import 'package:lualike_test/test.dart';

void main() {
  group('Unary Expressions', () {
    test('unary minus on number', () async {
      // Expression: -5
      var expr = UnaryExpression("-", NumberLiteral(5));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(-5)));
    });

    test('unary not on true', () async {
      // Expression: not true, expected false.
      var expr = UnaryExpression("not", BooleanLiteral(true));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect((result as Value).raw, isFalse);
    });

    test('unary not on false', () async {
      // Expression: not false, expected true.
      var expr = UnaryExpression("not", BooleanLiteral(false));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect((result as Value).raw, isTrue);
    });

    test('length operator on string', () async {
      // Expression: #"hello", expected 5.
      var expr = UnaryExpression("#", StringLiteral("hello"));
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(5)));
    });

    test('length operator on list', () async {
      // Expression: #[1,2,3] -- here we simulate a table literal with numeric keys.
      // We use TableConstructor with one literal entry per index.
      var entry1 = TableEntryLiteral(NumberLiteral(1));
      var entry2 = TableEntryLiteral(NumberLiteral(2));
      var entry3 = TableEntryLiteral(NumberLiteral(3));
      var table = TableConstructor([entry1, entry2, entry3]);
      var expr = UnaryExpression("#", table);
      var vm = Interpreter();
      var result = await expr.accept(vm);
      expect(result, equals(Value(3)));
    });
  });
}
