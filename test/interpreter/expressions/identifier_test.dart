@Tags(['expressions'])
library;

import 'package:lualike/testing.dart';

void main() {
  group('Identifier evaluation for undefined variables', () {
    test('undefined global resolves to nil', () async {
      final bridge = LuaLike();
      await bridge.execute('result = undef');
      final result = bridge.getGlobal('result') as Value;
      expect(result.raw, isNull);
    });

    test('indexing undefined global throws', () async {
      final bridge = LuaLike();
      expect(
        () async => await bridge.execute('return undef.x'),
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to index a nil value'),
          ),
        ),
      );
    });
  });
}
