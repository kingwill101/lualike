import 'package:lualike_test/test.dart';

void main() {
  group('TableConstructor', () {
    test('evaluates empty table constructor', () async {
      var tableConstructor = TableConstructor([]);
      var vm = Interpreter();
      var result = await tableConstructor.accept(vm);
      expect(result, equals(Value({})));
    });

    test('evaluates table constructor with entries', () async {
      // Create table with entries: a = 42, and b = "hello"
      var entry1 = KeyedTableEntry(Identifier("a"), NumberLiteral(42));
      var entry2 = KeyedTableEntry(Identifier("b"), StringLiteral("hello"));
      var tableConstructor = TableConstructor([entry1, entry2]);

      var vm = Interpreter();
      var result = await tableConstructor.accept(vm);

      expect(result, equals(Value({"a": Value(42), "b": Value("hello")})));
    });

    test('throws on nil key in constructor', () async {
      var entry = IndexedTableEntry(NilValue(), NumberLiteral(1));
      var tableConstructor = TableConstructor([entry]);
      var vm = Interpreter();

      expect(
        () async => await tableConstructor.accept(vm),
        throwsA(
          isA<LuaError>().having(
            (e) => e.message,
            'message',
            contains('table index is nil'),
          ),
        ),
      );
    });
  });
}
