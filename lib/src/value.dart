import 'dart:math' as math;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/stdlib/lib_math.dart';
import 'package:lualike/src/stdlib/metatables.dart';
import 'package:lualike/src/upvalue.dart';

/// Represents an asynchronous function that can be called with a list of arguments.
typedef AsyncFunction = Future<Object?> Function(List<Object?> args);

/// Represents a value in the LuaLike runtime system.
///
/// Values can hold any Dart object and optionally have an associated metatable
/// that defines their behavior for various operations. Values that represent
/// tables implement the Map interface for easy interaction with Dart code.
class Value extends Object implements Map<String, dynamic>, GCObject {
  /// The underlying raw value being wrapped.
  dynamic _raw;

  /// Optional metatable defining the value's behavior for various operations.
  Map<String, dynamic>? metatable;

  /// References to captured upvalues if this value represents a function/closure.
  List<Upvalue>? upvalues;

  /// The AST node representing the function body, if this value is a Lua function.
  FunctionBody? functionBody;

  /// Whether this value is a multi-result value.
  bool isMulti = false;

  /// Whether this value is a constant (cannot be modified after initialization)
  bool isConst = false;

  /// Whether this value is a to-be-closed variable
  bool isToBeClose = false;

  /// Whether this value has been initialized (used for const variables)
  bool _isInitialized = false;

  /// Interpreter instance (for functions)
  Interpreter? interpreter;

  /// Whether this value is marked for garbage collection
  bool _marked = false;

  /// Whether this value is old (used for garbage collection)
  @override
  bool isOld = false;

  /// Get the raw value
  dynamic get raw => _raw;

  /// Set the raw value with attribute enforcement
  set raw(dynamic value) {
    if (isConst && _isInitialized) {
      throw UnsupportedError("attempt to assign to const variable");
    }
    _raw = value;
    _isInitialized = true;
  }

  /// Creates a new Value wrapping the given raw value.
  ///
  /// [raw] - The value to wrap
  /// [metatable] - Optional metatable to associate with the value. If not
  /// provided, a default metatable may be applied based on the value's type.
  /// [isConst] - Whether this value is a constant
  /// [isToBeClose] - Whether this value is a to-be-closed variable
  /// [interpreter] - Interpreter instance (for functions/coroutines)
  Value(
    dynamic raw, {
    Map<String, dynamic>? metatable,
    this.isConst = false,
    this.isToBeClose = false,
    this.upvalues,
    this.interpreter,
    this.functionBody,
  }) {
    _raw = raw;
    _isInitialized = true;

    // If no metatable was provided, apply default metatable
    if (metatable == null) {
      MetaTable().applyDefaultMetatable(this);
    } else {
      this.metatable = metatable;
    }
  }

  isA<T>() {
    return raw is T;
  }

  factory Value.multi(List<dynamic> values) {
    final value = Value(values);
    value.isMulti = true;
    return value;
  }

  /// Creates a constant value that cannot be modified after initialization
  factory Value.constant(dynamic value, {Map<String, dynamic>? metatable}) {
    return Value(value, metatable: metatable, isConst: true);
  }

  /// Creates a to-be-closed value that will have its __close metamethod called when it goes out of scope
  factory Value.toBeClose(dynamic value, {Map<String, dynamic>? metatable}) {
    if (value != null && value != false) {
      // Verify the value has a __close metamethod
      final tempValue = Value(value, metatable: metatable);
      if (!tempValue.hasMetamethod('__close')) {
        throw UnsupportedError(
          "to-be-closed variable value must have a __close metamethod",
        );
      }
    }
    return Value(value, metatable: metatable, isToBeClose: true);
  }

  /// Closes the value by calling its __close metamethod if it exists
  /// [error] - The error that caused the scope to exit, or null if normal exit
  void close([dynamic error]) {
    if (!isToBeClose || raw == null || raw == false) {
      return; // Only close to-be-closed variables with non-false values
    }

    final closeMeta = getMetamethod('__close');
    if (closeMeta != null) {
      try {
        if (closeMeta is Function) {
          closeMeta([this, error is Value ? error : Value(error)]);
        } else if (closeMeta is Value && closeMeta.raw is Function) {
          closeMeta.raw([this, error is Value ? error : Value(error)]);
        }
      } catch (e) {
        // Log the error but continue closing other variables
        print('Error in __close metamethod: $e');
        // Re-throw the error after closing
        rethrow;
      }
    }
  }

  /// Creates a deep copy of this Value and its metatable.
  ///
  /// For table values, recursively copies all nested values.
  /// Returns a new Value instance with copied contents.
  Value copy() {
    if (raw is Map) {
      // Deep copy for tables
      final newMap = <dynamic, dynamic>{};
      (raw as Map).forEach((key, value) {
        newMap[key] = value is Value ? value.copy() : Value(value).copy();
      });
      return Value(
        newMap,
        metatable: metatable != null ? Map.from(metatable!) : null,
        isConst: isConst,
        isToBeClose: isToBeClose,
      );
    }
    // For non-table values, copy with metatable
    return Value(
      raw,
      metatable: metatable != null ? Map.from(metatable!) : null,
      isConst: isConst,
      isToBeClose: isToBeClose,
    );
  }

  /// Gets the metatable associated with this value.
  ///
  /// Returns the metatable or null if none is set.
  Map<String, dynamic>? getMetatable() => metatable;

  /// Sets a new metatable for this value.
  ///
  /// [mt] - The new metatable to associate with this value.
  void setMetatable(Map<String, dynamic> mt) {
    metatable = mt;
  }

  /// Looks up a metamethod in this value's metatable.
  ///
  /// [event] - The name of the metamethod to look up (e.g. "__add")
  /// Returns the metamethod if found, null otherwise.
  dynamic getMetamethod(String event) {
    if (metatable != null) {
      return metatable![event];
    }
    return null;
  }

