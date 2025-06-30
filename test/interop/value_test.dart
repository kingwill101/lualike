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
      dynamic sum = 0;
      table.forEach((key, value) {
        sum = (value + sum).raw;
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

  group('Number Edge Cases', () {
    test('NaN equality', () {
      final nan1 = Value(double.nan);
      final nan2 = Value(double.nan);
      expect(nan1 == nan2, isFalse, reason: 'NaN should not be equal to NaN');
    });

    test('NaN inequality', () {
      final nan1 = Value(double.nan);
      final nan2 = Value(double.nan);
      expect(nan1 != nan2, isTrue, reason: 'NaN should be not-equal to NaN');
    });

    test('NaN comparisons', () {
      final nan = Value(double.nan);
      final v = Value(1.0);
      expect(nan > v, isFalse, reason: 'NaN > x should be false');
      expect(nan < v, isFalse, reason: 'NaN < x should be false');
      expect(nan >= v, isFalse, reason: 'NaN >= x should be false');
      expect(nan <= v, isFalse, reason: 'NaN <= x should be false');
      expect(v > nan, isFalse, reason: 'x > NaN should be false');
      expect(v < nan, isFalse, reason: 'x < NaN should be false');
      expect(v >= nan, isFalse, reason: 'x >= NaN should be false');
      expect(v <= nan, isFalse, reason: 'x <= NaN should be false');
    });

    test('Infinity equality', () {
      final pInf1 = Value(double.infinity);
      final pInf2 = Value(double.infinity);
      final nInf1 = Value(double.negativeInfinity);
      final nInf2 = Value(double.negativeInfinity);
      expect(pInf1 == pInf2, isTrue);
      expect(nInf1 == nInf2, isTrue);
      expect(pInf1 == nInf1, isFalse);
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
    expect((Value(10) > Value(5)), isTrue);
    expect((Value(5) < Value(10)), isTrue);
    expect((Value(10) >= Value(10)), isTrue);
    expect((Value(10) <= Value(10)), isTrue);

    // String comparisons
    expect((Value("b") > Value("a")), isTrue);
    expect((Value("a") < Value("b")), isTrue);
    expect((Value("b") >= Value("b")), isTrue);
    expect((Value("b") <= Value("b")), isTrue);

    // Different types should throw
    expect(() => Value(42) > Value("test"), throwsUnsupportedError);
    expect(() => Value("test") < Value(42), throwsUnsupportedError);
    expect(() => Value({}) >= Value(42), throwsUnsupportedError);
    expect(() => Value(42) <= Value({}), throwsUnsupportedError);
  });

  group('Number Operator Tests (migrated)', () {
    final vInt = Value(10);
    final vDouble = Value(10.5);
    final vBigInt = Value(BigInt.from(9223372036854775807));
    final vNan = Value(double.nan);
    final vInfinity = Value(double.infinity);

    group('Arithmetic Operators', () {
      test('Addition (+)', () {
        expect((vInt + Value(5)).raw, 15);
        expect((vDouble + Value(5.5)).raw, 16.0);
        expect(
          (vBigInt + Value(BigInt.one)).raw,
          BigInt.parse('9223372036854775808'),
        );
      });
      test('Subtraction (-)', () {
        expect((vInt - Value(5)).raw, 5);
        expect((vDouble - Value(5.5)).raw, 5.0);
        expect(
          (vBigInt - Value(BigInt.one)).raw,
          BigInt.from(9223372036854775806),
        );
      });
      test('Multiplication (*)', () {
        expect((vInt * Value(5)).raw, 50);
        expect((vDouble * Value(2)).raw, 21.0);
      });
      test('Division (/)', () {
        expect((vInt / Value(2)).raw, 5.0);
        expect((vDouble / Value(2)).raw, 5.25);
      });
      test('Floor Division (~/)', () {
        expect((vInt ~/ Value(3)).raw, 3);
        expect((Value(10.8) ~/ Value(3)).raw, 3.0);
      });
      test('Modulo (%)', () {
        expect((vInt % Value(3)).raw, 1);
        expect((vDouble % Value(3)).raw, 1.5);
      });
      test('Exponentiation (^)', () {
        expect((Value(2).exp(Value(3))).raw, 8.0);
        expect((Value(4.0).exp(Value(0.5))).raw, 2.0);
      });
      test('Negation (-)', () {
        expect((-vInt).raw, -10);
        expect((-vDouble).raw, -10.5);
      });
    });

    group('Bitwise Operators', () {
      final vBitInt = Value(0xF0);
      final vBitBig = Value(BigInt.parse('11110000', radix: 2));
      test('Bitwise AND (&)', () {
        expect((vBitInt & Value(0x0F)).raw, 0);
        expect(
          (vBitBig & Value(BigInt.parse('00001111', radix: 2))).raw,
          BigInt.zero,
        );
      });
      test('Bitwise OR (|)', () {
        expect((vBitInt | Value(0x0F)).raw, 0xFF);
        expect(
          (vBitBig | Value(BigInt.parse('00001111', radix: 2))).raw,
          BigInt.parse('11111111', radix: 2),
        );
      });
      test('Bitwise XOR (^)', () {
        expect((vBitInt ^ Value(0xFF)).raw, 0x0F);
        expect(
          (vBitBig ^ Value(BigInt.parse('11111111', radix: 2))).raw,
          BigInt.parse('00001111', radix: 2),
        );
      });
      test('Bitwise NOT (~)', () {
        expect((~vBitInt).raw, ~0xF0);
        expect((~vBitBig).raw, ~BigInt.parse('11110000', radix: 2));
      });
      test('Left Shift (<<)', () {
        expect((vBitInt << Value(4)).raw, 0xF00);
        expect(
          (vBitBig << Value(4)).raw,
          BigInt.parse('111100000000', radix: 2),
        );
      });
      test('Right Shift (>>)', () {
        expect((vBitInt >> Value(4)).raw, 0x0F);
        expect((vBitBig >> Value(4)).raw, BigInt.parse('1111', radix: 2));
      });
    });

    group('Comparison Operators', () {
      test('Equality (==)', () {
        expect(vInt == Value(10), isTrue);
        expect(vDouble == Value(10.5), isTrue);
        expect(vInt == vDouble, isFalse);
        expect(vNan == vNan, isFalse); // NaN should never equal itself
        expect(vInfinity == Value(double.infinity), isTrue);
        expect(vInfinity == Value(double.negativeInfinity), isFalse);
      });
      test('Inequality (!=)', () {
        expect(vInt != Value(11), isTrue);
        expect(vNan != vNan, isTrue); // NaN should always be != to itself
      });
      test('Less Than (<)', () {
        expect(vInt < Value(11), isTrue);
        expect(vInt < Value(10), isFalse);
        expect(vNan < vInt, isFalse);
      });
      test('Greater Than (>)', () {
        expect(vInt > Value(9), isTrue);
        expect(vInt > Value(10), isFalse);
        expect(vNan > vInt, isFalse);
      });
      test('Less Than or Equal (<=)', () {
        expect(vInt <= Value(10), isTrue);
        expect(vInt <= Value(9), isFalse);
        expect(vNan <= vInt, isFalse);
      });
      test('Greater Than or Equal (>=)', () {
        expect(vInt >= Value(10), isTrue);
        expect(vInt >= Value(11), isFalse);
        expect(vNan >= vInt, isFalse);
      });
    });
  });

  group('Large Integer and Float Edge Cases', () {
    final minint = -9223372036854775808;
    final maxint = 9223372036854775807;
    test('minint * -1.0 == 9223372036854775808.0', () {
      final result = Value(minint) * Value(-1.0);
      expect(result.raw, equals(9223372036854775808.0));
    });
    test('maxint < minint * -1.0', () {
      final left = Value(maxint);
      final right = Value(minint) * Value(-1.0);
      expect(left < right, isTrue);
    });
    test('maxint <= minint * -1.0', () {
      final left = Value(maxint);
      final right = Value(minint) * Value(-1.0);
      expect(left <= right, isTrue);
    });
    test('minint * -1.0 > maxint', () {
      final left = Value(minint) * Value(-1.0);
      final right = Value(maxint);
      expect(left > right, isTrue);
    });
    test('minint * -1.0 >= maxint', () {
      final left = Value(minint) * Value(-1.0);
      final right = Value(maxint);
      expect(left >= right, isTrue);
    });
    test('maxint < 9223372036854775808.0', () {
      final left = Value(maxint);
      final right = Value(9223372036854775808.0);
      expect(left < right, isTrue);
    });
    test('maxint <= 9223372036854775808.0', () {
      final left = Value(maxint);
      final right = Value(9223372036854775808.0);
      expect(left <= right, isTrue);
    });
  });
}
