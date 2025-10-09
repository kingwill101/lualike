import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Metatable registry visibility', () {
    test('weak mode visible across wrappers', () {
      final map = <dynamic, dynamic>{};
      final a = Value(map);
      a.setMetatable({'__mode': 'k'});

      // Simulate an alternate wrapper encountered in GC paths
      final b = Value(map);

      expect(a.tableWeakMode, 'k');
      expect(
        b.tableWeakMode,
        'k',
        reason: 'Registered metatable should be visible via raw Map',
      );
      expect(a.hasWeakKeys, isTrue);
      expect(b.hasWeakKeys, isTrue);
    });
  });
}
