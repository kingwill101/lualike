import 'package:lualike/testing.dart';

void main() {
  group('Value Basics', () {
    test('basic value wrapping', () {
      expect(Value(42).raw, equals(42));
      expect(Value("hello").raw, equals("hello"));
      expect(Value(true).raw, equals(true));
      expect(Value(null).raw, equals(null));
    });

    test('value equality', () {
      expect(Value(42), equals(Value(42)));
      expect(Value("hello"), equals(Value("hello")));
      expect(Value(true), equals(Value(true)));
      expect(Value(null), equals(Value(null)));
      expect(Value(42) == Value(43), isFalse);
    });
  });

  group('Value Metatable Operations', () {
    test('setting and getting metatable', () {
      final v = Value(42);
      final mt = {
        '__add': (args) => Value((args[0].raw as num) + (args[1].raw as num)),
      };
      v.setMetatable(mt);
      expect(v.getMetatable(), equals(mt));
    });

    test('metamethod lookup', () {
      final v = Value(42);
      add(args) => Value((args[0].raw as num) + (args[1].raw as num));
      v.setMetatable({'__add': add});
      expect(v.getMetamethod('__add'), equals(add));
      expect(v.getMetamethod('nonexistent'), isNull);
    });
  });

  group('Value Table Operations', () {
    test('table creation and access', () {
      final table = Value({});
      table['key'] = Value('value');
      expect(table['key'].raw, equals('value'));
    });

    test('nested tables', () {
      final table = Value({
        'nested': Value({'deep': Value('value')}),
      });
      expect((table['nested'].raw as Map)['deep'].raw, equals('value'));
    });

    test('table copying', () {
      final original = Value({
        'key': Value('value'),
        'nested': Value({'deep': Value(42)}),
      });
      final copy = original.copy();

      // Verify it's a deep copy
      expect(copy, equals(original));
      expect(copy.raw, isNot(same(original.raw)));
      expect(
        (copy.raw as Map)['nested'].raw,
        isNot(same((original.raw as Map)['nested'].raw)),
      );
    });
  });

  group('Value Wrapping and Unwrapping', () {
    test('wrap primitive values', () {
      expect(Value.wrap(42).raw, equals(42));
      expect(Value.wrap("test").raw, equals("test"));
      expect(Value.wrap(true).raw, equals(true));
    });

    test('wrap nested structures', () {
      final wrapped = Value.wrap({
        'number': 42,
        'string': 'test',
        'nested': {'deep': true},
      });

      expect(wrapped.raw is Map, isTrue);
      expect(wrapped['number'].raw, equals(42));
      expect(wrapped['string'].raw, equals('test'));
      expect(wrapped['nested']['deep'].raw, equals(true));
    });

    test('unwrap nested structures', () {
      final value = Value({
        'number': Value(42),
        'string': Value('test'),
        'nested': Value({'deep': Value(true)}),
      });

      final unwrapped = value.unwrap();
      expect(unwrapped is Map, isTrue);
      expect(unwrapped['number'], equals(42));
      expect(unwrapped['string'], equals('test'));
      expect((unwrapped['nested'] as Map)['deep'], equals(toLuaValue(true)));
    });
  });

  group('Value Map Interface', () {
    test('map operations', () {
      final table = Value({});

      // Test basic operations
      table['key'] = 'value';
      expect(table['key'].raw, equals('value'));
      expect(table.containsKey('key'), isTrue);
      expect(table.containsValue(Value('value')), isTrue);

      // Test removal
      table.remove('key');
      expect(table.containsKey('key'), isFalse);

      // Test clear
      table['key1'] = 'value1';
      table['key2'] = 'value2';
      table.clear();
      expect(table.isEmpty, isTrue);

      // Test addAll
      table.addAll({'a': 1, 'b': 2});
      expect(table['a'].raw, equals(1));
      expect(table['b'].raw, equals(2));
    });

    test('map iteration', () {
      final table = Value({'a': Value(1), 'b': Value(2), 'c': Value(3)});

      // Test keys
      expect(table.keys.toList(), equals(['a', 'b', 'c']));

      // Test values
      final values = table.values.map((v) => (v as Value).unwrap()).toList();
      expect(values, equals([1, 2, 3]));

      // Test forEach
      num sum = 0;
      table.forEach((key, value) {
        sum = ((value + sum) as Value).raw as num;
      });
      expect(sum, equals(6));
    });
  });

  group('Value Error Handling', () {
    test('invalid table operations on non-table values', () {
      final nonTable = Value(42);
      expect(() => nonTable['key'], throwsUnsupportedError);
      expect(() => nonTable['key'] = 'value', throwsUnsupportedError);
      expect(() => nonTable.addAll({'key': 'value'}), throwsUnsupportedError);
    });
  });

  group('Value String Representation', () {
    test('toString for different types', () {
      expect(Value(42).toString(), equals('Value:<42>'));
      expect(Value("test").toString(), equals('Value:<test>'));
      expect(Value(true).toString(), equals('Value:<true>'));
      expect(Value(null).toString(), equals('Value:<nil>'));
    });

    test('toString for tables', () {
      final table = Value({'key': Value('value')});
      expect(table.toString(), contains('table:'));
    });

    test('toString handles recursive structures', () {
      final table = Value({});
      table['self'] = table;
      expect(table.toString(), contains('table:'));
    });
  });

  group('Value Operator Overloads', () {
    test('addition operator', () {
      final v1 = Value(10);
      final v2 = Value(5);
      expect((v1 + v2).raw, equals(15));
    });

    test('subtraction operator', () {
      final v1 = Value(10);
      final v2 = Value(5);
      expect((v1 - v2).raw, equals(5));
    });

    test('multiplication operator', () {
      final v1 = Value(10);
      final v2 = Value(5);
      expect((v1 * v2).raw, equals(50));
    });

    test('division operator', () {
      final v1 = Value(10);
      final v2 = Value(5);
      expect((v1 / v2).raw, equals(2));
    });

    test('negation operator', () {
      final v = Value(10);
      expect(-v, equals(Value(-10)));
    });

    test('bitwise NOT operator', () {
      final v = Value(10);
      expect((~v).raw, equals(~10));
    });
  });

  group('Value Attributes', () {
    test('const attribute prevents modification', () {
      final constValue = Value(42, isConst: true);
      expect(constValue.raw, equals(42));
      expect(constValue.isConst, isTrue);

      // Attempting to modify a const value should throw
      expect(() => constValue.raw = 100, throwsUnsupportedError);
    });

    test('const attribute is preserved when copying', () {
      final constValue = Value(42, isConst: true);
      final copy = constValue.copy();

      expect(copy.isConst, isTrue);
      expect(() => copy.raw = 100, throwsUnsupportedError);
    });

    test('to-be-closed attribute is set correctly', () {
      final value = Value(42, isToBeClose: true);
      expect(value.isToBeClose, isTrue);
    });

    test('to-be-closed attribute is preserved when copying', () {
      final value = Value(42, isToBeClose: true);
      final copy = value.copy();

      expect(copy.isToBeClose, isTrue);
    });

    test('close method calls __close metamethod', () {
      var closeCalled = false;
      final mt = {
        '__close': (args) {
          closeCalled = true;
          return Value(null);
        },
      };

      final value = Value(42, isToBeClose: true);
      value.setMetatable(mt);

      value.close();
      expect(closeCalled, isTrue);
    });

    test('close method with error passes error to __close metamethod', () {
      Object? capturedError;
      final mt = {
        '__close': (args) {
          capturedError = args[1];
          return Value(null);
        },
      };

      final value = Value(42, isToBeClose: true);
      value.setMetatable(mt);

      final error = Exception('Test error');
      value.close(error);
      expect(capturedError, isA<Value>());
      expect((capturedError as Value).raw, equals(error));
    });

    test('hasMetamethod correctly identifies __close', () {
      final value = Value(42);
      expect(value.hasMetamethod('__close'), isFalse);

      value.setMetatable({'__close': (args) => Value(null)});

      expect(value.hasMetamethod('__close'), isTrue);
    });

    test('multi-value attribute is set correctly', () {
      final value = Value.multi([1, 2, 3]);
      expect(value.isMulti, isTrue);
      expect(value.raw, equals([1, 2, 3]));
    });

    test('attributes can be combined', () {
      final mt = {'__close': (args) => Value(null)};

      final value = Value(42, isConst: true, isToBeClose: true, metatable: mt);

      expect(value.isConst, isTrue);
      expect(value.isToBeClose, isTrue);
      expect(value.hasMetamethod('__close'), isTrue);
    });
  });

  test('comparison operators', () {
    // Number comparisons
    expect((Value(10) > Value(5)).raw, isTrue);
    expect((Value(5) < Value(10)).raw, isTrue);
    expect((Value(10) >= Value(10)).raw, isTrue);
    expect((Value(10) <= Value(10)).raw, isTrue);

    // String comparisons
    expect((Value("b") > Value("a")).raw, isTrue);
    expect((Value("a") < Value("b")).raw, isTrue);
    expect((Value("b") >= Value("b")).raw, isTrue);
    expect((Value("b") <= Value("b")).raw, isTrue);

    // Different types should throw
    expect(() => Value(42) > Value("test"), throwsUnsupportedError);
    expect(() => Value("test") < Value(42), throwsUnsupportedError);
    expect(() => Value({}) >= Value(42), throwsUnsupportedError);
    expect(() => Value(42) <= Value({}), throwsUnsupportedError);
  });
}