  /// Checks if the value has a metamethod associated with the given event.
  ///
  /// [event] - The name of the metamethod to check for.
  /// Returns `true` if the metamethod exists, `false` otherwise.
  hasMetamethod(String event) =>
      metatable != null && metatable!.containsKey(event);

  /// Checks if this value is callable (is a function or has __call metamethod)
  bool isCallable() {
    return raw is Function ||
        raw is FunctionDef ||
        raw is FunctionLiteral ||
        raw is FunctionBody ||
        hasMetamethod('__call');
  }

  /// Calls the value as a function with the given arguments.
  ///
  /// This method handles calling Dart functions, LuaLike functions (FunctionDef, FunctionBody),
  /// and functions that implement the '__call' metamethod.
  ///
  /// [args] - The arguments to pass to the function.
  /// Returns the result of the function call.
  /// Throws an [UnsupportedError] if the value is not callable.
  Future<Object?> invoke(List<Object?> args) async {
    if (raw is AsyncFunction) {
      // Call the asynchronous Dart function directly
      return await (raw as AsyncFunction)(args);
    } else if (raw is Function) {
      // Call synchronous Dart function
      return (raw as Function)(args);
    } else if (raw is FunctionDef) {
      // Call LuaLike function defined in AST
      final FunctionDef funcDef = raw as FunctionDef;
      final FunctionBody funcBody = funcDef.body;
      // Evaluate the function body
      final result = await funcBody.accept(
        Environment.current?.interpreter as AstVisitor<Object?>,
      );
      return result;
    } else if (raw is FunctionBody) {
      // Call LuaLike function body directly (closure)
      final FunctionBody funcBody = raw as FunctionBody;
      // Evaluate the function body
      final result = await funcBody.accept(
        Environment.current?.interpreter as AstVisitor<Object?>,
      );
      return result;
    } else if (raw is BuiltinFunction) {
      // Call BuiltinFunction
      return (raw as BuiltinFunction).call(args);
    } else if (hasMetamethod('__call')) {
      // Call __call metamethod
      final callMeta = getMetamethod('__call');
      if (callMeta is Value) {
        return await callMeta.invoke([this, ...args]);
      } else if (callMeta is Function) {
        return await callMeta([this, ...args]);
      }
    }
    throw UnsupportedError(
      'Attempt to call a non-function value: ${raw.runtimeType}',
    );
  }

  /// Converts a raw Dart value into a Value object.
  ///
  /// If the input is already a Value, returns it unchanged.
  /// For maps, recursively wraps all entries.
  ///
  /// [value] - The value to wrap
  /// Returns a new Value instance wrapping the input.
  static Value wrap(dynamic value) {
    if (value is Value) return value;
    if (value is Map) {
      // Create new table with copied entries
      final newMap = <dynamic, dynamic>{};
      value.forEach((key, val) {
        newMap[key] = wrap(val);
      });
      return Value(newMap, metatable: {});
    }
    return Value(value);
  }

  /// Unwraps a Value to get its raw value, recursively for tables
  dynamic unwrap() {
    if (raw is Map) {
      final unwrapped = <dynamic, dynamic>{};
      (raw as Map).forEach((key, value) {
        unwrapped[key] = value is Value ? value.completeUnwrap() : value;
      });
      return unwrapped;
    }
    return raw is Value ? raw.completeUnwrap() : raw;
  }

  completeUnwrap() {
    var current = raw;
    while (current is Value) {
      current = current.unwrap();
    }
    return current;
  }

  @override
  int get hashCode => raw.hashCode;

  @override
  bool operator ==(Object other) => equals(other);

  @override
  String toString() {
    final tostringMeta = getMetamethod('__tostring');
    if (tostringMeta != null) {
      final result = callMetamethod('__tostring', [this]);
      return result is Value ? result.raw.toString() : result.toString();
    }

    if (raw == null) return "Value:<nil>";
    if (raw is bool) return "Value:<$raw>";
    if (raw is num || raw is BigInt) return "Value:<$raw>";
    if (raw is String) return "Value:<$raw>";
    if (raw is List) return "Value:<list:${raw.hashCode}>";
    if (raw is Map) return "Value:<table:${raw.hashCode}>";
    if (raw is Function) return "Value:<function:${raw.hashCode}>";
    return "Value:<$raw>";
  }

  static const tableMetamethods = {
    '__index', // for reading from tables
    '__newindex', // for writing to tables
    '__len', // for length operation (#)
    '__pairs', // for pairs iteration
    '__ipairs', // for ipairs iteration
    '__add', // for addition (+)
    '__sub', // for subtraction (-)
    '__mul', // for multiplication (*)
    '__div', // for division (/)
    '__mod', // for modulo (%)
    '__pow', // for exponentiation (^)
    '__unm', // for negation (-)
    '__idiv', // for floor division (//)
    '__band', // for bitwise AND (&)
    '__bor', // for bitwise OR (|)
    '__bxor', // for bitwise XOR (~)
    '__bnot', // for bitwise NOT (~)
    '__shl', // for left shift (<<)
    '__shr', // for right shift (>>)
    '__concat', // for concatenation (..)
    '__eq', // for equality (==)
    '__lt', // for less than (<)
    '__le', // for less than or equal (<=)
    '__call', // for function calls
    '__tostring', // for string conversion
    '__gc', // for garbage collection
    '__close', // for to-be-closed variables
  };

  @override
  dynamic operator [](Object? key) {
    if (raw is Map && getMetamethod('__index') == null) {
      // If key is a Value, use its raw value, else key directly
      final rawKey = key is Value ? key.raw : key;
      var result = (raw as Map)[rawKey];
      // If the result is not already wrapped, wrap it
      if (result is! Value) result = Value(result);
      return result;
    } else {
      // Use metamethod __index if defined
      return callMetamethod('__index', [this, key is Value ? key : Value(key)]);
    }
  }

