import 'package:lualike_test/test.dart';

void main() {
  group('TableFieldAccess inline cache', () {
    test('returns updated value after table mutation', () async {
      final vm = Interpreter();
      final table = ValueClass.table();
      table[Value('value')] = Value(10);
      vm.globals.define('tbl', table);

      final access = TableFieldAccess(Identifier('tbl'), Identifier('value'));

      final first = await access.accept(vm) as Value;
      final second = await access.accept(vm) as Value;

      expect(identical(first, second), isTrue);
      expect(first.raw, equals(10));

      table[Value('value')] = Value(25);

      final third = await access.accept(vm) as Value;

      expect(third.raw, equals(25));
      expect(identical(third, second), isFalse);
    });

    test('skips caching when __index metamethod is present', () async {
      final vm = Interpreter();
      final table = ValueClass.table();
      var callCount = 0;

      table.setMetatable({
        '__index': Value((List<Object?> args) {
          callCount++;
          return Value(callCount);
        }),
      });

      vm.globals.define('tbl2', table);

      final access = TableFieldAccess(Identifier('tbl2'), Identifier('value'));

      final first = await access.accept(vm) as Value;
      final second = await access.accept(vm) as Value;

      expect(first.raw, equals(1));
      expect(second.raw, equals(2));
      expect(callCount, equals(2));
    });
  });
}
