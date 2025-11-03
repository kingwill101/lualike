import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  test('Value.tableWeakMode sees __mode=v via metatable', () {
    final a = Value({});
    a.setMetatable({'__mode': 'v'});
    expect(a.tableWeakMode, equals('v'));
    expect(a.hasWeakValues, isTrue);
    expect(a.hasWeakKeys, isFalse);
  });
}
