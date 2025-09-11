import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';

void main() {
  group('All-Weak Tables Tests', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      GenerationalGCManager.initialize(interpreter);
      gc = GenerationalGCManager.instance;
    });

    test('all-weak table removes entries with dead keys or values', () async {
      // Create all-weak table
      final allWeakTable = Value({});
      allWeakTable.setMetatable({'__mode': 'kv'});

      // Add entries
      final strongKey = Value('strong_key');
      final weakKey = Value('weak_key');
      final strongValue = Value('strong_value');
      final weakValue = Value('weak_value');

      allWeakTable.raw[strongKey] = strongValue;
      allWeakTable.raw[weakKey] = weakValue;

      // Create root environment that references the table, one key, and one value
      final rootEnv = Environment();
      final tableBox = Box<Value>(allWeakTable);
      final strongKeyBox = Box<Value>(strongKey); // Keep strong key alive
      final strongValueBox = Box<Value>(strongValue); // Keep strong value alive
      rootEnv.define('all_weak_table', tableBox);
      rootEnv.define('strong_key_ref', strongKeyBox);
      rootEnv.define('strong_value_ref', strongValueBox);

      // Verify initial state
      expect((allWeakTable.raw as Map).length, 2);
      expect((allWeakTable.raw as Map)[strongKey], equals(strongValue));
      expect((allWeakTable.raw as Map)[weakKey], equals(weakValue));

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Only the entry with both strong key AND strong value should remain
      expect((allWeakTable.raw as Map).length, 1);
      expect((allWeakTable.raw as Map).containsKey(strongKey), true);
      expect((allWeakTable.raw as Map)[strongKey], equals(strongValue));
      expect((allWeakTable.raw as Map).containsKey(weakKey), false);
    });

    test(
      'all-weak table removes entries with dead keys even if values are strong',
      () async {
        final allWeakTable = Value({});
        allWeakTable.setMetatable({'__mode': 'kv'});

        final deadKey = Value('dead_key');
        final strongValue = Value('strong_value');
        allWeakTable.raw[deadKey] = strongValue;

        // Create separate strong reference to the value
        final strongTable = Value({});
        strongTable.raw['value_ref'] = strongValue;

        // Root references both tables but not the key
        final rootEnv = Environment();
        rootEnv.define('all_weak_table', Box<Value>(allWeakTable));
        rootEnv.define('strong_table', Box<Value>(strongTable));

        expect((allWeakTable.raw as Map).length, 1);

        await gc.majorCollection([rootEnv]);

        // Entry should be removed even though value is strongly reachable elsewhere
        expect((allWeakTable.raw as Map).length, 0);
        expect((strongTable.raw as Map)['value_ref'], equals(strongValue));
      },
    );

    test(
      'all-weak table removes entries with dead values even if keys are strong',
      () async {
        final allWeakTable = Value({});
        allWeakTable.setMetatable({'__mode': 'kv'});

        final strongKey = Value('strong_key');
        final deadValue = Value('dead_value');
        allWeakTable.raw[strongKey] = deadValue;

        // Create separate strong reference to the key
        final strongTable = Value({});
        strongTable.raw['key_ref'] = strongKey;

        // Root references both tables but not the value
        final rootEnv = Environment();
        rootEnv.define('all_weak_table', Box<Value>(allWeakTable));
        rootEnv.define('strong_table', Box<Value>(strongTable));

        expect((allWeakTable.raw as Map).length, 1);

        await gc.majorCollection([rootEnv]);

        // Entry should be removed even though key is strongly reachable elsewhere
        expect((allWeakTable.raw as Map).length, 0);
        expect((strongTable.raw as Map)['key_ref'], equals(strongKey));
      },
    );

    test(
      'all-weak table completely cleared when no external references',
      () async {
        final allWeakTable = Value({});
        allWeakTable.setMetatable({'__mode': 'kv'});

        final key1 = Value('key1');
        final key2 = Value('key2');
        final value1 = Value('value1');
        final value2 = Value('value2');

        allWeakTable.raw[key1] = value1;
        allWeakTable.raw[key2] = value2;

        // Root references only the table
        final rootEnv = Environment();
        rootEnv.define('all_weak_table', Box<Value>(allWeakTable));

        expect((allWeakTable.raw as Map).length, 2);

        await gc.majorCollection([rootEnv]);

        // All entries should be cleared
        expect((allWeakTable.raw as Map).length, 0);
      },
    );

    test('all-weak table with primitive keys and values', () async {
      final allWeakTable = Value({});
      allWeakTable.setMetatable({'__mode': 'kv'});

      final valueObj1 = Value('value_obj1');
      final valueObj2 = Value('value_obj2');

      // Mix of primitive and object keys/values
      allWeakTable.raw['string_key'] = valueObj1;
      allWeakTable.raw[42] = valueObj2;
      allWeakTable.raw[Value('obj_key')] = 'string_value';
      allWeakTable.raw[Value('obj_key2')] = valueObj1;

      // Root references only the table and one value
      final rootEnv = Environment();
      rootEnv.define('all_weak_table', Box<Value>(allWeakTable));
      rootEnv.define('strong_value_ref', Box<Value>(valueObj1));

      expect((allWeakTable.raw as Map).length, 4);

      await gc.majorCollection([rootEnv]);

      // Only entries with primitive keys AND strong values should remain
      // string_key -> valueObj1 should remain (primitive key, strong value)
      // 42 -> valueObj2 should be removed (primitive key, dead value)
      // obj_key -> string_value should be removed (dead key, primitive value)
      // obj_key2 -> valueObj1 should be removed (dead key, strong value)
      expect((allWeakTable.raw as Map).length, 1);
      expect((allWeakTable.raw as Map)['string_key'], equals(valueObj1));
    });

    test('all-weak mode detection works correctly', () {
      // Test various all-weak mode representations
      final kvTable = Value({});
      kvTable.setMetatable({'__mode': 'kv'});
      expect(kvTable.tableWeakMode, 'kv');
      expect(kvTable.hasWeakKeys, true);
      expect(kvTable.hasWeakValues, true);
      expect(kvTable.isAllWeak, true);

      final vkTable = Value({});
      vkTable.setMetatable({'__mode': 'vk'});
      expect(vkTable.tableWeakMode, 'kv');
      expect(vkTable.hasWeakKeys, true);
      expect(vkTable.hasWeakValues, true);
      expect(vkTable.isAllWeak, true);

      final kvxTable = Value({});
      kvxTable.setMetatable({'__mode': 'kvx'});
      expect(kvxTable.tableWeakMode, 'kv');
      expect(kvxTable.hasWeakKeys, true);
      expect(kvxTable.hasWeakValues, true);
      expect(kvxTable.isAllWeak, true);
    });

    test('getReferencesForGC respects all-weak semantics', () {
      final table = Value({});
      table.setMetatable({
        '__mode': 'kv',
      }); // Add metatable so there's at least one reference
      final key = Value('key');
      final value = Value('value');
      table.raw[key] = value;

      // All weak should exclude both keys and values
      final allWeakRefs = table.getReferencesForGC(
        strongKeys: false,
        strongValues: false,
      );
      expect(allWeakRefs.contains(key), false);
      expect(allWeakRefs.contains(value), false);

      // Should still include metatable and other non-entry references
      expect(allWeakRefs.length, greaterThanOrEqualTo(1)); // At least metatable
    });

    test('mixed all-weak and strong tables behavior', () async {
      final allWeakTable = Value({});
      allWeakTable.setMetatable({'__mode': 'kv'});

      final strongTable = Value({});

      final key = Value('key');
      final value = Value('value');

      allWeakTable.raw[key] = value;
      strongTable.raw[key] = value;

      // Root references both tables but not key/value directly
      final rootEnv = Environment();
      rootEnv.define('all_weak_table', Box<Value>(allWeakTable));
      rootEnv.define('strong_table', Box<Value>(strongTable));

      expect((allWeakTable.raw as Map).length, 1);
      expect((strongTable.raw as Map).length, 1);

      await gc.majorCollection([rootEnv]);

      // Strong table should keep both key and value alive
      // All-weak table should also keep the entry since both are alive
      expect((strongTable.raw as Map).length, 1);
      expect((allWeakTable.raw as Map).length, 1);
      expect((strongTable.raw as Map)[key], equals(value));
      expect((allWeakTable.raw as Map)[key], equals(value));
    });

    test(
      'all-weak table with weak keys and weak values tables interaction',
      () async {
        final allWeakTable = Value({});
        allWeakTable.setMetatable({'__mode': 'kv'});

        final weakKeysTable = Value({});
        weakKeysTable.setMetatable({'__mode': 'k'});

        final weakValuesTable = Value({});
        weakValuesTable.setMetatable({'__mode': 'v'});

        final key = Value('key');
        final value = Value('value');

        allWeakTable.raw[key] = value;
        weakKeysTable.raw[key] = value;
        weakValuesTable.raw[key] = value;

        // Create strong reference to key only
        final strongKeyRef = Value({});
        strongKeyRef.raw['key'] = key;

        // Root references all tables and strong key reference
        final rootEnv = Environment();
        rootEnv.define('all_weak_table', Box<Value>(allWeakTable));
        rootEnv.define('weak_keys_table', Box<Value>(weakKeysTable));
        rootEnv.define('weak_values_table', Box<Value>(weakValuesTable));
        rootEnv.define('strong_key_ref', Box<Value>(strongKeyRef));

        await gc.majorCollection([rootEnv]);

        // Key survives due to strong reference
        // Ephemeron convergence: since key is marked, value also becomes marked
        // All tables should keep their entries (both key and value are now strong)
        expect((weakKeysTable.raw as Map).length, 1);
        expect((weakValuesTable.raw as Map).length, 1);
        expect((allWeakTable.raw as Map).length, 1);
      },
    );

    test('minor collections do not apply all-weak semantics', () async {
      final allWeakTable = Value({});
      allWeakTable.setMetatable({'__mode': 'kv'});

      final key = Value('key');
      final value = Value('value');
      allWeakTable.raw[key] = value;

      // Root references only the table
      final rootEnv = Environment();
      rootEnv.define('all_weak_table', Box<Value>(allWeakTable));

      expect((allWeakTable.raw as Map).length, 1);

      // Perform minor collection (should not apply weak semantics)
      gc.minorCollection([rootEnv]);

      // Entry should still be there after minor collection
      expect((allWeakTable.raw as Map).length, 1);
      expect((allWeakTable.raw as Map)[key], equals(value));
    });

    test('all-weak tables are tracked during major collection', () async {
      final allWeakTable1 = Value({});
      allWeakTable1.setMetatable({'__mode': 'kv'});

      final allWeakTable2 = Value({});
      allWeakTable2.setMetatable({'__mode': 'vk'});

      final strongTable = Value({});

      final key = Value('key');
      final value = Value('value');

      allWeakTable1.raw[key] = value;
      allWeakTable2.raw[key] = value;
      strongTable.raw[key] = value;

      // Root references all tables
      final rootEnv = Environment();
      rootEnv.define('all_weak1', Box<Value>(allWeakTable1));
      rootEnv.define('all_weak2', Box<Value>(allWeakTable2));
      rootEnv.define('strong', Box<Value>(strongTable));

      // Verify tracking lists are initially empty
      expect(gc.allWeakTables.length, 0);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Tracking lists should be cleared after collection
      expect(gc.allWeakTables.length, 0);

      // All tables should survive with entries due to strong table reference
      expect((allWeakTable1.raw as Map).length, 1);
      expect((allWeakTable2.raw as Map).length, 1);
      expect((strongTable.raw as Map).length, 1);
    });

    test('all-weak table metatable is preserved during clearing', () async {
      final allWeakTable = Value({});
      final metaFunction = Value('meta_function');
      final metatable = {'__mode': 'kv', '__index': metaFunction};
      allWeakTable.setMetatable(metatable);

      final key = Value('key');
      final value = Value('dead_value');
      allWeakTable.raw[key] = value;

      // Root references only the table
      final rootEnv = Environment();
      rootEnv.define('all_weak_table', Box<Value>(allWeakTable));

      await gc.majorCollection([rootEnv]);

      // Table entry should be cleared, but metatable should remain intact
      expect((allWeakTable.raw as Map).length, 0);
      expect(allWeakTable.metatable, isNotNull);
      expect(allWeakTable.metatable!['__index'], equals(metaFunction));

      // Metatable function should survive
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(metaFunction), true);
    });
  });
}
