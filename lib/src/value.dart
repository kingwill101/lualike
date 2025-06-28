import 'dart:math' as math;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
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

  /// Interpreter instance (for functions/coroutines)
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
        Logger.debug('Error in __close metamethod: $e', category: 'Value');
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
    // Save current interpreter state
    final Interpreter? currentInterpreter = interpreter;
    Environment? previousEnv;
    Coroutine? previousCoroutine;

    if (currentInterpreter != null) {
      previousEnv = currentInterpreter.getCurrentEnv();
      previousCoroutine = currentInterpreter.getCurrentCoroutine();
    }

    try {
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

        // Set interpreter environment to the function's closure environment for execution
        if (currentInterpreter != null) {
          // currentInterpreter.setCurrentEnv(funcBody.environment!); // Removed as environment is handled by closure
        }

        // Evaluate the function body
        final result = await funcBody.accept(currentInterpreter!);

        // Restore interpreter environment
        if (currentInterpreter != null && previousEnv != null) {
          // currentInterpreter.setCurrentEnv(previousEnv); // Removed as environment is handled by closure
        }
        return result;
      } else if (raw is FunctionBody) {
        // Call LuaLike function body directly (closure)
        final FunctionBody funcBody = raw as FunctionBody;

        // Set interpreter environment to the function's closure environment for execution
        if (currentInterpreter != null) {
          // currentInterpreter.setCurrentEnv(funcBody.environment!); // Removed as environment is handled by closure
        }

        // Evaluate the function body
        final result = await funcBody.accept(currentInterpreter!);

        // Restore interpreter environment
        if (currentInterpreter != null && previousEnv != null) {
          // currentInterpreter.setCurrentEnv(previousEnv); // Removed as environment is handled by closure
        }
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
    } finally {
      // Always restore original environment and coroutine if changed
      if (currentInterpreter != null) {
        if (previousEnv != null) {
          // currentInterpreter.setCurrentEnv(previousEnv); // Removed as environment is handled by closure
        }
        if (previousCoroutine != null) {
          // currentInterpreter.setCurrentCoroutine(previousCoroutine); // Removed as coroutine is handled by closure
        }
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
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Value) {
      if (raw.runtimeType == other.runtimeType) {
        return raw == other;
      }
      return false;
    }

    if (raw is Map && other.raw is Map) {
      final map1 = raw as Map;
      final map2 = other.raw as Map;
      if (map1.length != map2.length) return false;
      if (map1.isEmpty && map2.isEmpty) return true; // Handle empty maps
      return map1.entries.every((e) {
        if (!map2.containsKey(e.key)) return false;
        final v1 = e.value is Value ? e.value : Value(e.value);
        final v2 = map2[e.key] is Value ? map2[e.key] : Value(map2[e.key]);
        return v1 == v2;
      });
    }
    return raw == other.raw;
  }

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() {
    final tostringMeta = getMetamethod('__tostring');
    if (tostringMeta != null) {
      final result = callMetamethod('__tostring', [this]);
      return result is Value ? result.raw.toString() : result.toString();
    }

    if (raw == null) return "Value:<nil>";
    if (raw is bool) return "Value:<$raw>";
    if (raw is num) return "Value:<$raw>";
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
    Logger.debug(
      'Attempting to set key $key with value $value',
      category: 'Value',
    );

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
      (raw as Map)[key] = value is Value ? value : Value(value);
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
  void forEach(void Function(String key, dynamic value) action) {
    if (raw is! Map) throw UnsupportedError('Not a table');
    for (final entry in entries) {
      action(entry.key, entry.value);
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
      Logger.debug('Using __pairs metamethod for entries', category: 'Value');

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
          final keyStr =
              nextKey is Value ? nextKey.raw.toString() : nextKey.toString();

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
      ifAbsent:
          ifAbsent != null
              ? () {
                final result = ifAbsent();
                return result is Value ? result : Value(result);
              }
              : null,
    );
  }

  /// Overload the addition operator
  Value operator +(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      return Value(raw + wrappedOther.raw);
    }

    throw UnsupportedError(
      "Addition not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  // Overload the subtraction operator
  Value operator -(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      return Value(raw - wrappedOther.raw);
    }

    throw UnsupportedError(
      "Subtraction not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  // Overload the multiplication operator
  Value operator *(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      return Value(raw * wrappedOther.raw);
    }

    throw UnsupportedError(
      "Multiplication not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  // Overload the division operator
  Value operator /(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      return Value(raw / wrappedOther.raw);
    }

    throw UnsupportedError(
      "Division not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  // Overload the bitwise NOT operator
  Value operator ~() {
    // Only perform direct operation on raw values
    if (raw is int) {
      return Value(~raw);
    }

    throw UnsupportedError(
      'Bitwise NOT not supported for these types ${raw.runtimeType}',
    );
  }

  // Overload the left shift operator
  Value operator <<(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is int && wrappedOther.raw is int) {
      return Value(raw << wrappedOther.raw);
    }

    throw UnsupportedError(
      'Left shift not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  // Overload the right shift operator
  Value operator >>(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is int && wrappedOther.raw is int) {
      return Value(raw >> wrappedOther.raw);
    }

    throw UnsupportedError(
      'Right shift not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  // Overload the modulo operator
  Value operator %(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      return Value(raw % wrappedOther.raw);
    }

    throw UnsupportedError(
      'Modulo not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  // Overload the floor division operator
  Value operator ~/(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      return Value((raw / wrappedOther.raw).floor());
    }

    throw UnsupportedError(
      'Floor division not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  // Overload the exponentiation operator
  Value exp(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is num && wrappedOther.raw is num) {
      // Using Dart's math.pow; ensure to import 'dart:math' if not already
      return Value(math.pow(raw, wrappedOther.raw));
    }

    throw UnsupportedError(
      'Exponentiation not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  // Overload the negation operator
  Value operator -() {
    // Only perform direct operation on raw values
    if (raw is num) {
      return Value(-raw);
    }

    throw UnsupportedError(
      'Negation not supported for type ${raw.runtimeType}',
    );
  }

  // Overload the concatenation operator
  Value concat(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is String && wrappedOther.raw is String) {
      return Value(raw + wrappedOther.raw);
    }
    if (raw == null || other == null) {
      throw UnsupportedError('Attempt to concatenate a nil value');
    }

    throw UnsupportedError(
      'Concatenation not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}',
    );
  }

  // Overload the equality operator
  bool equals(Object other) {
    // Only perform direct comparison
    return super == other;
  }

  operator >(Object other) {
    if (raw is num && other is Value && other.raw is num) {
      return Value(raw > other.raw);
    }
    if (raw is String && other is Value && other.raw is String) {
      return Value(raw.compareTo(other.raw) > 0);
    }
    throw UnsupportedError(
      'Greater than not supported for these types ${raw.runtimeType} and ${other is Value ? other.raw.runtimeType : other.runtimeType}',
    );
  }

  operator <(Object other) {
    if (raw is num && other is Value && other.raw is num) {
      return Value(raw < other.raw);
    }
    if (raw is String && other is Value && other.raw is String) {
      return Value(raw.compareTo(other.raw) < 0);
    }
    throw UnsupportedError(
      'Less than not supported for these types ${raw.runtimeType} and ${other is Value ? other.raw.runtimeType : other.runtimeType}',
    );
  }

  operator >=(Object other) {
    if (raw is num && other is Value && other.raw is num) {
      return Value(raw >= other.raw);
    }
    if (raw is String && other is Value && other.raw is String) {
      return Value(raw.compareTo(other.raw) >= 0);
    }
    throw UnsupportedError(
      'Greater than or equal not supported for these types ${raw.runtimeType} and ${other is Value ? other.raw.runtimeType : other.runtimeType}',
    );
  }

  operator <=(Object other) {
    if (raw is num && other is Value && other.raw is num) {
      return Value(raw <= other.raw);
    }
    if (raw is String && other is Value && other.raw is String) {
      return Value(raw.compareTo(other.raw) <= 0);
    }
    throw UnsupportedError(
      'Less than or equal not supported for these types ${raw.runtimeType} and ${other is Value ? other.raw.runtimeType : other.runtimeType}',
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

  // Overload the bitwise XOR operator
  Value operator ^(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is int && wrappedOther.raw is int) {
      return Value(raw ^ wrappedOther.raw);
    }

    throw UnsupportedError(
      "Bitwise XOR not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  // Overload the bitwise OR operator
  Value operator |(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is int && wrappedOther.raw is int) {
      return Value(raw | wrappedOther.raw);
    }

    throw UnsupportedError(
      "Bitwise OR not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

  // Overload the bitwise AND operator
  Value operator &(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Only perform direct operation on raw values
    if (raw is int && wrappedOther.raw is int) {
      return Value(raw & wrappedOther.raw);
    }

    throw UnsupportedError(
      "Bitwise AND not supported for these types ${raw.runtimeType} and ${wrappedOther.raw.runtimeType}",
    );
  }

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
        Logger.debug('Error in finalizer: $e', category: 'Value');
      }
    }
  }

  @override
  bool get marked => _marked;

  @override
  set marked(bool value) => _marked = value;
}
