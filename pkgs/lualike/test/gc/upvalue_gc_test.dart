import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/upvalue.dart';

void main() {
  group('Upvalue GC Object Tests', () {
    late Interpreter interpreter;
    late GenerationalGCManager gc;

    setUp(() {
      interpreter = Interpreter();
      GenerationalGCManager.initialize(interpreter);
      gc = GenerationalGCManager.instance;
    });

    group('Upvalue GC Registration', () {
      test('upvalues are registered as GC objects', () {
        final box = Box<dynamic>(Value(42));
        final upvalue = Upvalue(valueBox: box, name: 'test');

        // Upvalue should be registered with GC
        expect(
          gc.youngGen.objects.contains(upvalue) ||
              gc.oldGen.objects.contains(upvalue),
          isTrue,
        );
      });

      test('upvalue getReferences includes valueBox', () {
        final testValue = Value('test_value');
        final box = Box<dynamic>(testValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        gc.register(testValue);

        final refs = upvalue.getReferences();
        expect(refs.contains(box), isTrue);
      });

      test('closed upvalue includes closed value in references', () {
        final testValue = Value('test_value');
        final box = Box<dynamic>(testValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        gc.register(testValue);

        // Close the upvalue
        upvalue.close();

        final refs = upvalue.getReferences();
        // Should include the closed value if it's a GCObject
        expect(refs.contains(testValue), isTrue);
      });

      test('joined upvalue includes joined upvalue in references', () {
        final box1 = Box<dynamic>(Value(1));
        final box2 = Box<dynamic>(Value(2));
        final upvalue1 = Upvalue(valueBox: box1, name: 'test1');
        final upvalue2 = Upvalue(valueBox: box2, name: 'test2');

        // Join upvalue1 with upvalue2
        upvalue1.joinWith(upvalue2);

        final refs = upvalue1.getReferences();
        expect(refs.contains(upvalue2), isTrue);
      });
    });

    group('Upvalue Collection Behavior', () {
      test('upvalues are collected when unreachable', () async {
        final testValue = Value('test_value');
        final box = Box<dynamic>(testValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        gc.register(testValue);

        // Collect without including upvalue or testValue in roots
        await gc.majorCollection([]);

        // Both should be collected
        expect(gc.youngGen.objects.contains(upvalue), isFalse);
        expect(gc.youngGen.objects.contains(testValue), isFalse);
      });

      test('upvalues keep their values alive', () async {
        final testValue = Value('test_value');
        final box = Box<dynamic>(testValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        gc.register(testValue);

        // Collect with upvalue as root (but not testValue directly)
        await gc.majorCollection([upvalue]);

        // testValue should be kept alive through upvalue -> box -> value
        expect(gc.youngGen.objects.contains(upvalue), isTrue);
        expect(gc.youngGen.objects.contains(testValue), isTrue);
      });

      test('values keep their upvalues alive', () async {
        final testValue = Value('test_value');
        final box = Box<dynamic>(Value(1));
        final upvalue = Upvalue(valueBox: box, name: 'test');

        // Create a function value that references the upvalue
        final functionValue = Value((List<Object?> args) => 42);
        functionValue.upvalues = [upvalue];

        gc.register(testValue);

        // Collect with functionValue as root
        await gc.majorCollection([functionValue]);

        // Upvalue should be kept alive through function
        expect(gc.youngGen.objects.contains(functionValue), isTrue);
        expect(gc.youngGen.objects.contains(upvalue), isTrue);
      });
    });

    group('Upvalue Weak Table Integration', () {
      test('upvalues work correctly with weak values tables', () async {
        final key = Value('key');
        final upvalueValue = Value('upvalue_content');
        final box = Box<dynamic>(upvalueValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        gc.register(key);
        gc.register(upvalueValue);

        // Create weak values table
        final weakTable = Value(<dynamic, dynamic>{});
        weakTable.metatable = {'__mode': 'v'};
        (weakTable.raw as Map)[key] = upvalue;

        gc.register(weakTable);

        // Collect with key and weakTable as roots (but not upvalue or upvalueValue)
        await gc.majorCollection([key, weakTable]);

        // Upvalue should be collected, and entry should be cleared
        expect(gc.youngGen.objects.contains(upvalue), isFalse);
        expect((weakTable.raw as Map).containsKey(key), isFalse);
      });

      test('upvalues work correctly with weak keys tables', () async {
        final value = Value('value');
        final upvalueValue = Value('upvalue_content');
        final box = Box<dynamic>(upvalueValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        gc.register(value);
        gc.register(upvalueValue);

        // Create weak keys table
        final weakTable = Value(<dynamic, dynamic>{});
        weakTable.metatable = {'__mode': 'k'};
        (weakTable.raw as Map)[upvalue] = value;

        gc.register(weakTable);

        // Collect with value and weakTable as roots (but not upvalue)
        await gc.majorCollection([value, weakTable]);

        // Upvalue (key) should be collected, and entry should be cleared
        expect(gc.youngGen.objects.contains(upvalue), isFalse);
        expect((weakTable.raw as Map).containsKey(upvalue), isFalse);
      });

      test('strongly reachable upvalues survive in weak keys tables', () async {
        final value = Value('value');
        final upvalueValue = Value('upvalue_content');
        final box = Box<dynamic>(upvalueValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        // Create a function that keeps the upvalue alive
        final functionValue = Value((List<Object?> args) => 42);
        functionValue.upvalues = [upvalue];

        gc.register(value);
        gc.register(upvalueValue);

        // Create weak keys table
        final weakTable = Value(<dynamic, dynamic>{});
        weakTable.metatable = {'__mode': 'k'};
        (weakTable.raw as Map)[upvalue] = value;

        gc.register(weakTable);

        // Collect with functionValue, value, and weakTable as roots
        await gc.majorCollection([functionValue, value, weakTable]);

        // Upvalue should survive through function reference
        expect(gc.youngGen.objects.contains(upvalue), isTrue);
        expect((weakTable.raw as Map).containsKey(upvalue), isTrue);
      });
    });

    group('Upvalue Memory Estimation', () {
      test('upvalues contribute to memory estimation', () {
        final initialEstimate = gc.estimateMemoryUse();

        // Create upvalues with different characteristics
        final box1 = Box<dynamic>(Value(1));
        Upvalue(valueBox: box1, name: 'short');

        final estimate1 = gc.estimateMemoryUse();
        expect(estimate1, greaterThan(initialEstimate));

        final box2 = Box<dynamic>(Value(2));
        Upvalue(valueBox: box2, name: 'very_long_name_for_testing');

        final estimate2 = gc.estimateMemoryUse();
        expect(estimate2, greaterThan(estimate1));

        // Upvalues should contribute significantly to memory usage
        expect(estimate2, greaterThan(initialEstimate + 300));
      });

      test('closed upvalues affect memory estimation', () {
        final box = Box<dynamic>(Value('test'));
        final upvalue = Upvalue(valueBox: box, name: 'test');

        final openEstimate = gc.estimateMemoryUse();

        // Close the upvalue
        upvalue.close();

        final closedEstimate = gc.estimateMemoryUse();

        // Closed upvalue should have slightly different memory footprint
        expect(closedEstimate, isNot(equals(openEstimate)));
      });
    });

    group('Upvalue Finalization', () {
      test('upvalue free method properly cleans up', () {
        final testValue = Value('test');
        final box = Box<dynamic>(testValue);
        final upvalue = Upvalue(valueBox: box, name: 'test');

        final otherUpvalue = Upvalue(
          valueBox: Box<dynamic>(Value(2)),
          name: 'other',
        );
        upvalue.joinWith(otherUpvalue);

        expect(upvalue.isJoined, isTrue);
        expect(upvalue.isOpen, isTrue);

        // Free the upvalue
        upvalue.free();

        // Should be closed and cleaned up
        expect(upvalue.isOpen, isFalse);
        expect(upvalue.isJoined, isFalse);
      });
    });

    group('Complex Upvalue Scenarios', () {
      test(
        'nested closure upvalue chains survive collection correctly',
        () async {
          // Create a chain of closures with upvalues
          final baseValue = Value('base');
          final box1 = Box<dynamic>(baseValue);
          final upvalue1 = Upvalue(valueBox: box1, name: 'outer');

          final intermediateValue = Value('intermediate');
          final box2 = Box<dynamic>(intermediateValue);
          final upvalue2 = Upvalue(valueBox: box2, name: 'middle');

          final innerValue = Value('inner');
          final box3 = Box<dynamic>(innerValue);
          final upvalue3 = Upvalue(valueBox: box3, name: 'inner');

          // Create nested functions
          final outerFunction = Value((List<Object?> args) => 'outer');
          outerFunction.upvalues = [upvalue1];

          final middleFunction = Value((List<Object?> args) => 'middle');
          middleFunction.upvalues = [upvalue2, upvalue1]; // References outer

          final innerFunction = Value((List<Object?> args) => 'inner');
          innerFunction.upvalues = [
            upvalue3,
            upvalue2,
            upvalue1,
          ]; // References all

          gc.register(baseValue);
          gc.register(intermediateValue);
          gc.register(innerValue);

          // Collect with only the innermost function as root
          await gc.majorCollection([innerFunction]);

          // All upvalues and values should survive through the chain
          expect(gc.youngGen.objects.contains(innerFunction), isTrue);
          expect(gc.youngGen.objects.contains(upvalue1), isTrue);
          expect(gc.youngGen.objects.contains(upvalue2), isTrue);
          expect(gc.youngGen.objects.contains(upvalue3), isTrue);
          expect(gc.youngGen.objects.contains(baseValue), isTrue);
          expect(gc.youngGen.objects.contains(intermediateValue), isTrue);
          expect(gc.youngGen.objects.contains(innerValue), isTrue);
        },
      );

      test('upvalue joining with gc works correctly', () async {
        final value1 = Value('value1');
        final value2 = Value('value2');
        final box1 = Box<dynamic>(value1);
        final box2 = Box<dynamic>(value2);
        final upvalue1 = Upvalue(valueBox: box1, name: 'up1');
        final upvalue2 = Upvalue(valueBox: box2, name: 'up2');

        gc.register(value1);
        gc.register(value2);

        // Join upvalues
        upvalue1.joinWith(upvalue2);

        // Create function that only references upvalue1
        final function = Value((List<Object?> args) => 42);
        function.upvalues = [upvalue1];

        // Collect with function as root
        await gc.majorCollection([function]);

        // Both upvalues should survive (upvalue1 directly, upvalue2 through join)
        expect(gc.youngGen.objects.contains(upvalue1), isTrue);
        expect(gc.youngGen.objects.contains(upvalue2), isTrue);

        // value2 should survive through upvalue2, value1 might be collected
        expect(gc.youngGen.objects.contains(value2), isTrue);
      });
    });
  });
}
