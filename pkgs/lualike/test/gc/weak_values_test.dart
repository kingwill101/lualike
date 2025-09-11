import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/environment.dart';

void main() {
  group('Weak Values Tests', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      GenerationalGCManager.initialize(interpreter);
      gc = GenerationalGCManager.instance;
    });

    test(
      'weak values table keeps keys but removes entries with dead values',
      () async {
        // Create weak values table
        final weakTable = Value({});
        weakTable.setMetatable({'__mode': 'v'});

        // Add entries with both strong and potentially weak values
        final strongKey = Value('strong_key');
        final weakKey = Value('weak_key');
        final strongValue = Value('strong_value');
        final weakValue = Value('weak_value');

        weakTable.raw[strongKey] = strongValue;
        weakTable.raw[weakKey] = weakValue;

        // Create root environment that references the table and one value
        final rootEnv = Environment();
        final tableBox = Box<Value>(weakTable);
        final strongValueBox = Box<Value>(
          strongValue,
        ); // Keep strong value alive
        rootEnv.define('weak_table', tableBox);
        rootEnv.define('strong_ref', strongValueBox);

        // Verify initial state
        expect((weakTable.raw as Map).length, 2);
        expect((weakTable.raw as Map)[strongKey], equals(strongValue));
        expect((weakTable.raw as Map)[weakKey], equals(weakValue));

        // Perform major collection - weak value should be collected
        await gc.majorCollection([rootEnv]);

        // Strong value entry should remain, weak value entry should be removed
        expect((weakTable.raw as Map).containsKey(strongKey), true);
        expect((weakTable.raw as Map)[strongKey], equals(strongValue));
        expect((weakTable.raw as Map).containsKey(weakKey), false);
        expect((weakTable.raw as Map).length, 1);
      },
    );

    test(
      'weak values table preserves all keys regardless of value liveness',
      () async {
        // Create weak values table
        final weakTable = Value({});
        weakTable.setMetatable({'__mode': 'v'});

        final key1 = Value('key1');
        final key2 = Value('key2');
        final deadValue1 = Value('dead1');
        final deadValue2 = Value('dead2');

        weakTable.raw[key1] = deadValue1;
        weakTable.raw[key2] = deadValue2;

        // Root only references the table (and thus the keys), not the values
        final rootEnv = Environment();
        final tableBox = Box<Value>(weakTable);
        rootEnv.define('weak_table', tableBox);

        expect((weakTable.raw as Map).length, 2);

        // Perform major collection
        await gc.majorCollection([rootEnv]);

        // All entries should be removed since values are dead
        // But keys should have been preserved during marking
        expect((weakTable.raw as Map).length, 0);

        // Verify keys survived the collection (they're in GC generations)
        final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
        expect(allObjects.contains(key1), true);
        expect(allObjects.contains(key2), true);
        expect(allObjects.contains(deadValue1), false);
        expect(allObjects.contains(deadValue2), false);
      },
    );

    test('mixed weak and strong tables behave differently', () async {
      // Create both weak and strong tables with same content
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'v'});

      final strongTable = Value({});
      // No __mode = strong table

      final key = Value('key');
      final value = Value('value');

      weakTable.raw[key] = value;
      strongTable.raw[key] = value;

      // Root references both tables but not the value directly
      final rootEnv = Environment();
      final weakBox = Box<Value>(weakTable);
      final strongBox = Box<Value>(strongTable);
      rootEnv.define('weak_table', weakBox);
      rootEnv.define('strong_table', strongBox);

      expect((weakTable.raw as Map).length, 1);
      expect((strongTable.raw as Map).length, 1);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Strong table should keep the entry, weak table should also keep it
      // because the value is still alive (kept by strong table)
      expect((strongTable.raw as Map).length, 1);
      expect((strongTable.raw as Map)[key], equals(value));
      expect((weakTable.raw as Map).length, 1);
      expect((weakTable.raw as Map)[key], equals(value));

      // Value should survive because strong table kept it alive
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(value), true);
    });

    test(
      'values reachable through other paths survive in weak tables',
      () async {
        // Create weak table
        final weakTable = Value({});
        weakTable.setMetatable({'__mode': 'v'});

        final key1 = Value('key1');
        final key2 = Value('key2');
        final value1 = Value('value1');
        final value2 = Value('value2');

        weakTable.raw[key1] = value1;
        weakTable.raw[key2] = value2;

        // Root references table and one value through another path
        final rootEnv = Environment();
        final tableBox = Box<Value>(weakTable);
        final value1Box = Box<Value>(
          value1,
        ); // Keep value1 alive through other reference
        rootEnv.define('weak_table', tableBox);
        rootEnv.define('other_ref', value1Box);

        expect((weakTable.raw as Map).length, 2);

        // Perform major collection
        await gc.majorCollection([rootEnv]);

        // value1 should survive (referenced elsewhere), value2 should be cleared
        expect((weakTable.raw as Map).length, 1);
        expect((weakTable.raw as Map).containsKey(key1), true);
        expect((weakTable.raw as Map)[key1], equals(value1));
        expect((weakTable.raw as Map).containsKey(key2), false);
      },
    );

    test('nested weak tables work correctly', () async {
      // Create nested weak tables
      final outerWeakTable = Value({});
      outerWeakTable.setMetatable({'__mode': 'v'});

      final innerWeakTable = Value({});
      innerWeakTable.setMetatable({'__mode': 'v'});

      final key1 = Value('outer_key');
      final key2 = Value('inner_key');
      final innerValue = Value('inner_value');

      innerWeakTable.raw[key2] = innerValue;
      outerWeakTable.raw[key1] = innerWeakTable;

      // Root only references outer table
      final rootEnv = Environment();
      final tableBox = Box<Value>(outerWeakTable);
      rootEnv.define('outer_weak_table', tableBox);

      expect((outerWeakTable.raw as Map).length, 1);
      expect((innerWeakTable.raw as Map).length, 1);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Inner table should be cleared from outer table (weak values semantics)
      // because it's only reachable through the outer weak-values table
      expect((outerWeakTable.raw as Map).length, 0);

      // Inner table may still exist as a GCObject but was cleared from outer table
      // Its inner value should also be cleared since it's not strongly reachable
      // (The exact behavior depends on the order of weak table processing)
    });

    test('minor collections do not apply weak clearing', () async {
      // Create weak table with dead value
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'v'});

      final key = Value('key');
      final value = Value('value');
      weakTable.raw[key] = value;

      // Root references only the table, not the value
      final rootEnv = Environment();
      final tableBox = Box<Value>(weakTable);
      rootEnv.define('weak_table', tableBox);

      expect((weakTable.raw as Map).length, 1);

      // Perform minor collection (should not apply weak semantics)
      gc.minorCollection([rootEnv]);

      // Entry should still be there after minor collection
      expect((weakTable.raw as Map).length, 1);
      expect((weakTable.raw as Map)[key], equals(value));

      // Note: After minor collection, objects are promoted to old generation
      // which changes the reachability analysis in subsequent major collections.
      // Currently, values promoted to old gen may be kept alive differently.
      // This is a known limitation of our current generational GC implementation.

      // For now, we test that minor collections don't clear weak entries
      // The major collection behavior after promotion may differ from direct major GC
    });

    test('major collection clears weak values directly', () async {
      // Test major collection without prior minor collection
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'v'});

      final key = Value('key');
      final value = Value('value');
      weakTable.raw[key] = value;

      // Root references only the table, not the value
      final rootEnv = Environment();
      final tableBox = Box<Value>(weakTable);
      rootEnv.define('weak_table', tableBox);

      // Perform major collection directly (no minor collection first)
      await gc.majorCollection([rootEnv]);

      // Entry should be cleared since value is not strongly reachable
      expect((weakTable.raw as Map).length, 0);
    });

    test('string and number keys work with weak values', () async {
      // Create weak table with non-GCObject keys
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'v'});

      final stringKey = 'string_key';
      final numberKey = 42;
      final value1 = Value('value1');
      final value2 = Value('value2');

      weakTable.raw[stringKey] = value1;
      weakTable.raw[numberKey] = value2;

      // Root references only the table
      final rootEnv = Environment();
      final tableBox = Box<Value>(weakTable);
      rootEnv.define('weak_table', tableBox);

      expect((weakTable.raw as Map).length, 2);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Both entries should be cleared (values are dead)
      expect((weakTable.raw as Map).length, 0);
    });

    test('metatable itself is not subject to weak clearing', () async {
      // Create weak table
      final weakTable = Value({});
      final metaFunction = Value('meta_function');
      final metatable = {'__mode': 'v', '__index': metaFunction};
      weakTable.setMetatable(metatable);

      final key = Value('key');
      final value = Value('dead_value');
      weakTable.raw[key] = value;

      // Root references only the table
      final rootEnv = Environment();
      final tableBox = Box<Value>(weakTable);
      rootEnv.define('weak_table', tableBox);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Table entry should be cleared, but metatable should remain intact
      expect((weakTable.raw as Map).length, 0);
      expect(weakTable.metatable, isNotNull);
      expect(weakTable.metatable!['__index'], equals(metaFunction));

      // Metatable function should survive
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(metaFunction), true);
    });

    test('weak table tracking lists are properly managed', () async {
      // Create multiple weak tables
      final weakTable1 = Value({});
      weakTable1.setMetatable({'__mode': 'v'});

      final weakTable2 = Value({});
      weakTable2.setMetatable({'__mode': 'v'});

      final strongTable = Value({});

      final key = Value('key');
      final value = Value('value');

      weakTable1.raw[key] = value;
      weakTable2.raw[key] = value;
      strongTable.raw[key] = value;

      // Root references all tables
      final rootEnv = Environment();
      rootEnv.define('weak1', Box<Value>(weakTable1));
      rootEnv.define('weak2', Box<Value>(weakTable2));
      rootEnv.define('strong', Box<Value>(strongTable));

      // Verify tracking lists are initially empty
      expect(gc.weakValuesTables.length, 0);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Tracking lists should be cleared after collection
      expect(gc.weakValuesTables.length, 0);

      // Value should survive due to strong table reference
      expect((weakTable1.raw as Map).length, 1);
      expect((weakTable2.raw as Map).length, 1);
      expect((strongTable.raw as Map).length, 1);
    });
  });
}
