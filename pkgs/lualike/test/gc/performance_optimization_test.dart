import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/upvalue.dart';

void main() {
  group('GC Performance Optimization Tests', () {
    late Interpreter vm;
    late GenerationalGCManager gc;

    setUp(() {
      vm = Interpreter();
      GenerationalGCManager.initialize(vm);
      gc = GenerationalGCManager.instance;
    });

    group('Map Traversal Filtering', () {
      test('empty maps are skipped during traversal', () async {
        // Create an empty map that would normally be traversed
        final emptyMap = <String, dynamic>{};
        final value = Value(emptyMap);

        gc.register(value);

        // Force a major collection with the value as root
        await gc.majorCollection([value]);

        // Value should still be alive (not collected due to being in root set)
        expect(gc.youngGen.objects.contains(value), isTrue);
      });

      test('maps without GC objects are skipped efficiently', () async {
        // Create a map with only primitive values
        final primitiveMap = <String, dynamic>{
          'string': 'hello',
          'number': 42,
          'bool': true,
          'null': null,
        };
        final value = Value(primitiveMap);

        gc.register(value);

        // This should not cause excessive traversal
        await gc.majorCollection([value]);

        expect(gc.youngGen.objects.contains(value), isTrue);
      });

      test('maps with GC objects are properly traversed', () async {
        final obj1 = Value('referenced');
        final obj2 = Value('also_referenced');

        gc.register(obj1);
        gc.register(obj2);

        // Create a map containing GC objects
        final mapWithGCObjects = <String, dynamic>{
          'primitive': 'hello',
          'gc_obj1': obj1,
          'number': 42,
          'gc_obj2': obj2,
        };
        final tableValue = Value(mapWithGCObjects);

        gc.register(tableValue);

        // Build root set that includes the table but not the contained objects directly
        final roots = [tableValue];

        await gc.majorCollection(roots);

        // Objects should be kept alive through table traversal
        expect(obj1.marked, isFalse); // Marks are cleared after collection
        expect(obj2.marked, isFalse);
        expect(gc.youngGen.objects.contains(obj1), isTrue);
        expect(gc.youngGen.objects.contains(obj2), isTrue);
      });
    });

    group('Iterable Traversal Filtering', () {
      test('empty iterables are skipped during traversal', () async {
        final emptyList = <dynamic>[];
        final value = Value(emptyList);

        gc.register(value);
        await gc.majorCollection([value]);

        // Test passes if no exception is thrown and performance is maintained
        expect(gc.youngGen.objects.contains(value), isTrue);
      });

      test('iterables without GC objects are skipped efficiently', () async {
        final primitiveList = ['hello', 42, true, null];
        final value = Value(primitiveList);

        gc.register(value);

        await gc.majorCollection([value]);

        expect(gc.youngGen.objects.contains(value), isTrue);
      });

      test('iterables with GC objects are properly traversed', () async {
        final obj1 = Value('item1');
        final obj2 = Value('item2');

        gc.register(obj1);
        gc.register(obj2);

        final listWithGCObjects = ['primitive', obj1, 42, obj2];
        final listValue = Value(listWithGCObjects);

        gc.register(listValue);

        final roots = [listValue];
        await gc.majorCollection(roots);

        // Objects should be kept alive through iterable traversal
        expect(gc.youngGen.objects.contains(obj1), isTrue);
        expect(gc.youngGen.objects.contains(obj2), isTrue);
      });
    });

    group('Memory Estimation Improvements', () {
      test('memory estimation considers object types and sizes', () {
        // Create various types of objects
        final simpleValue = Value(42);
        final tableValue = Value(<String, dynamic>{'a': 1, 'b': 2, 'c': 3});
        final env = Environment();
        env.define('x', Value(1));
        env.define('y', Value(2));

        gc.register(simpleValue);
        gc.register(tableValue);
        gc.register(env);

        final memoryEstimate = gc.estimateMemoryUse();

        // Should be more than just object count * fixed size
        expect(
          memoryEstimate,
          greaterThan(3 * 64),
        ); // More than basic object overhead
        expect(memoryEstimate, lessThan(10000)); // But reasonable
      });

      test('larger tables result in higher memory estimates', () {
        final smallTable = Value(<String, dynamic>{'a': 1});
        final largeTable = Value(<String, dynamic>{
          for (int i = 0; i < 100; i++) 'key$i': i,
        });

        gc.register(smallTable);
        final smallEstimate = gc.estimateMemoryUse();

        gc.register(largeTable);
        final largeEstimate = gc.estimateMemoryUse();

        expect(largeEstimate, greaterThan(smallEstimate));
      });

      test('values with upvalues increase memory estimates', () {
        final simpleValue = Value(42);
        gc.register(simpleValue);
        final simpleEstimate = gc.estimateMemoryUse();

        // Create a value with upvalues (simulating a closure)
        final closureValue = Value((List<Object?> args) => 42);
        closureValue.upvalues = [
          Upvalue(valueBox: Box(Value(1)), name: 'x'),
          Upvalue(valueBox: Box(Value(2)), name: 'y'),
        ];
        gc.register(closureValue);
        final closureEstimate = gc.estimateMemoryUse();

        expect(closureEstimate, greaterThan(simpleEstimate));
      });

      test('values with metatables increase memory estimates', () {
        final simpleTable = Value(<String, dynamic>{'a': 1});
        gc.register(simpleTable);
        final simpleEstimate = gc.estimateMemoryUse();

        final tableWithMeta = Value(<String, dynamic>{'a': 1});
        tableWithMeta.metatable = {'__index': Value('metatable')};
        gc.register(tableWithMeta);
        final metaEstimate = gc.estimateMemoryUse();

        expect(metaEstimate, greaterThan(simpleEstimate));
      });

      test('environments contribute appropriately to memory estimates', () {
        final env1 = Environment();
        env1.define('x', Value(1));

        final env2 = Environment();
        for (int i = 0; i < 10; i++) {
          env2.define('var$i', Value(i));
        }

        gc.register(env1);
        final smallEnvEstimate = gc.estimateMemoryUse();

        gc.register(env2);
        final largeEnvEstimate = gc.estimateMemoryUse();

        expect(largeEnvEstimate, greaterThan(smallEnvEstimate));
      });

      test('memory estimation is stable and consistent', () {
        // Create a consistent set of objects
        final objects = <Value>[];
        for (int i = 0; i < 5; i++) {
          final table = Value(<String, dynamic>{'id': i, 'data': 'item_$i'});
          objects.add(table);
          gc.register(table);
        }

        final estimate1 = gc.estimateMemoryUse();
        final estimate2 = gc.estimateMemoryUse();

        // Should be deterministic
        expect(estimate1, equals(estimate2));

        // Should be reasonable
        expect(estimate1, greaterThan(0));
        expect(estimate1, lessThan(100000));
      });
    });

    group('Performance Integration Tests', () {
      test('large object graphs are handled efficiently', () async {
        final stopwatch = Stopwatch()..start();

        // Create a complex object graph
        final rootTable = Value(<String, dynamic>{});
        gc.register(rootTable);

        final tables = <Value>[];
        for (int i = 0; i < 50; i++) {
          final table = Value(<String, dynamic>{
            'id': i,
            'data': List.generate(10, (j) => 'item_${i}_$j'),
            'refs': <Value>[],
          });
          tables.add(table);
          gc.register(table);
          (rootTable.raw as Map)['table_$i'] = table;
        }

        // Create cross-references
        for (int i = 0; i < tables.length; i++) {
          final refs = (tables[i].raw as Map)['refs'] as List<Value>;
          refs.add(tables[(i + 1) % tables.length]);
          refs.add(tables[(i + 2) % tables.length]);
        }

        final roots = [rootTable];
        await gc.majorCollection(roots);

        stopwatch.stop();

        // Should complete in reasonable time (less than 1 second)
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));

        // All objects should be preserved
        for (final table in tables) {
          expect(
            gc.youngGen.objects.contains(table) ||
                gc.oldGen.objects.contains(table),
            isTrue,
          );
        }
      });

      test('memory estimation scales appropriately with object count', () {
        final estimates = <int>[];

        // Test with increasing numbers of objects
        for (int count in [1, 5, 10, 25, 50]) {
          // Clear previous objects
          gc.youngGen.objects.clear();
          gc.oldGen.objects.clear();

          // Add objects
          for (int i = 0; i < count; i++) {
            final value = Value(<String, dynamic>{
              'id': i,
              'data': List.generate(5, (j) => 'item_$j'),
            });
            gc.register(value);
          }

          estimates.add(gc.estimateMemoryUse());
        }

        // Estimates should generally increase with object count
        for (int i = 1; i < estimates.length; i++) {
          expect(estimates[i], greaterThanOrEqualTo(estimates[i - 1]));
        }

        // Growth should be roughly linear or slightly super-linear
        final ratio = estimates.last / estimates.first;
        expect(ratio, greaterThan(25)); // At least proportional to object count
        expect(ratio, lessThan(200)); // But not exponential
      });
    });
  });
}
