import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/environment.dart';

void main() {
  group('Weak Keys / Ephemeron Tests', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      GenerationalGCManager.initialize(interpreter);
      gc = GenerationalGCManager.instance;
    });

    test('weak keys table removes entries with dead keys', () async {
      // Create weak keys table
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'k'});

      // Add entries
      final strongKey = Value('strong_key');
      final weakKey = Value('weak_key');
      final value1 = Value('value1');
      final value2 = Value('value2');

      weakTable.raw[strongKey] = value1;
      weakTable.raw[weakKey] = value2;

      // Create root environment that references the table and one key
      final rootEnv = Environment();
      final tableBox = Box<Value>(weakTable);
      final strongKeyBox = Box<Value>(strongKey); // Keep strong key alive
      rootEnv.define('weak_table', tableBox);
      rootEnv.define('strong_key_ref', strongKeyBox);

      // Verify initial state
      expect((weakTable.raw as Map).length, 2);
      expect((weakTable.raw as Map)[strongKey], equals(value1));
      expect((weakTable.raw as Map)[weakKey], equals(value2));

      // Perform major collection - weak key entry should be removed
      await gc.majorCollection([rootEnv]);

      // Strong key entry should remain, weak key entry should be removed
      expect((weakTable.raw as Map).containsKey(strongKey), true);
      expect((weakTable.raw as Map)[strongKey], equals(value1));
      expect((weakTable.raw as Map).containsKey(weakKey), false);
      expect((weakTable.raw as Map).length, 1);
    });

    test(
      'ephemeron convergence - value survives only if key is strongly reachable',
      () async {
        // Create weak keys table
        final weakTable = Value({});
        weakTable.setMetatable({'__mode': 'k'});

        final key = Value('key');
        final value = Value('value');
        final anotherValue = Value('another_value');

        // Create a chain: key -> value in weak table, value -> anotherValue in strong table
        weakTable.raw[key] = value;
        final strongTable = Value({});
        strongTable.raw[value] = anotherValue;

        // Root references weak table and strong table, but not key directly
        final rootEnv = Environment();
        final weakTableBox = Box<Value>(weakTable);
        final strongTableBox = Box<Value>(strongTable);
        rootEnv.define('weak_table', weakTableBox);
        rootEnv.define('strong_table', strongTableBox);

        // Initially, key is not strongly reachable
        await gc.majorCollection([rootEnv]);

        // Key should be cleared (not strongly reachable), but value should survive
        // because it's strongly reachable through the strong table
        expect((weakTable.raw as Map).containsKey(key), false);
        expect((strongTable.raw as Map).containsKey(value), true);
        expect((strongTable.raw as Map)[value], equals(anotherValue));
      },
    );

    test(
      'ephemeron convergence - value survives when key becomes strongly reachable',
      () async {
        // Create weak keys table
        final weakTable = Value({});
        weakTable.setMetatable({'__mode': 'k'});

        final key = Value('key');
        final value = Value('value');

        weakTable.raw[key] = value;

        // Create another strong reference to the key
        final strongTable = Value({});
        strongTable.raw['key_ref'] = key;

        // Root references both tables
        final rootEnv = Environment();
        final weakTableBox = Box<Value>(weakTable);
        final strongTableBox = Box<Value>(strongTable);
        rootEnv.define('weak_table', weakTableBox);
        rootEnv.define('strong_table', strongTableBox);

        await gc.majorCollection([rootEnv]);

        // Key is strongly reachable through strong table, so value should survive
        expect((weakTable.raw as Map).containsKey(key), true);
        expect((weakTable.raw as Map)[key], equals(value));
        expect((strongTable.raw as Map)['key_ref'], equals(key));
      },
    );

    test('complex ephemeron convergence with multiple tables', () async {
      // Create multiple weak keys tables with interconnected references
      final weakTable1 = Value({});
      weakTable1.setMetatable({'__mode': 'k'});

      final weakTable2 = Value({});
      weakTable2.setMetatable({'__mode': 'k'});

      final key1 = Value('key1');
      final key2 = Value('key2');
      final value1 = Value('value1');
      final value2 = Value('value2');

      // Create a cycle: key1 -> value1 in table1, key2 -> value2 in table2
      // value1 and key2 are the same object, value2 and key1 are the same object
      weakTable1.raw[key1] = value1;
      weakTable2.raw[key2] = value2;

      // Make key2 the same as value1, and key1 the same as value2
      // This creates an ephemeron cycle that should converge
      final cycleKey = Value('cycle_key');
      final cycleValue = Value('cycle_value');
      weakTable1.raw[cycleKey] = cycleValue;
      weakTable2.raw[cycleValue] = cycleKey;

      // Root references both tables but no keys directly
      final rootEnv = Environment();
      rootEnv.define('weak_table1', Box<Value>(weakTable1));
      rootEnv.define('weak_table2', Box<Value>(weakTable2));

      await gc.majorCollection([rootEnv]);

      // The cycle should be cleared since no external strong references exist
      expect((weakTable1.raw as Map).length, 0);
      expect((weakTable2.raw as Map).length, 0);
    });

    test('ephemeron with external strong reference breaks cycle', () async {
      // Similar to above but with one external strong reference
      final weakTable1 = Value({});
      weakTable1.setMetatable({'__mode': 'k'});

      final weakTable2 = Value({});
      weakTable2.setMetatable({'__mode': 'k'});

      final cycleKey = Value('cycle_key');
      final cycleValue = Value('cycle_value');
      weakTable1.raw[cycleKey] = cycleValue;
      weakTable2.raw[cycleValue] = cycleKey;

      // Add external strong reference to break the cycle
      final strongTable = Value({});
      strongTable.raw['external_ref'] = cycleKey;

      // Root references all tables
      final rootEnv = Environment();
      rootEnv.define('weak_table1', Box<Value>(weakTable1));
      rootEnv.define('weak_table2', Box<Value>(weakTable2));
      rootEnv.define('strong_table', Box<Value>(strongTable));

      await gc.majorCollection([rootEnv]);

      // The cycle should survive due to external strong reference
      expect((weakTable1.raw as Map).containsKey(cycleKey), true);
      expect((weakTable2.raw as Map).containsKey(cycleValue), true);
      expect((strongTable.raw as Map)['external_ref'], equals(cycleKey));
    });

    test(
      'weak keys table preserves values when keys are strongly reachable',
      () async {
        final weakTable = Value({});
        weakTable.setMetatable({'__mode': 'k'});

        final key1 = Value('key1');
        final key2 = Value('key2');
        final value1 = Value('value1');
        final value2 = Value('value2');

        weakTable.raw[key1] = value1;
        weakTable.raw[key2] = value2;

        // Strong reference to keys in a separate structure
        final keyArray = Value([key1, key2]);

        // Root references table and key array
        final rootEnv = Environment();
        rootEnv.define('weak_table', Box<Value>(weakTable));
        rootEnv.define('key_array', Box<Value>(keyArray));

        await gc.majorCollection([rootEnv]);

        // All entries should survive since keys are strongly reachable
        expect((weakTable.raw as Map).length, 2);
        expect((weakTable.raw as Map)[key1], equals(value1));
        expect((weakTable.raw as Map)[key2], equals(value2));
      },
    );

    test('mixed weak keys and weak values behavior', () async {
      // This will be tested after implementing __mode='kv' in Phase 4
      // For now, just test that __mode='k' is detected correctly
      final weakKeysTable = Value({});
      weakKeysTable.setMetatable({'__mode': 'k'});

      expect(weakKeysTable.tableWeakMode, 'k');
      expect(weakKeysTable.hasWeakKeys, true);
      expect(weakKeysTable.hasWeakValues, false);
      expect(weakKeysTable.isAllWeak, false);
    });

    test('weak keys detection works correctly', () {
      // Test various __mode values
      final weakKeysTable = Value({});
      weakKeysTable.setMetatable({'__mode': 'k'});
      expect(weakKeysTable.tableWeakMode, 'k');
      expect(weakKeysTable.hasWeakKeys, true);
      expect(weakKeysTable.hasWeakValues, false);

      final mixedTable = Value({});
      mixedTable.setMetatable({'__mode': 'kv'});
      expect(mixedTable.tableWeakMode, 'kv');
      expect(mixedTable.hasWeakKeys, true);
      expect(mixedTable.hasWeakValues, true);

      final reverseTable = Value({});
      reverseTable.setMetatable({'__mode': 'vk'});
      expect(reverseTable.tableWeakMode, 'kv');
      expect(reverseTable.hasWeakKeys, true);
      expect(reverseTable.hasWeakValues, true);
    });

    test('getReferencesForGC respects weak keys semantics', () {
      final table = Value({});
      final key = Value('key');
      final value = Value('value');
      table.raw[key] = value;

      // Weak keys should exclude keys from references
      final weakKeysRefs = table.getReferencesForGC(
        strongKeys: false,
        strongValues: true,
      );
      expect(weakKeysRefs.contains(key), false);
      expect(weakKeysRefs.contains(value), true);

      // Strong references should include both
      final strongRefs = table.getReferencesForGC(
        strongKeys: true,
        strongValues: true,
      );
      expect(strongRefs.contains(key), true);
      expect(strongRefs.contains(value), true);
    });

    test('minor collections do not apply weak keys semantics', () async {
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'k'});

      final key = Value('key');
      final value = Value('value');
      weakTable.raw[key] = value;

      // Root references only the table, not the key
      final rootEnv = Environment();
      final tableBox = Box<Value>(weakTable);
      rootEnv.define('weak_table', tableBox);

      expect((weakTable.raw as Map).length, 1);

      // Perform minor collection (should not apply weak semantics)
      gc.minorCollection([rootEnv]);

      // Entry should still be there after minor collection
      expect((weakTable.raw as Map).length, 1);
      expect((weakTable.raw as Map)[key], equals(value));
    });

    test('ephemeron tables are tracked during major collection', () async {
      final weakTable1 = Value({});
      weakTable1.setMetatable({'__mode': 'k'});

      final weakTable2 = Value({});
      weakTable2.setMetatable({'__mode': 'k'});

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
      expect(gc.ephemeronTables.length, 0);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Tracking lists should be cleared after collection
      expect(gc.ephemeronTables.length, 0);

      // Value should survive due to strong table reference
      expect((weakTable1.raw as Map).length, 1);
      expect((weakTable2.raw as Map).length, 1);
      expect((strongTable.raw as Map).length, 1);
    });
  });
}
