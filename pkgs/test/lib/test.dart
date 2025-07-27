/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

import 'package:meta/meta.dart';
import 'package:lualike/lualike.dart';
export 'package:lualike/lualike.dart';
import 'package:test/test.dart';
export 'package:test/test.dart';

@visibleForTesting
/// A fluent API for testing LuaLike execution results.
class BridgeAssert {
  final LuaLike _bridge;

  /// Creates a new BridgeAssert for the given bridge.
  const BridgeAssert(this._bridge);

  /// Factory method to create a BridgeAssert instance.
  static BridgeAssert from(LuaLike bridge) => BridgeAssert(bridge);

  /// Asserts that a global variable exists and has the expected value.
  BridgeAssert global(String name, Object? expected) {
    final value = _bridge.getGlobal(name);
    final expectedValue = expected is Value ? expected : toLuaValue(expected);
    expect(
      value,
      equals(expectedValue),
      reason:
          'Global $name with the value $value does not have the expected value $expectedValue',
    );
    return this;
  }

  /// Asserts that a local variable exists and has the expected value.
  BridgeAssert local(String name, Object? expected) {
    // First make sure the local is exposed as a global for testing
    _bridge.execute('_test_value = $name');
    final value = _bridge.getGlobal('_test_value');
    if (expected is Value) {
      expect(value, equals(expected));
    } else {
      expect((value as Value).raw, equals(expected));
    }
    // Clean up
    _bridge.execute('_test_value = nil');
    return this;
  }

  /// Asserts that a table field has the expected value.
  BridgeAssert tableField(
    String tableName,
    String fieldName,
    Object? expected,
  ) {
    // Get the table field
    _bridge.execute('_test_value = $tableName.$fieldName');
    final value = _bridge.getGlobal('_test_value');
    if (expected is Value) {
      expect(value, equals(expected));
    } else {
      expect((value as Value).raw, equals(expected));
    }
    // Clean up
    _bridge.execute('_test_value = nil');
    return this;
  }

  /// Asserts that a table indexed value has the expected value.
  BridgeAssert tableIndex(String tableName, Object index, Object? expected) {
    // Get the table indexed value
    final indexStr = index is String ? '"$index"' : index;
    _bridge.execute('_test_value = $tableName[$indexStr]');
    final value = _bridge.getGlobal('_test_value');
    if (expected is Value) {
      expect(value, equals(expected));
    } else {
      expect((value as Value).raw, equals(expected));
    }
    // Clean up
    _bridge.execute('_test_value = nil');
    return this;
  }

  /// Runs code and asserts that the result of the last expression matches the expected value.
  Future<BridgeAssert> runs(String code, Object? expected) async {
    // Wrap in return statement if not already present
    if (!code.trim().startsWith('return ')) {
      code = 'return $code';
    }
    dynamic actual;
    expected = toLuaValue(expected);

    try {
      actual = await _bridge.execute(code);
    } on ReturnException catch (e) {
      actual = e.value;
    } finally {
      if (expected is Value) {
        expect(fromLuaValue(expected), equals(fromLuaValue(expected)));
      } else {
        expect((actual as Value).raw, equals((expected as Value).value.raw));
      }
    }

    return this;
  }

  /// Asserts that running the code throws an error.
  Future<BridgeAssert> throws(String code, {String? containing}) async {
    try {
      await _bridge.execute(code);
      fail('Expected code to throw an error but it succeeded.');
    } catch (e) {
      if (containing != null) {
        expect(e.toString(), contains(containing));
      }
    }
    return this;
  }

  /// Executes code without assertions, useful for setup steps.
  Future<BridgeAssert> setup(String code) async {
    await _bridge.execute(code);
    return this;
  }
}

/// Extension method on LuaLike to easily create a BridgeAssert.
extension BridgeAssertExtension on LuaLike {
  BridgeAssert get asserts => BridgeAssert(this);
}

/// Extension methods for creating Value objects for testing.
extension ValueExtensions on Object? {
  Value toValue() => Value(this);
}
