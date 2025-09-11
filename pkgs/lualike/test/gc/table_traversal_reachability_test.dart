import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';

void main() {
  group('Table Traversal Reachability Tests', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      GenerationalGCManager.initialize(interpreter);
      gc = GenerationalGCManager.instance;
    });

    test('objects reachable only via table are kept alive', () async {
      // Create a table with a Value that should be kept alive
      final table = Value({});
      final valueInTable = Value('test_value');
      table['key'] = valueInTable;

      // Create a root that references the table
      final rootEnv = Environment();
      final rootBox = Box<Value>(table);
      rootEnv.define('table_var', rootBox);

      // Verify initial state
      expect(gc.youngGen.objects.length, greaterThan(0));
      expect(valueInTable.marked, false);
      expect(table.marked, false);

      // Perform major collection with the root environment
      await gc.majorCollection([rootEnv]);

      // Both table and value should survive
      expect(table.marked, false); // unmarked after collection
      expect(valueInTable.marked, false); // unmarked after collection

      // Verify they're still in the generations (not freed)
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(table), true);
      expect(allObjects.contains(valueInTable), true);
    });

    test('nested table references are preserved', () async {
      // Create nested tables: root -> table1 -> table2 -> value
      final rootTable = Value({});
      final nestedTable = Value({});
      final deepValue = Value('deep_value');

      nestedTable['deep_key'] = deepValue;
      rootTable['nested'] = nestedTable;

      // Create root
      final rootEnv = Environment();
      final rootBox = Box<Value>(rootTable);
      rootEnv.define('root_table', rootBox);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // All objects should survive
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(rootTable), true);
      expect(allObjects.contains(nestedTable), true);
      expect(allObjects.contains(deepValue), true);
    });

    test('unreferenced table values are collected', () async {
      // Create a table with values
      final table = Value({});
      final referencedValue = Value('referenced');
      final unreferencedValue = Value('unreferenced');

      table['ref_key'] = referencedValue;
      // Don't add unreferencedValue to the table

      // Create root that only references the table
      final rootEnv = Environment();
      final rootBox = Box<Value>(table);
      rootEnv.define('table_var', rootBox);

      // Get initial count
      final initialCount =
          gc.youngGen.objects.length + gc.oldGen.objects.length;

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // The unreferenced value should be collected
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(table), true);
      expect(allObjects.contains(referencedValue), true);
      expect(allObjects.contains(unreferencedValue), false);

      // Total object count should be less than initial
      final finalCount = gc.youngGen.objects.length + gc.oldGen.objects.length;
      expect(finalCount, lessThan(initialCount));
    });

    test('table keys are also preserved', () async {
      // Create a table with Value keys
      final table = Value({});
      final keyValue = Value('key_object');
      final regularValue = Value('value_object');

      // Use Value as key
      table.raw[keyValue] = regularValue;

      // Create root
      final rootEnv = Environment();
      final rootBox = Box<Value>(table);
      rootEnv.define('table_var', rootBox);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Both key and value should survive
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(table), true);
      expect(allObjects.contains(keyValue), true);
      expect(allObjects.contains(regularValue), true);
    });

    test('metatable references are preserved', () async {
      // Create table with metatable
      final table = Value({});
      final metaValue = Value('meta_function');
      final metatable = {'__index': metaValue};

      table.setMetatable(metatable);

      // Create root
      final rootEnv = Environment();
      final rootBox = Box<Value>(table);
      rootEnv.define('table_var', rootBox);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Metatable value should survive
      final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
      expect(allObjects.contains(table), true);
      expect(allObjects.contains(metaValue), true);
    });

    test('weak mode detection works correctly', () {
      // Test weak values
      final weakValuesTable = Value({});
      weakValuesTable.setMetatable({'__mode': 'v'});
      expect(weakValuesTable.tableWeakMode, 'v');
      expect(weakValuesTable.hasWeakValues, true);
      expect(weakValuesTable.hasWeakKeys, false);
      expect(weakValuesTable.isAllWeak, false);

      // Test weak keys
      final weakKeysTable = Value({});
      weakKeysTable.setMetatable({'__mode': 'k'});
      expect(weakKeysTable.tableWeakMode, 'k');
      expect(weakKeysTable.hasWeakValues, false);
      expect(weakKeysTable.hasWeakKeys, true);
      expect(weakKeysTable.isAllWeak, false);

      // Test all weak
      final allWeakTable = Value({});
      allWeakTable.setMetatable({'__mode': 'kv'});
      expect(allWeakTable.tableWeakMode, 'kv');
      expect(allWeakTable.hasWeakValues, true);
      expect(allWeakTable.hasWeakKeys, true);
      expect(allWeakTable.isAllWeak, true);

      // Test no weak mode
      final strongTable = Value({});
      expect(strongTable.tableWeakMode, null);
      expect(strongTable.hasWeakValues, false);
      expect(strongTable.hasWeakKeys, false);
      expect(strongTable.isAllWeak, false);
    });

    test('getReferencesForGC respects weak semantics', () {
      final table = Value({});
      final key = Value('key');
      final value = Value('value');
      table.raw[key] = value;

      // Strong references should include both
      final strongRefs = table.getReferencesForGC(
        strongKeys: true,
        strongValues: true,
      );
      expect(strongRefs.contains(key), true);
      expect(strongRefs.contains(value), true);

      // Weak keys should exclude keys
      final weakKeysRefs = table.getReferencesForGC(
        strongKeys: false,
        strongValues: true,
      );
      expect(weakKeysRefs.contains(key), false);
      expect(weakKeysRefs.contains(value), true);

      // Weak values should exclude values
      final weakValuesRefs = table.getReferencesForGC(
        strongKeys: true,
        strongValues: false,
      );
      expect(weakValuesRefs.contains(key), true);
      expect(weakValuesRefs.contains(value), false);

      // All weak should exclude both
      final allWeakRefs = table.getReferencesForGC(
        strongKeys: false,
        strongValues: false,
      );
      expect(allWeakRefs.contains(key), false);
      expect(allWeakRefs.contains(value), false);
    });

    test('root set builder works', () {
      // Create some environment state
      final env = Environment();
      final testValue = Value('test');
      final testBox = Box<Value>(testValue);
      env.define('test_var', testBox);

      interpreter.setCurrentEnv(env);

      // Build root set
      final roots = gc.buildRootSet(interpreter);

      expect(roots.isNotEmpty, true);
      expect(roots.contains(env), true);
    });

    test('minor collections do not apply weak semantics', () async {
      // Create weak table
      final weakTable = Value({});
      weakTable.setMetatable({'__mode': 'v'});
      final value = Value('should_not_be_cleared');
      weakTable['key'] = value;

      // Create root
      final rootEnv = Environment();
      final rootBox = Box<Value>(weakTable);
      rootEnv.define('weak_table', rootBox);

      // Perform minor collection (should not clear weak entries)
      gc.minorCollection([rootEnv]);

      // Value should still be in the table
      expect(weakTable['key'], equals(value));
    });
  });
}
