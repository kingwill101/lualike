import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';

void main() {
  group('Weak Values — Dead Table Semantics', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      gc = interpreter.gc;
      // Disable incremental auto-GC; we will drive a major collection directly
      gc.stop();
    });

    test('unreachable weak-values table does not preserve keys', () async {
      // Create a weak-values table and populate with a collectable key/value.
      final t = Value(<dynamic, dynamic>{});
      t.setMetatable({'__mode': 'v'});

      final key = Value(<dynamic, dynamic>{});
      final value = Value(<dynamic, dynamic>{});
      (t.raw as Map)[key] = value;

      // Do not add the table (or its entries) to any root. Perform a major GC
      // with an empty root set to simulate the table becoming unreachable.
      await gc.majorCollection(/* roots */ []);

      // The unreachable weak-values table must not have influenced clearing.
      // Its keys must not be "preserved" (re-marked) simply because the table
      // existed in a generation list. Both the table and its key/value become
      // dead and are removed from generation tracking.
      final survivors = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(
        survivors.contains(t),
        isFalse,
        reason:
            'dead weak-values table should be collected (not present in generations)',
      );
      expect(
        survivors.contains(key),
        isFalse,
        reason:
            'key from dead weak-values table must not be resurrected/preserved',
      );
      expect(
        survivors.contains(value),
        isFalse,
        reason: 'value from dead weak-values table should be collected',
      );

      // Tracking lists should be empty post-major collection
      expect(gc.weakValuesTables, isEmpty);
      expect(gc.ephemeronTables, isEmpty);
      expect(gc.allWeakTables, isEmpty);
    });
  });
}