  @override
  void operator []=(Object key, dynamic value) {
    final rawKey = key is Value ? key.raw : key;
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      callMetamethod('__newindex', [
        this,
        key is Value ? key : Value(key),
        value is Value ? value : Value(value),
      ]);
      return;
    }
    // If no newindex metamethod is set and raw is a Map, perform direct assignment
    if (raw is Map) {
      (raw as Map)[rawKey] = value is Value ? value : Value(value);
      return;
    }
    throw UnsupportedError('Not a table');
  }

  @override
  void clear() {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      final keys = List.from((raw as Map).keys);
      for (final key in keys) {
        callMetamethod('__newindex', [this, Value(key), Value(null)]);
      }
      return;
    }

    (raw as Map).clear();
  }

  @override
  bool containsKey(Object? key) {
    if (raw is! Map) return false;

    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final result = callMetamethod('__index', [this, Value(key)]);
      return result != null && (result is Value ? result.raw != null : true);
    }

    return (raw as Map).containsKey(key);
  }

  @override
  bool containsValue(Object? value) =>
      entries.where((a) => a.value == value).isNotEmpty;

  @override
  void forEach(void Function(String key, Value value) action) {
    if (raw is! Map) throw UnsupportedError('Not a table');
    for (final entry in entries) {
      action(entry.key, entry.value as Value);
    }
  }

  @override
  bool get isEmpty {
    if (raw is! Map) return true;

    final lenMeta = getMetamethod('__len');
    if (lenMeta != null) {
      final result = callMetamethod('__len', [this]);
      return (result is Value ? result.raw : result) == 0;
    }

    return (raw as Map).isEmpty;
  }

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  int get length {
    final lenMeta = getMetamethod('__len');
    if (lenMeta != null) {
      final result = callMetamethod('__len', [this]);
      return result is Value ? result.raw as int : result as int;
    }

    return (raw as Map).length;
  }

  @override
  Map<K, V> cast<K, V>() {
    if (raw is! Map) return {};
    return (raw as Map).cast<K, V>();
  }

  @override
  void addAll(Map<String, dynamic> other) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      other.forEach((key, value) {
        callMetamethod('__newindex', [
          this,
          Value(key),
          value is Value ? value : Value(value),
        ]);
      });
      return;
    }

    other.forEach((key, value) {
      this[key] = value;
    });
  }

  @override
  dynamic putIfAbsent(String key, dynamic Function() ifAbsent) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final current = callMetamethod('__index', [this, Value(key)]);
      if (current != null && (current is Value ? current.raw != null : true)) {
        return current;
      }

      final value = ifAbsent();
      final wrappedValue = value is Value ? value : Value(value);
      callMetamethod('__newindex', [this, Value(key), wrappedValue]);
      return wrappedValue;
    }

    return (raw as Map).putIfAbsent(key, () {
      final value = ifAbsent();
      return value is Value ? value : Value(value);
    });
  }

  @override
  dynamic remove(Object? key) {
    if (raw is! Map) return null;

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      final oldValue = this[key];
      callMetamethod('__newindex', [this, Value(key), Value(null)]);
      return oldValue;
    }

    final value = (raw as Map).remove(key);
    return value is Value
        ? value
        : value != null
        ? Value(value)
        : null;
  }

  @override
  Iterable<String> get keys {
    return entries.map((e) => e.key);
  }

  @override
  Iterable<dynamic> get values => entries.map((e) => e.value);

  @override
  Iterable<MapEntry<String, dynamic>> get entries {
    if (raw is! Map) return [];

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      print('Using __pairs metamethod for entries');

      final entries = <MapEntry<String, dynamic>>[];
      final iter = callMetamethod('__pairs', [this]);

      if (iter is Value && iter.isMulti && iter.raw is List) {
        final iterFn = iter.raw[0] as Value;
        final state = iter.raw[1] as Value;
        var key = Value(null); // Initial key is nil for first iteration

        while (true) {
          // Call iterator function with state and previous key
          final List<dynamic> result;
          if (iterFn.raw is Function) {
            result = iterFn.raw([state, key]);
          } else {
            break;
          }

          // Check if we've reached the end of iteration
          if (result.isEmpty) {
            break;
          }

          final nextKey = result[0];
          if (nextKey == null || (nextKey is Value && nextKey.raw == null)) {
            break;
          }

          final nextVal = result.length > 1 ? result[1] : Value(null);

          // Convert key to string for MapEntry
          final keyStr = nextKey is Value
              ? nextKey.raw.toString()
              : nextKey.toString();

          // Make sure value is a Value
          final valueVal = nextVal is Value ? nextVal : Value(nextVal);

          entries.add(MapEntry(keyStr, valueVal));

          // Update key for next iteration
          key = nextKey is Value ? nextKey : Value(nextKey);
        }
      }

      return entries;
    }

    // Default implementation for normal maps
    return (raw as Map).entries.map(
      (e) => MapEntry(
        e.key.toString(),
        e.value is Value ? e.value : Value(e.value),
      ),
    );
  }

  @override
  Map<K, V> map<K, V>(
    MapEntry<K, V> Function(String key, dynamic value) convert,
  ) {
    if (raw is! Map) return {};

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      final entries = <MapEntry<K, V>>[];
      final iter = callMetamethod('__pairs', [this]);
      if (iter is Value && iter.isMulti) {
        final iterFn = iter.raw[0] as Value;
        final state = iter.raw[1] as Value;
        var key = iter.raw[2] as Value;

        while (true) {
          final result = (iterFn.raw as Function)([state, key]);
          if (result is List && result.isNotEmpty) {
            key = result[0] as Value;
            if (key.raw == null) break;
            final val = result[1] as Value;
            entries.add(convert(key.raw.toString(), val));
          } else {
            break;
          }
        }
      }
      return Map.fromEntries(entries);
    }

    return Map.fromEntries(
      (raw as Map).entries.map(
        (e) => convert(
          e.key.toString(),
          e.value is Value ? e.value : Value(e.value),
        ),
      ),
    );
  }

  Object? callMetamethod(String s, List<Value> list) {
    final method = getMetamethod(s);
    if (method == null) {
      throw UnsupportedError("attempt to call a nil value");
    }
    if (method is Function || (method is Value && method.raw is Function)) {
      return method is Value ? method.unwrap()(list) : method(list);
    } else {
      throw UnsupportedError(
        "attempt to call a non-function $s(${list.map((a) => a.unwrap()).join(', ')})",
      );
    }
  }

  @override
  void addEntries(Iterable<MapEntry<String, dynamic>> newEntries) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      for (final entry in newEntries) {
        callMetamethod('__newindex', [
          this,
          Value(entry.key),
          entry.value is Value ? entry.value : Value(entry.value),
        ]);
      }
      return;
    }

    (raw as Map).addEntries(
      newEntries.map(
        (e) => MapEntry(e.key, e.value is Value ? e.value : Value(e.value)),
      ),
    );
  }

  @override
  void removeWhere(bool Function(String key, dynamic value) test) {
    if (raw is! Map) return;

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      final iter = callMetamethod('__pairs', [this]);
      if (iter is! Value || !iter.isMulti) return;

      final iterFn = iter.raw[0] as Value;
      final state = iter.raw[1] as Value;
      var key = iter.raw[2] as Value;

      while (true) {
        final result = (iterFn.raw as Function)([state, key]);
        if (result is List && result.isNotEmpty) {
          key = result[0] as Value;
          if (key.raw == null) break;

          final val = result[1] as Value;
          if (test(key.raw.toString(), val)) {
            callMetamethod('__newindex', [this, key, Value(null)]);
          }
        } else {
          break;
        }
      }
      return;
    }

    (raw as Map).removeWhere(
      (k, v) => test(k.toString(), v is Value ? v : Value(v)),
    );
  }

  @override
  void updateAll(dynamic Function(String key, dynamic value) update) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final pairsMeta = getMetamethod('__pairs');
    if (pairsMeta != null) {
      final iter = callMetamethod('__pairs', [this]);
      if (iter is! Value || !iter.isMulti) return;

      final iterFn = iter.raw[0] as Value;
      final state = iter.raw[1] as Value;
      var key = iter.raw[2] as Value;

      while (true) {
        final result = (iterFn.raw as Function)([state, key]);
        if (result is List && result.isNotEmpty) {
          key = result[0] as Value;
          if (key.raw == null) break;

          final val = result[1] as Value;
          final updatedValue = update(key.raw.toString(), val);
          callMetamethod('__newindex', [this, key, updatedValue]);
        } else {
          break;
        }
      }
      return;
    }

    (raw as Map).updateAll((k, v) {
      final result = update(k.toString(), v is Value ? v : Value(v));
      return result is Value ? result : Value(result);
    });
  }

  @override
  dynamic update(
    String key,
    dynamic Function(dynamic value) update, {
    dynamic Function()? ifAbsent,
  }) {
    if (raw is! Map) throw UnsupportedError('Not a table');

    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final current = callMetamethod('__index', [this, Value(key)]);
      if (current != null && (current is Value ? current.raw != null : true)) {
        final updatedValue = update(current);
        callMetamethod('__newindex', [this, Value(key), updatedValue]);
        return updatedValue;
      }

      if (ifAbsent != null) {
        final value = ifAbsent();
        final wrappedValue = value is Value ? value : Value(value);
        callMetamethod('__newindex', [this, Value(key), wrappedValue]);
        return wrappedValue;
      }
      return null;
    }

    return (raw as Map).update(
      key,
      (value) {
        final result = update(value is Value ? value : Value(value));
        return result is Value ? result : Value(result);
      },
      ifAbsent: ifAbsent != null
          ? () {
              final result = ifAbsent();
              return result is Value ? result : Value(result);
            }
          : null,
    );
  }

  // Overload the call operator
  /// Calls this value if it's callable (continued)
  Future<Object?> call(List<Object?> args) async {
    if (raw is Function) {
      // Direct function call
      return raw(args);
    } else if (hasMetamethod('__call')) {
      // Use __call metamethod
      final callMethod = getMetamethod('__call');
      final callArgs = [this, ...args];

      if (callMethod is Function) {
        return await callMethod(callArgs);
      } else if (callMethod is Value && callMethod.raw is Function) {
        return await callMethod.raw(callArgs);
      }
    } else if (raw is FunctionDef ||
        raw is FunctionLiteral ||
        raw is FunctionBody) {
      // Get interpreter to evaluate the function
      final interpreter = Environment.current?.interpreter;
      if (interpreter != null) {
        return await interpreter.callFunction(this, args);
      }
    }

    throw Exception("attempt to call a non-function value");
  }

  @override
  List<Object?> getReferences() {
    final refs = <Object?>[];
    if (raw is Map) {
      refs.addAll((raw as Map).values);
      refs.addAll((raw as Map).keys);
    } else if (raw is Value) {
      refs.add(raw);
    }
    if (metatable != null) {
      refs.add(metatable);
    }
    return refs;
  }

  @override
  void free() {
    final finalizer = getMetamethod('__gc');
    if (finalizer != null) {
      try {
        callMetamethod('__gc', [this]);
      } catch (e) {
        print('Error in finalizer: $e');
      }
    }
  }

  @override
  bool get marked => _marked;

  @override
  set marked(bool value) => _marked = value;
}

