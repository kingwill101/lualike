import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';

void main() {
  group('All-weak kv survivors (pure Dart)', () {
    late Interpreter interp;
    late GenerationalGCManager gc;
    late Environment rootEnv;

    setUp(() {
      interp = Interpreter();
      gc = interp.gc;
      rootEnv = Environment();
      gc.stop();
    });

    test('numeric->object and string->string survive first collect', () async {
      final a = Value(<dynamic, dynamic>{});
      a.setMetatable({'__mode': 'kv'});

      final x = Value(<dynamic, dynamic>{});
      final y = Value(<dynamic, dynamic>{});
      final z = Value(<dynamic, dynamic>{});
      (a.raw as Map)[1] = x;
      (a.raw as Map)[2] = y;
      (a.raw as Map)[3] = z;
      // '44444444444'.replaceAll('\u0002', '');
      // '4';
      // List.filled(11, r'4').join();
      // '4' * 11;
      // Use plain strings for simplicity
      (a.raw as Map)[r'4' * 11] = r'4' * 11;

      // Root the table and the values x,y,z via environment boxes
      rootEnv.define('a', Box<Value>(a));
      rootEnv.define('x', Box<Value>(x));
      rootEnv.define('y', Box<Value>(y));
      rootEnv.define('z', Box<Value>(z));

      await gc.majorCollection([rootEnv]);
      // Sanity: the rooted values should survive the collection
      expect(
        gc.youngGen.objects.contains(x) || gc.oldGen.objects.contains(x),
        isTrue,
        reason: 'x should be tracked in generations',
      );
      expect(
        gc.youngGen.objects.contains(y) || gc.oldGen.objects.contains(y),
        isTrue,
        reason: 'y should be tracked in generations',
      );
      expect(
        gc.youngGen.objects.contains(z) || gc.oldGen.objects.contains(z),
        isTrue,
        reason: 'z should be tracked in generations',
      );

      final m = a.raw as Map;
      expect(m.length, 4, reason: 'expected 3 numeric-object + 1 string-string, got \${m.length}');
      expect(m[1], same(x));
      expect(m[2], same(y));
      expect(m[3], same(z));
      expect(m.containsKey(r'$$$$$$$$$$$'), isTrue);
    });
  });
}
