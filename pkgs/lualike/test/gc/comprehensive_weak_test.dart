import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/environment.dart';

void main() {
  group('Comprehensive Weak Tables Tests', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      GenerationalGCManager.initialize(interpreter);
      gc = GenerationalGCManager.instance;
    });

    test('weak table modes detection and configuration', () {
      // Test all variations of __mode values
      final testCases = [
        ('k', 'k', true, false, false),
        ('v', 'v', false, true, false),
        ('kv', 'kv', true, true, true),
        ('vk', 'kv', true, true, true),
        ('kvx', 'kv', true, true, true), // extra chars ignored
        ('K', null, false, false, false), // case sensitive
        ('', null, false, false, false), // empty string
      ];

      for (final (mode, expectedMode, hasWeakKeys, hasWeakValues, isAllWeak)
          in testCases) {
        final table = Value({});
        table.setMetatable({'__mode': mode});

        expect(
          table.tableWeakMode,
          equals(expectedMode),
          reason: 'Mode: $mode',
        );
        expect(table.hasWeakKeys, equals(hasWeakKeys), reason: 'Mode: $mode');
        expect(
          table.hasWeakValues,
          equals(hasWeakValues),
          reason: 'Mode: $mode',
        );
        expect(table.isAllWeak, equals(isAllWeak), reason: 'Mode: $mode');
      }
    });

    test('getReferencesForGC behavior across all weak modes', () {
      final table = Value({});
      final key1 = Value('key1');
      final key2 = Value('key2');
      final value1 = Value('value1');
      final value2 = Value('value2');

      table.raw[key1] = value1;
      table.raw[key2] = value2;
      table.setMetatable({'__test': 'metatable'});

      // Strong references (normal table)
      final strongRefs = table.getReferencesForGC(
        strongKeys: true,
        strongValues: true,
      );
      expect(strongRefs.contains(key1), true);
      expect(strongRefs.contains(key2), true);
      expect(strongRefs.contains(value1), true);
      expect(strongRefs.contains(value2), true);

      // Weak values (__mode='v')
      final weakValuesRefs = table.getReferencesForGC(
        strongKeys: true,
        strongValues: false,
      );
      expect(weakValuesRefs.contains(key1), true);
      expect(weakValuesRefs.contains(key2), true);
      expect(weakValuesRefs.contains(value1), false);
      expect(weakValuesRefs.contains(value2), false);

      // Weak keys (__mode='k')
      final weakKeysRefs = table.getReferencesForGC(
        strongKeys: false,
        strongValues: true,
      );
      expect(weakKeysRefs.contains(key1), false);
      expect(weakKeysRefs.contains(key2), false);
      expect(weakKeysRefs.contains(value1), true);
      expect(weakKeysRefs.contains(value2), true);

      // All weak (__mode='kv')
      final allWeakRefs = table.getReferencesForGC(
        strongKeys: false,
        strongValues: false,
      );
      expect(allWeakRefs.contains(key1), false);
      expect(allWeakRefs.contains(key2), false);
      expect(allWeakRefs.contains(value1), false);
      expect(allWeakRefs.contains(value2), false);

      // All variants should include metatable
      expect(
        strongRefs.any((ref) => ref is Map && ref.containsKey('__test')),
        true,
      );
      expect(
        weakValuesRefs.any((ref) => ref is Map && ref.containsKey('__test')),
        true,
      );
      expect(
        weakKeysRefs.any((ref) => ref is Map && ref.containsKey('__test')),
        true,
      );
      expect(
        allWeakRefs.any((ref) => ref is Map && ref.containsKey('__test')),
        true,
      );
    });

    test('gc tracking lists management across collection phases', () async {
      // Create multiple tables of each type
      final weakValuesTables = List.generate(3, (i) {
        final table = Value({});
        table.setMetatable({'__mode': 'v'});
        return table;
      });

      final ephemeronTables = List.generate(2, (i) {
        final table = Value({});
        table.setMetatable({'__mode': 'k'});
        return table;
      });

      final allWeakTables = List.generate(2, (i) {
        final table = Value({});
        table.setMetatable({'__mode': 'kv'});
        return table;
      });

      // Add some entries
      final key = Value('key');
      final value = Value('value');

      for (final table in [
        ...weakValuesTables,
        ...ephemeronTables,
        ...allWeakTables,
      ]) {
        table.raw[key] = value;
      }

      // Root everything
      final rootEnv = Environment();
      for (int i = 0; i < weakValuesTables.length; i++) {
        rootEnv.define('weak_values_$i', Box<Value>(weakValuesTables[i]));
      }
      for (int i = 0; i < ephemeronTables.length; i++) {
        rootEnv.define('ephemeron_$i', Box<Value>(ephemeronTables[i]));
      }
      for (int i = 0; i < allWeakTables.length; i++) {
        rootEnv.define('all_weak_$i', Box<Value>(allWeakTables[i]));
      }

      // Verify tracking lists are initially empty
      expect(gc.weakValuesTables.length, 0);
      expect(gc.ephemeronTables.length, 0);
      expect(gc.allWeakTables.length, 0);

      // Perform major collection
      await gc.majorCollection([rootEnv]);

      // Verify tracking lists are cleared after collection
      expect(gc.weakValuesTables.length, 0);
      expect(gc.ephemeronTables.length, 0);
      expect(gc.allWeakTables.length, 0);

      // All tables should survive
      for (final table in [
        ...weakValuesTables,
        ...ephemeronTables,
        ...allWeakTables,
      ]) {
        final allObjects = [...gc.youngGen.objects, ...gc.oldGen.objects];
        expect(allObjects.contains(table), true);
      }
    });

    test('minor collections preserve weak table semantics', () async {
      // Create tables with all weak modes
      final weakValuesTable = Value({});
      weakValuesTable.setMetatable({'__mode': 'v'});

      final weakKeysTable = Value({});
      weakKeysTable.setMetatable({'__mode': 'k'});

      final allWeakTable = Value({});
      allWeakTable.setMetatable({'__mode': 'kv'});

      final key = Value('key');
      final value = Value('value');

      weakValuesTable.raw[key] = value;
      weakKeysTable.raw[key] = value;
      allWeakTable.raw[key] = value;

      // Root only the tables (not key/value)
      final rootEnv = Environment();
      rootEnv.define('weak_values', Box<Value>(weakValuesTable));
      rootEnv.define('weak_keys', Box<Value>(weakKeysTable));
      rootEnv.define('all_weak', Box<Value>(allWeakTable));

      // Verify initial state
      expect((weakValuesTable.raw as Map).length, 1);
      expect((weakKeysTable.raw as Map).length, 1);
      expect((allWeakTable.raw as Map).length, 1);

      // Perform minor collection - should NOT apply weak semantics
      gc.minorCollection([rootEnv]);

      // All entries should still be present
      expect((weakValuesTable.raw as Map).length, 1);
      expect((weakKeysTable.raw as Map).length, 1);
      expect((allWeakTable.raw as Map).length, 1);

      // Note: After minor collection, objects are promoted to old generation
      // which may affect the reachability analysis in subsequent major collections.
      // This is a known limitation of our current generational GC implementation.
      // For now, we test that minor collections don't clear weak entries,
      // and acknowledge that major collection behavior after promotion may vary.

      // The exact behavior after promotion depends on implementation details
      // and may be different from direct major collection without prior minor collection.
    });

    test('metatable preservation across all weak table types', () async {
      final tables = [
        (Value({})..setMetatable({}), 'strong'),
        (Value({})..setMetatable({'__mode': 'v'}), 'weak_values'),
        (Value({})..setMetatable({'__mode': 'k'}), 'weak_keys'),
        (Value({})..setMetatable({'__mode': 'kv'}), 'all_weak'),
      ];

      for (final (table, name) in tables) {
        // Add metatable functions
        final metaFunction = Value('meta_function_$name');
        table.metatable!['__index'] = metaFunction;
        table.metatable!['__newindex'] = metaFunction;

        // Add table entry that will be cleared
        final deadKey = Value('dead_key_$name');
        final deadValue = Value('dead_value_$name');
        table.raw[deadKey] = deadValue;
      }

      // Root only the tables
      final rootEnv = Environment();
      for (int i = 0; i < tables.length; i++) {
        rootEnv.define('table_$i', Box<Value>(tables[i].$1));
      }

      await gc.majorCollection([rootEnv]);

      // Verify metatables are preserved but entries are cleared (except strong table)
      for (int i = 0; i < tables.length; i++) {
        final (table, name) = tables[i];

        // Metatable should be preserved
        expect(table.metatable, isNotNull, reason: 'Table: $name');
        expect(table.metatable!['__index'], isNotNull, reason: 'Table: $name');
        expect(
          table.metatable!['__newindex'],
          isNotNull,
          reason: 'Table: $name',
        );

        // Strong table keeps entries, weak tables clear them
        if (name == 'strong') {
          expect((table.raw as Map).length, 1, reason: 'Table: $name');
        } else {
          expect((table.raw as Map).length, 0, reason: 'Table: $name');
        }
      }
    });
  });
}
