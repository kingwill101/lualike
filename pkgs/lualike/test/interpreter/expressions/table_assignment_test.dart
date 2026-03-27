@Tags(['expressions'])
library;

import 'package:lualike_test/test.dart';

void main() {
  group('Table assignments with undefined identifier keys', () {
    test('dot syntax uses field name when identifier is undefined', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        t = {}
        t.undef = 42
      ''');
      final t = bridge.getGlobal('t') as Value;
      final map = t.raw as Map<dynamic, dynamic>;
      expect(map['undef'], equals(Value(42)));
    });

    test(
      'bracket syntax throws error when using undefined variable as index',
      () async {
        final bridge = LuaLike();
        expect(
          () async => await bridge.execute('''
            t = {}
            t[undef] = 99
          '''),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('Multiple assignment staging', () {
    test(
      'preserves staged table targets when later locals are overwritten',
      () async {
        final bridge = LuaLike();
        final result =
            await bridge.execute(r'''
        local a,i,j,b
        a = {'a', 'b'}
        i = 1
        j = 2
        b = a
        i, a[i], a, j, a[j], a[i+j] = j, i, i, b, j, i
        return i, a, j, b[1], b[2], b[3]
      ''')
                as List<Object?>;

        expect(result.length, equals(6));
        expect(result[0], equals(Value(2)));
        expect(result[1], equals(Value(1)));
        expect(result[2] is Value, isTrue);
        final table = (result[2] as Value).raw as Map<dynamic, dynamic>;
        expect(table[1], equals(Value(1)));
        expect(table[2], equals(Value(2)));
        expect(table[3], equals(Value(1)));
        expect(result[3], equals(Value(1)));
        expect(result[4], equals(Value(2)));
        expect(result[5], equals(Value(1)));
      },
    );
  });
}