extension OperatorExtension on Value {
  // Overload the bitwise XOR operator
  Value operator ^(dynamic other) => _arith('bxor', Value.wrap(other));

  // Overload the bitwise OR operator
  Value operator |(dynamic other) => _arith('|', Value.wrap(other));

  // Overload the bitwise AND operator
  Value operator &(dynamic other) => _arith('&', Value.wrap(other));

  // Logical OR method (Lua-style)
  Value or(dynamic other) {
    // In Lua, 'or' returns the first value if it's truthy, otherwise the second value
    if (raw != null && raw != false) {
      return this;
    }
    final wrappedOther = other is Value ? other : Value.wrap(other);
    return wrappedOther;
  }

  // Logical AND method (Lua-style)
  Value and(dynamic other) {
    // In Lua, 'and' returns the first value if it's falsy, otherwise the second value
    if (raw == null || raw == false) {
      return this;
    }
    final wrappedOther = other is Value ? other : Value.wrap(other);
    return wrappedOther;
  }

  // Add a helper for Lua's ~= (not equal) semantics
  bool notEquals(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN ~= anything is always true
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      print('COMPARE ~=: NaN detected, returning true');
      return true;
    }
    // Lua: int ~= float if float does not exactly represent int
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        print('COMPARE ~=: int ~= non-finite double, returning true');
        return true;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
      final doubleFromInt = intVal.toDouble();
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      print(
        'COMPARE ~=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
      );
      return !isExact;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!(raw).isFinite) {
        print(
          'COMPARE ~=: double ~= int, but double is not finite, returning true',
        );
        return true;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
      final doubleFromInt = intVal.toDouble();
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      print(
        'COMPARE ~=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
      );
      return !isExact;
    }
    if ((raw is BigInt && otherRaw is double) ||
        (raw is double && otherRaw is BigInt)) {
      // This case is now handled above
      // ...
    }
    return !(this == other);
  }

  Value _arith(String op, Value other) {
    var r1 = raw;
    var r2 = other.raw;

    final minInt64 = BigInt.from(MathLib.minInteger);
    final maxInt64 = BigInt.from(MathLib.maxInteger);
    print('ARITH: Lua 64-bit minInt64=$minInt64, maxInt64=$maxInt64');
    print(
      'ARITH: START op=$op, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
    );

    // Try to convert strings to numbers (Lua automatic conversion)
    if (r1 is String) {
      print('ARITH: r1 is String, parsing...');
      try {
        r1 = LuaNumberParser.parse(r1);
        print('ARITH: r1 parsed to $r1 (${r1.runtimeType})');
      } catch (e) {
        print('ARITH: r1 parse error: $e');
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    if (r2 is String) {
      print('ARITH: r2 is String, parsing...');
      try {
        r2 = LuaNumberParser.parse(r2);
        print('ARITH: r2 parsed to $r2 (${r2.runtimeType})');
      } catch (e) {
        print('ARITH: r2 parse error: $e');
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    print(
      'ARITH: after string parse, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
    );

    if (!((r1 is num || r1 is BigInt) && (r2 is num || r2 is BigInt))) {
      print('ARITH: type error, non-number values');
      throw LuaError.typeError(
        "attempt to perform arithmetic on non-number values",
      );
    }

    bool isZero(dynamic v) {
      if (v is int) return v == 0;
      if (v is BigInt) return v == BigInt.zero;
      if (v is double) return v == 0.0;
      return false;
    }

    BigInt toInt(dynamic v) {
      if (v is BigInt) return v;
      if (v is int) return BigInt.from(v);
      if (v is double) {
        if (!v.isFinite) {
          // Match Lua's error message for math.huge
          throw LuaError("number (field 'huge') has no integer representation");
        }
        if (v.floorToDouble() != v) {
          throw LuaError('number has no integer representation');
        }
        final bi = BigInt.parse(v.toStringAsFixed(0));
        if (bi < minInt64 || bi > maxInt64) {
          throw LuaError('number has no integer representation');
        }
        return bi;
      }
      throw LuaError.typeError('number has no integer representation');
    }

    if ((op == '//' || op == '%') &&
        isZero(r2) &&
        r1 is! double &&
        r2 is! double) {
      throw LuaError('divide by zero');
    }

    // After parsing and before operation, check for double promotion
    final isDoubleOp = r1 is double || r2 is double;
    print('ARITH: double promotion needed? $isDoubleOp');

    if (op == '^') {
      print(
        'ARITH: exponentiation, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      );
      final f1 = (r1 is BigInt)
          ? r1.toDouble()
          : (r1 is int ? r1.toDouble() : r1 as double);
      final f2 = (r2 is BigInt)
          ? r2.toDouble()
          : (r2 is int ? r2.toDouble() : r2 as double);
      final result = math.pow(f1, f2);
      print('ARITH: exponentiation result: $result (${result.runtimeType})');
      return Value(result);
    }
    if (op == '/') {
      print(
        'ARITH: division, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      );
      final f1 = (r1 is BigInt)
          ? r1.toDouble()
          : (r1 is int ? r1.toDouble() : r1 as double);
      final f2 = (r2 is BigInt)
          ? r2.toDouble()
          : (r2 is int ? r2.toDouble() : r2 as double);
      final result = f1 / f2;
      print('ARITH: division result: $result (${result.runtimeType})');
      return Value(result);
    }

    if (op == '<<' || op == '>>') {
      print(
        'ARITH: bitwise shift, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      );
      final b1 = toInt(r1);
      var shift = toInt(r2).toInt();
      var opToUse = op;

      // Handle negative shift amounts by reversing the operation
      if (shift < 0) {
        shift = -shift;
        opToUse = op == '<<' ? '>>' : '<<';
      }

      const intBits = 64;
      final mask = BigInt.parse('FFFFFFFFFFFFFFFF', radix: 16);
      BigInt result;
      if (opToUse == '<<') {
        result = (b1 << shift) & mask;
      } else {
        if (shift >= intBits) {
          result = b1.isNegative ? BigInt.from(-1) : BigInt.zero;
        } else {
          result = (b1 >> shift) & mask;
        }
      }
      print(
        'ARITH: bitwise shift intermediate result: $result (${result.runtimeType})',
      );
      if (result > maxInt64) {
        result -= BigInt.from(2).pow(64);
        print(
          'ARITH: bitwise shift wrapped to signed: $result (${result.runtimeType})',
        );
      }
      if (r1 is BigInt || r2 is BigInt) {
        print(
          'ARITH: bitwise shift operands included BigInt, returning BigInt result',
        );
        return Value(result);
      }
      if (result >= minInt64 && result <= maxInt64) {
        print(
          'ARITH: bitwise shift result fits in int64, returning int: ${result.toInt()}',
        );
        return Value(result.toInt());
      }
      print(
        'ARITH: bitwise shift result does not fit in int64, returning BigInt: $result',
      );
      return Value(result);
    }

    if (isDoubleOp) {
      // Promote both to double for arithmetic
      final d1 = (r1 is BigInt) ? r1.toDouble() : (r1 as num).toDouble();
      final d2 = (r2 is BigInt) ? r2.toDouble() : (r2 as num).toDouble();
      dynamic result;
      switch (op) {
        case '+':
          result = d1 + d2;
          break;
        case '-':
          result = d1 - d2;
          break;
        case '*':
          result = d1 * d2;
          break;
        case '~/':
          result = d1 ~/ d2;
          break;
        case '//':
          final div = d1 / d2;
          result = (div.isInfinite || div.isNaN) ? div : div.floorToDouble();
          break;
        case '%':
          var rem = d1.remainder(d2);
          if (rem != 0 && ((d1 < 0 && d2 > 0) || (d1 > 0 && d2 < 0))) {
            rem += d2;
          }
          result = rem;
          break;
        case '&':
          final bi1 = toInt(d1);
          final bi2 = toInt(d2);
          var biRes = bi1 & bi2;
          if (biRes >= minInt64 && biRes <= maxInt64) {
            result = biRes.toInt();
          } else {
            result = biRes;
          }
          break;
        case '|':
          final bi1 = toInt(d1);
          final bi2 = toInt(d2);
          var biRes = bi1 | bi2;
          if (biRes >= minInt64 && biRes <= maxInt64) {
            result = biRes.toInt();
          } else {
            result = biRes;
          }
          break;
        case 'bxor':
          final bi1 = toInt(d1);
          final bi2 = toInt(d2);
          var biRes = bi1 ^ bi2;
          if (biRes >= minInt64 && biRes <= maxInt64) {
            result = biRes.toInt();
          } else {
            result = biRes;
          }
          break;
        default:
          print('ARITH: unsupported op for double promotion: $op');
          throw LuaError.typeError(
            'operation "$op" not supported for double promotion',
          );
      }
      print('ARITH: double promotion result: $result (${result.runtimeType})');
      return Value(result);
    }

    if (r1 is BigInt || r2 is BigInt) {
      print(
        'ARITH: at least one operand is BigInt, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      );
      final b1 = toInt(r1);
      final b2 = toInt(r2);
      dynamic result;
      switch (op) {
        case '+':
          result = b1 + b2;
          break;
        case '-':
          result = b1 - b2;
          break;
        case '*':
          result = b1 * b2;
          break;
        case '~/':
          result = b1 ~/ b2;
          break;
        case '//':
          final div = b1.toDouble() / b2.toDouble();
          result = (div.isInfinite || div.isNaN) ? div : div.floorToDouble();
          break;
        case '%':
          var div = b1 ~/ b2;
          final differentSigns =
              (b1.isNegative && !b2.isNegative) ||
              (!b1.isNegative && b2.isNegative);
          if (differentSigns && b1 % b2 != BigInt.zero) {
            div -= BigInt.one;
          }
          result = b1 - div * b2;
          break;
        case '&':
          result = b1 & b2;
          break;
        case '|':
          result = b1 | b2;
          break;
        case 'bxor':
          result = b1 ^ b2;
          break;
        default:
          print('ARITH: unsupported op for BigInt: $op');
          throw LuaError.typeError('operation "$op" not supported for BigInt');
      }
      print('ARITH: BigInt result: $result (${result.runtimeType})');
      if (result is BigInt) {
        return Value(result);
      }
      print('ARITH: BigInt result is not BigInt, returning as is');
      return Value(result);
    }

    if (r1 is num && r2 is num) {
      print(
        'ARITH: both operands are num, r1=$r1 (${r1.runtimeType}), r2=$r2 (${r2.runtimeType})',
      );
      dynamic result;
      switch (op) {
        case '+':
          result = r1 + r2;
          break;
        case '-':
          result = r1 - r2;
          break;
        case '*':
          result = r1 * r2;
          break;
        case '~/':
          result = r1 ~/ r2;
          break;
        case '//':
          if (r1 is int && r2 is int) {
            final quotient = r1 ~/ r2;
            final remainder = r1 % r2;
            if (remainder != 0 && (r1 < 0) != (r2 < 0)) {
              result = quotient - 1;
            } else {
              result = quotient;
            }
          } else {
            final div = r1 / r2;
            result = (div.isInfinite || div.isNaN) ? div : div.floorToDouble();
          }
          break;
        case '%':
          if (r1 is int && r2 is int) {
            var div = r1 ~/ r2;
            if ((r1 < 0) != (r2 < 0) && r1 % r2 != 0) {
              div -= 1;
            }
            result = r1 - div * r2;
          } else {
            final div = (r1 / r2).floor();
            result = r1 - div * r2;
          }
          break;
        case '&':
          final bi1 = toInt(r1);
          final bi2 = toInt(r2);
          var biRes = bi1 & bi2;
          if (r1 is int &&
              r2 is int &&
              biRes >= minInt64 &&
              biRes <= maxInt64) {
            result = biRes.toInt();
          } else {
            result = biRes;
          }
          break;
        case '|':
          final bi1 = toInt(r1);
          final bi2 = toInt(r2);
          var biRes = bi1 | bi2;
          if (r1 is int &&
              r2 is int &&
              biRes >= minInt64 &&
              biRes <= maxInt64) {
            result = biRes.toInt();
          } else {
            result = biRes;
          }
          break;
        case 'bxor':
          final bi1 = toInt(r1);
          final bi2 = toInt(r2);
          var biRes = bi1 ^ bi2;
          if (r1 is int &&
              r2 is int &&
              biRes >= minInt64 &&
              biRes <= maxInt64) {
            result = biRes.toInt();
          } else {
            result = biRes;
          }
          break;
        default:
          print('ARITH: unsupported op for num: $op');
          throw LuaError.typeError('operation "$op" not supported for num');
      }
      print('ARITH: num result: $result (${result.runtimeType})');
      return Value(result);
    }

    print('ARITH: type error, operation not supported for these types');
    throw LuaError.typeError('operation "$op" not supported for these types');
  }

  /// Overload the addition operator
  Value operator +(dynamic other) => _arith('+', Value.wrap(other));

  // Overload the subtraction operator
  Value operator -(dynamic other) => _arith('-', Value.wrap(other));

  // Overload the multiplication operator
  Value operator *(dynamic other) => _arith('*', Value.wrap(other));

  // Overload the division operator
  Value operator /(dynamic other) => _arith('/', Value.wrap(other));

  // Overload the bitwise NOT operator
  Value operator ~() {
    var r = raw;

    // Try to convert strings to numbers (Lua automatic conversion)
    if (r is String) {
      try {
        r = LuaNumberParser.parse(r);
      } catch (e) {
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    if (r is int) return Value(~r);
    if (r is BigInt) return Value(~r);
    if (r is double) {
      if (!r.isFinite || r.floorToDouble() != r) {
        throw LuaError('number has no integer representation');
      }
      return Value(~r.toInt());
    }

    throw LuaError.typeError(
      'Bitwise NOT not supported for these types ${raw.runtimeType}',
    );
  }

  // Overload the left shift operator
  Value operator <<(dynamic other) => _arith('<<', Value.wrap(other));

  // Overload the right shift operator
  Value operator >>(dynamic other) => _arith('>>', Value.wrap(other));

  // Overload the modulo operator
  Value operator %(dynamic other) => _arith('%', Value.wrap(other));

  // Overload the floor division operator
  Value operator ~/(dynamic other) => _arith('//', Value.wrap(other));

  // Overload the exponentiation operator
  Value exp(dynamic other) => _arith('^', Value.wrap(other));

  // Overload the negation operator
  Value operator -() {
    var r = raw;

    // Try to convert strings to numbers (Lua automatic conversion)
    if (r is String) {
      try {
        r = LuaNumberParser.parse(r);
      } catch (e) {
        throw LuaError.typeError(
          "attempt to perform arithmetic on a string value",
        );
      }
    }

    if (r is BigInt) return Value(-r);
    if (r is num) return Value(-r);

    throw UnsupportedError(
      'Negation not supported for type ${raw.runtimeType}',
    );
  }

  // Overload the concatenation operator
  Value concat(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is String) {
      if (wrappedOther.raw is String) {
        return Value(raw + wrappedOther.raw);
      } else if (wrappedOther is num) {
        return Value(raw + wrappedOther.toString());
      }

      return Value(raw + wrappedOther.raw);
    }

    if (raw is num) {
      if (wrappedOther.raw is String) {
        return Value(raw.toString() + wrappedOther.raw);
      } else if (wrappedOther is num) {
        return Value(raw.toString() + wrappedOther.toString());
      }
      return Value(raw.toString() + wrappedOther.raw.toString());
    }

    if (raw == null || other == null) {
      throw LuaError.typeError('Attempt to concatenate a nil value');
    }

    throw LuaError.typeError(
      'Concatenation not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  operator >(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN > anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      print('COMPARE >: NaN detected, returning false');
      return false;
    }
    // Always use mathematical ordering for int/BigInt vs double
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int/BigInt vs infinity: int > +inf is false, int > -inf is true
          return otherRaw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE >: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        BigInt intFromDouble;
        try {
          intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        } on FormatException {
          return false;
        }
        return intVal > intFromDouble;
      }
      return doubleFromInt > doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // infinity vs int/BigInt: +inf > int is true, -inf > int is false
          return !raw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE >: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        BigInt intFromDouble;
        try {
          intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        } on FormatException {
          return false;
        }
        return intFromDouble > intVal;
      }
      return doubleVal > doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw > otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw > otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw > BigInt.from(otherRaw);
      return raw.toDouble() > otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) > otherRaw;
      return raw > otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) > 0;
    }
    throw UnsupportedError(
      'Greater than not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  operator <(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN < anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      print('COMPARE <: NaN detected, returning false');
      return false;
    }
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int/BigInt vs infinity: int < +inf is true, int < -inf is false
          return !otherRaw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE <: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        return intVal < intFromDouble;
      }
      return doubleFromInt < doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // infinity vs int/BigInt: +inf < int is false, -inf < int is true
          return raw.isNegative;
        }
        // For NaN, return false (already handled above)
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE <: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        return intFromDouble < intVal;
      }
      return doubleVal < doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw < otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw < otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw < BigInt.from(otherRaw);
      return raw.toDouble() < otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) < otherRaw;
      return raw < otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) < 0;
    }
    throw UnsupportedError(
      'Less than not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  operator >=(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN >= anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      print('COMPARE >=: NaN detected, returning false');
      return false;
    }
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int >= +inf is false, int >= -inf is true
          return otherRaw.isNegative;
        }
        return false; // NaN
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE >=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        return intVal >= intFromDouble;
      }
      return doubleFromInt >= doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // +inf >= int is true, -inf >= int is false
          return !raw.isNegative;
        }
        return false; // NaN
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE >=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        return intFromDouble >= intVal;
      }
      return doubleVal >= doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw >= otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw >= otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw >= BigInt.from(otherRaw);
      return raw.toDouble() >= otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) >= otherRaw;
      return raw >= otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) >= 0;
    }
    throw UnsupportedError(
      'Greater than or equal not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  operator <=(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN <= anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      print('COMPARE <=: NaN detected, returning false');
      return false;
    }
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        if (otherRaw.isInfinite) {
          // int <= +inf is true, int <= -inf is false
          return !otherRaw.isNegative;
        }
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE <=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        return intVal <= intFromDouble;
      }
      return doubleFromInt <= doubleVal;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        if (raw.isInfinite) {
          // +inf <= int is false, -inf <= int is true
          return raw.isNegative;
        }
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      print(
        'COMPARE <=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
      );
      if (doubleFromInt == doubleVal) {
        final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
        return intFromDouble <= intVal;
      }
      return doubleVal <= doubleFromInt;
    }
    if (raw is num && otherRaw is num) return raw <= otherRaw;
    if (raw is BigInt && otherRaw is BigInt) return raw <= otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw <= BigInt.from(otherRaw);
      return raw.toDouble() <= otherRaw;
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) <= otherRaw;
      return raw <= otherRaw.toDouble();
    }
    if (raw is String && otherRaw is String) {
      return raw.compareTo(otherRaw) <= 0;
    }
    throw UnsupportedError(
      'Less than or equal not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  bool equals(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN == anything is always false
    if ((raw is num && raw.isNaN) || (otherRaw is num && otherRaw.isNaN)) {
      print('COMPARE ==: NaN detected, returning false');
      return false;
    }
    // Lua: int == float only if float is finite and exactly represents int
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        print('COMPARE ==: int == non-finite double, returning false');
        return false;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      BigInt intFromDouble;
      try {
        // Handle very large numbers that toStringAsFixed might return in scientific notation
        final stringVal = doubleVal.toStringAsFixed(0);
        if (stringVal.contains('e') || stringVal.contains('E')) {
          // Use LuaNumberParser for scientific notation
          final parsed = LuaNumberParser.parse(stringVal);
          if (parsed is double) {
            return false; // If it's not an exact integer, they're not equal
          }
          intFromDouble = parsed is BigInt ? parsed : BigInt.from(parsed);
        } else {
          intFromDouble = BigInt.parse(stringVal);
        }
      } catch (e) {
        return false; // If we can't parse it as an integer, they're not equal
      }
      final doubleFromInt = intVal.toDouble();
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      print(
        'COMPARE ==: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
      );
      return isExact;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        print(
          'COMPARE ==: double == int, but double is not finite, returning false',
        );
        return false;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      BigInt intFromDouble;
      try {
        // Handle very large numbers that toStringAsFixed might return in scientific notation
        final stringVal = doubleVal.toStringAsFixed(0);
        if (stringVal.contains('e') || stringVal.contains('E')) {
          // Use LuaNumberParser for scientific notation
          final parsed = LuaNumberParser.parse(stringVal);
          if (parsed is double) {
            return false; // If it's not an exact integer, they're not equal
          }
          intFromDouble = parsed is BigInt ? parsed : BigInt.from(parsed);
        } else {
          intFromDouble = BigInt.parse(stringVal);
        }
      } catch (e) {
        return false; // If we can't parse it as an integer, they're not equal
      }
      final doubleFromInt = intVal.toDouble();
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      print(
        'COMPARE ==: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
      );
      return isExact;
    }
    if ((raw is BigInt && otherRaw is double) ||
        (raw is double && otherRaw is BigInt)) {
      final d1 = raw is BigInt ? raw.toDouble() : raw;
      final d2 = otherRaw is BigInt ? otherRaw.toDouble() : otherRaw;
      print('COMPARE ==: promoting BigInt to double: $d1 == $d2');
      return d1 == d2;
    }

    if (identical(this, other)) return true;
    if (raw is BigInt && otherRaw is BigInt) return raw == otherRaw;
    if (raw is BigInt && otherRaw is num) {
      if (otherRaw is int) return raw == BigInt.from(otherRaw);
      return otherRaw.isFinite &&
          raw.toDouble() == otherRaw &&
          raw == BigInt.from(otherRaw);
    }
    if (raw is num && otherRaw is BigInt) {
      if (raw is int) return BigInt.from(raw) == otherRaw;
      return raw.isFinite &&
          raw == otherRaw.toDouble() &&
          BigInt.from(raw) == otherRaw;
    }

    if (raw is Map && otherRaw is Map) {
      final map1 = raw as Map;
      final map2 = otherRaw;
      if (map1.length != map2.length) return false;
      if (map1.isEmpty && map2.isEmpty) return true;
      return map1.entries.every((e) {
        if (!map2.containsKey(e.key)) return false;
        final v1 = e.value is Value ? e.value : Value(e.value);
        final v2 = map2[e.key] is Value ? map2[e.key] : Value(map2[e.key]);
        return v1 == v2;
      });
    }
    return raw == otherRaw;
  }
}
