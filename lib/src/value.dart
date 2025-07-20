import 'dart:async';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/generational_gc.dart';
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

  /// Reference to the original metatable Value when set via `setmetatable`.
  /// This allows `getmetatable` to return the same table object that was
  /// provided, preserving identity semantics required by Lua tests.
  Value? metatableRef;

  /// References to captured upvalues if this value represents a function/closure.
  List<Upvalue>? upvalues;

  /// The AST node representing the function body, if this value is a Lua function.
  FunctionBody? functionBody;

  /// The name of the function, if this value is a named function.
  String? functionName;

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
  /// [functionName] - Name of the function (for debugging/debug.getinfo)
  Value(
    dynamic raw, {
    Map<String, dynamic>? metatable,
    this.isConst = false,
    this.isToBeClose = false,
    this.upvalues,
    this.interpreter,
    this.functionBody,
    this.functionName,
  }) {
    _raw = raw;
    _isInitialized = true;

    // If no metatable is provided, apply the default metatable for this type.
    // This mirrors Lua's behavior where strings, numbers, etc. share
    // common metatables giving them methods like string.find.
    if (metatable == null) {
      MetaTable().applyDefaultMetatable(this);
    } else {
      this.metatable = metatable;
    }

    if (GenerationalGCManager.isInitialized) {
      GenerationalGCManager.instance.register(this);
    }
  }

  bool isA<T>() {
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
  Future<dynamic> close([dynamic error]) async {
    if (!isToBeClose || raw == null || raw == false) {
      return null; // Only close to-be-closed variables with non-false values
    }

    final closeMeta = getMetamethod('__close');
    if (closeMeta != null) {
      try {
        dynamic result;
        if (closeMeta is Function) {
          result = closeMeta([this, error is Value ? error : Value(error)]);
        } else if (closeMeta is Value && closeMeta.raw is Function) {
          result = closeMeta.raw([this, error is Value ? error : Value(error)]);
        }

        if (result is Future) {
          result = await result;
        }

        // Normalize multi-value returns and unwrap Value wrappers
        if (result is Value) {
          if (result.isMulti &&
              result.raw is List &&
              (result.raw as List).isNotEmpty) {
            result = (result.raw as List).first;
          } else {
            result = result.raw;
          }
        }
        if (result is List && result.isNotEmpty) {
          result = result.first;
        }

        // Ignore returned values when closing because of an existing error
        if (error != null) {
          return null;
        }

        // Treat any non-nil/false return as an error object
        if (result != null && result != false) {
          return result;
        }
      } catch (e) {
        Logger.error(
          'Error in __close metamethod',
          category: 'Value',
          error: e,
        );
        return e;
      }
    }
    return null;
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
  bool hasMetamethod(String event) =>
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
      return Value(newMap);
    }
    return Value(value);
  }

  /// Unwraps a Value to get its raw value, recursively for tables and lists.
  dynamic unwrap() {
    if (raw is Map) {
      final unwrapped = <dynamic, dynamic>{};
      (raw as Map).forEach((key, value) {
        final realKey = key is LuaString ? key.toString() : key;
        dynamic out;
        if (value is Value) {
          out = value.unwrap();
        } else if (value is Map || value is List) {
          out = Value(value).completeUnwrap();
        } else if (value is LuaString) {
          out = value.toString();
        } else {
          out = value;
        }
        unwrapped[realKey] = out;
      });
      return unwrapped;
    }
    if (raw is List) {
      return (raw as List).map((e) {
        if (e is Value) {
          return e.unwrap();
        } else if (e is Map || e is List) {
          return Value(e).unwrap();
        } else if (e is LuaString) {
          return e.toString();
        }
        return e;
      }).toList();
    }
    if (raw is LuaString) {
      // Decode using UTF-8 so multi-byte characters (e.g. Chinese) are
      // preserved when users call `.unwrap()`.
      return (raw as LuaString).toString();
    }
    return raw is Value ? raw.completeUnwrap() : raw;
  }

  dynamic completeUnwrap() {
    var current = raw;
    while (current is Value) {
      current = current.unwrap();
    }
    if (current is LuaString) {
      return (current).toString();
    }
    return current;
  }

  @override
  int get hashCode => raw.hashCode;

  @override
  bool operator ==(Object other) => equals(other);

  // Guard to prevent infinite recursion in toString
  static final Set<int> _toStringGuard = <int>{};

  @override
  String toString() {
    final objectId = identityHashCode(this);

    // Check if we're already in a toString call for this object
    if (_toStringGuard.contains(objectId)) {
      // Fallback to simple representation to avoid recursion
      if (raw == null) return "Value:<nil>";
      if (raw is bool) return "Value:<$raw>";
      if (raw is num || raw is BigInt) return "Value:<$raw>";
      if (raw is String) return "Value:<$raw>";
      if (raw is List) return "Value:<list:${raw.hashCode}>";
      if (raw is Map) return "Value:<table:${raw.hashCode}>";
      if (raw is Function) return "Value:<function:${raw.hashCode}>";
      return "Value:<$raw>";
    }

    final tostringMeta = getMetamethod('__tostring');
    if (tostringMeta != null) {
      // Check if this is a Lua function (which would return a Future)
      if (tostringMeta is Value && tostringMeta.raw is Function) {
        // This is a Lua function, calling it would return a Future
        // For toString(), we can't handle Futures, so use default representation
        return "Value:<table:${raw.hashCode}>";
      }

      try {
        _toStringGuard.add(objectId);
        final result = callMetamethod('__tostring', [this]);
        // Handle both sync and async results
        if (result is Future) {
          // For toString(), we can't await, so return a placeholder
          return "Value:<table:${raw.hashCode}>";
        }
        return result is Value ? result.raw.toString() : result.toString();
      } catch (e) {
        // If metamethod call fails, fall back to default behavior
        Logger.debug('Error in __tostring metamethod: $e', category: 'Value');
      } finally {
        _toStringGuard.remove(objectId);
      }
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
    if (raw is Map) {
      // Normalize the key
      var rawKey = key is Value ? key.raw : key;
      if (rawKey is LuaString) {
        rawKey = rawKey.toString();
      }

      // First check if the key exists in the table
      if ((raw as Map).containsKey(rawKey)) {
        var result = (raw as Map)[rawKey];
        // If the result is not already wrapped, wrap it
        if (result is! Value) result = Value(result);
        return result;
      }

      // Key doesn't exist, check for __index metamethod
      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        final result = callMetamethod('__index', [
          this,
          key is Value ? key : Value(key),
        ]);

        return result is Value ? result : Value(result);
      }

      // No metamethod and key not found, return nil
      return Value(null);
    } else {
      // Not a table, but might have an __index metamethod
      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        return callMetamethod('__index', [
          this,
          key is Value ? key : Value(key),
        ]);
      }
      // No metamethod, cannot index
      final tname = NumberUtils.typeName(raw);
      throw LuaError.typeError('attempt to index a $tname value');
    }
  }

  /// Asynchronous version of [operator []] that awaits any `__index`
  /// metamethod results. This is needed when metamethods are implemented as
  /// Lua functions which return [Future]s.
  Future<dynamic> getValueAsync(Object? key) async {
    if (raw is Map) {
      var rawKey = key is Value ? key.raw : key;
      if (rawKey is LuaString) {
        rawKey = rawKey.toString();
      }

      if ((raw as Map).containsKey(rawKey)) {
        var result = (raw as Map)[rawKey];
        if (result is! Value) result = Value(result);
        return result;
      }

      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        var result = await callMetamethodAsync('__index', [
          this,
          key is Value ? key : Value(key),
        ]);
        return result is Value ? result : Value(result);
      }

      return Value(null);
    } else {
      final indexMeta = getMetamethod('__index');
      if (indexMeta != null) {
        var result = await callMetamethodAsync('__index', [
          this,
          key is Value ? key : Value(key),
        ]);
        return result;
      }
      final tname = NumberUtils.typeName(raw);
      throw LuaError.typeError('attempt to index a $tname value');
    }
  }

  @override
  void operator []=(Object key, dynamic value) {
    var rawKey = key is Value ? key.raw : key;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }
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
    if (raw is Map) {
      final valueToSet = value is Value ? value : Value(value);
      if (valueToSet.isNil) {
        (raw as Map).remove(rawKey);
      } else {
        (raw as Map)[rawKey] = valueToSet;
      }
      return;
    }
    final tname = NumberUtils.typeName(raw);
    throw LuaError.typeError('attempt to index a $tname value');
  }

  /// Assigns [value] to [key], awaiting any __newindex metamethod.
  Future<void> setValueAsync(
    Object key,
    dynamic value, [
    Set<Value>? visited,
  ]) async {
    var rawKey = key is Value ? key.raw : key;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }
    if (rawKey == null) {
      throw LuaError.typeError('table index is nil');
    }
    if (rawKey is num && rawKey.isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    final newindexMeta = getMetamethod('__newindex');
    if (newindexMeta != null) {
      visited ??= <Value>{};
      if (visited.contains(this)) {
        throw LuaError('loop in settable');
      }
      visited.add(this);

      if (newindexMeta is Value && newindexMeta.raw is Map) {
        await newindexMeta.setValueAsync(key, value, visited);
        return;
      }

      final result = callMetamethod('__newindex', [
        this,
        key is Value ? key : Value(key),
        value is Value ? value : Value(value),
      ]);
      if (result is Future) await result;
      return;
    }
    if (raw is Map) {
      final valueToSet = value is Value ? value : Value(value);
      if (valueToSet.isNil) {
        (raw as Map).remove(rawKey);
      } else {
        (raw as Map)[rawKey] = valueToSet;
      }
      return;
    }
    final tname = NumberUtils.typeName(raw);
    throw LuaError.typeError('attempt to index a $tname value');
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

    // Normalize the key the same way as operator[]
    var rawKey = key is Value ? key.raw : key;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }

    // First check if the key exists in the table directly
    if ((raw as Map).containsKey(rawKey)) {
      return true;
    }

    // Key doesn't exist, check if __index metamethod would return a non-nil value
    final indexMeta = getMetamethod('__index');
    if (indexMeta != null) {
      final result = callMetamethod('__index', [this, Value(key)]);
      return result != null && (result is Value ? result.raw != null : true);
    }

    return false;
  }

  /// Checks if the raw table contains the key (without metamethods)
  bool rawContainsKey(Object? key) {
    if (raw is! Map) return false;

    // Normalize the key the same way as operator[]
    var rawKey = key is Value ? key.raw : key;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }

    return (raw as Map).containsKey(rawKey);
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
    if (raw == null) return 0;

    if (raw is LuaString) {
      return (raw as LuaString).length;
    }

    final lenMeta = getMetamethod('__len');
    if (lenMeta != null) {
      final result = callMetamethod('__len', [this]);
      return result is Value ? result.raw as int : result as int;
    }

    if (raw is String) {
      return (raw as String).length;
    }

    if (raw is List) {
      return (raw as List).length;
    }

    if (raw is! Map) {
      throw LuaError.typeError('attempt to get length of a ${raw.runtimeType}');
    }

    final map = raw as Map;
    int n = 0;
    while (map.containsKey(n + 1)) {
      n++;
    }
    return n;
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

  /// Asynchronous version of callMetamethod for use in async contexts
  Future<Object?> callMetamethodAsync(String s, List<Value> list) async {
    Logger.debug(
      'callMetamethodAsync called with $s, args: ${list.map((e) => e.raw)}',
    );
    final method = getMetamethod(s);
    if (method == null) {
      throw UnsupportedError("attempt to call a nil value");
    }

    // Special handling for __index and __newindex when they are tables
    if (s == '__index' && method is Value && method.raw is Map) {
      // __index is a table. Lua repeats the lookup on that table, allowing
      // further metamethod processing.
      if (list.length >= 2) {
        final key = list[1];
        var result = method[key];
        if (result is Value && result.raw is Future) {
          result = await result.raw;
        } else if (result is Future) {
          result = await result;
        }
        if (result is Value && result.isMulti && result.raw is List) {
          final values = result.raw as List;
          return values.isNotEmpty ? values.first : Value(null);
        } else if (result is List && result.isNotEmpty) {
          return result.first is Value ? result.first : Value(result.first);
        }
        return result;
      }
    } else if (s == '__newindex' && method is Value && method.raw is Map) {
      // __newindex is a table, so repeat the assignment on that table. This
      // allows the table's own metamethods to run, matching Lua semantics.
      if (list.length >= 3) {
        final key = list[1];
        final value = list[2];
        await method.setValueAsync(key, value, <Value>{this});
        return Value(null);
      }
    }

    if (method is Function) {
      var result = method(list);
      if (result is Future) result = await result;
      return result;
    } else if (method is BuiltinFunction) {
      var result = method.call(list);
      if (result is Future) result = await result;
      return result;
    } else if (method is Value) {
      if (method.raw is Function) {
        var result = (method.raw as Function)(list);
        if (result is Future) result = await result;
        return result;
      } else if (method.raw is BuiltinFunction) {
        var result = (method.raw as BuiltinFunction).call(list);
        if (result is Future) result = await result;
        return result;
      } else if (method.raw is FunctionDef ||
          method.raw is FunctionLiteral ||
          method.raw is FunctionBody) {
        // This is a Lua function defined as an AST node
        // We can await it here since this is an async method
        final interpreter =
            method.interpreter ?? Environment.current?.interpreter;
        if (interpreter != null) {
          final result = await interpreter.callFunction(method, list);
          // For __index metamethod, only return the first value if multiple values are returned
          if (s == '__index') {
            if (result is Value && result.isMulti && result.raw is List) {
              final values = result.raw as List;
              return values.isNotEmpty ? values.first : Value(null);
            } else if (result is List && result.isNotEmpty) {
              return result.first is Value ? result.first : Value(result.first);
            }
          }
          return result;
        }
        throw UnsupportedError("No interpreter available to call function");
      }
    } else if (method is FunctionDef) {
      // Handle direct FunctionDef nodes
      final interpreter = Environment.current?.interpreter;
      if (interpreter != null) {
        final result = await interpreter.callFunction(Value(method), list);
        return result;
      }
      throw UnsupportedError("No interpreter available to call function");
    }

    throw UnsupportedError(
      "attempt to call a non-function $s(${list.map((a) => a.unwrap()).join(', ')})",
    );
  }

  Object? callMetamethod(String s, List<Value> list) {
    final method = getMetamethod(s);
    if (method == null) {
      throw UnsupportedError("attempt to call a nil value");
    }

    // Special handling for __index and __newindex when they are tables
    if (s == '__index' && method is Value && method.raw is Map) {
      // __index is a table, so do lookup through that table
      if (list.length >= 2) {
        final key = list[1];
        // Use the Value's indexing mechanism to handle potential metamethods
        final result = method[key];

        return result;
      }
    } else if (s == '__newindex' && method is Value && method.raw is Map) {
      // __newindex is a table, so repeat the assignment on that table and
      // propagate any asynchronous result up to the caller.
      if (list.length >= 3) {
        final key = list[1];
        final value = list[2];
        return method.setValueAsync(key, value, <Value>{this});
      }
    }

    if (method is Function) {
      return method(list);
    } else if (method is BuiltinFunction) {
      return method.call(list);
    } else if (method is Value) {
      if (method.raw is Function) {
        // This is a Lua function - calling it directly returns a Future
        // For synchronous contexts like toString(), we need to avoid this
        final result = (method.raw as Function)(list);
        return result;
      } else if (method.raw is BuiltinFunction) {
        return (method.raw as BuiltinFunction).call(list);
      } else if (method.raw is FunctionDef ||
          method.raw is FunctionLiteral ||
          method.raw is FunctionBody) {
        // This is a Lua function defined as an AST node
        // We need to call it using the interpreter
        final interpreter =
            method.interpreter ?? Environment.current?.interpreter;
        if (interpreter != null) {
          // Call the function directly using the interpreter
          final result = interpreter.callFunction(method, list);

          // Note: This may return a Future, which should be handled by callers
          // For synchronous contexts, this will not work properly
          return result;
        }
        throw UnsupportedError("No interpreter available to call function");
      }
    } else if (method is FunctionDef) {
      // Handle direct FunctionDef nodes
      final interpreter = Environment.current?.interpreter;
      if (interpreter != null) {
        // Call the function directly using the interpreter
        return interpreter.callFunction(Value(method), list);
      }
      throw UnsupportedError("No interpreter available to call function");
    }

    throw UnsupportedError(
      "attempt to call a non-function $s(${list.map((a) => a.unwrap()).join(', ')})",
    );
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
    // The GC manager now handles __gc metamethods.
    // This method is for other resource cleanup if needed.
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

  // Helper method for Lua truthiness evaluation
  bool isTruthy() {
    // In Lua, only nil and false are falsy - everything else is truthy
    return raw != null && raw != false;
  }

  bool isFalsy() {
    // In Lua, only nil and false are falsy
    return raw == null || raw == false;
  }

  // Add a helper for Lua's ~= (not equal) semantics
  bool notEquals(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN ~= anything is always true
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debug(
        'COMPARE ~=: NaN detected, returning true',
        category: 'Value',
      );
      return true;
    }
    // Lua: int ~= float if float does not exactly represent int
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        Logger.debug(
          'COMPARE ~=: int ~= non-finite double, returning true',
          category: 'Value',
        );
        return true;
      }
      final intVal = raw is BigInt ? raw as BigInt : BigInt.from(raw);
      final doubleVal = otherRaw;
      final doubleFromInt = intVal.toDouble();
      final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      Logger.debug(
        'COMPARE ~=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return !isExact;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!(raw).isFinite) {
        Logger.debug(
          'COMPARE ~=: double ~= int, but double is not finite, returning true',
          category: 'Value',
        );
        return true;
      }
      final intVal = otherRaw is BigInt ? otherRaw : BigInt.from(otherRaw);
      final doubleVal = raw;
      final doubleFromInt = intVal.toDouble();
      final intFromDouble = BigInt.parse(doubleVal.toStringAsFixed(0));
      final isExact = (doubleVal == doubleFromInt) && (intVal == intFromDouble);
      Logger.debug(
        'COMPARE ~=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return !isExact;
    }
    return !(this == other);
  }

  Value _arith(String op, Value other) {
    final result = NumberUtils.performArithmetic(op, raw, other.raw);
    return Value(result);
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
    final result = NumberUtils.bitwiseNot(raw);
    return Value(result);
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
    final result = NumberUtils.negate(raw);
    return Value(result);
  }

  // Overload the concatenation operator
  Value concat(dynamic other) {
    // Wrap the other value if needed
    final wrappedOther = other is Value ? other : Value.wrap(other);

    // Handle LuaString concatenation
    if (raw is LuaString) {
      if (wrappedOther.raw is LuaString) {
        return Value((raw as LuaString) + (wrappedOther.raw as LuaString));
      } else if (wrappedOther.raw is num) {
        final otherStr = LuaString.fromDartString(wrappedOther.raw.toString());
        return Value((raw as LuaString) + otherStr);
      } else {
        final otherStr = LuaString.fromDartString(wrappedOther.raw.toString());
        return Value((raw as LuaString) + otherStr);
      }
    }

    if (wrappedOther.raw is LuaString) {
      if (raw is num) {
        final thisStr = LuaString.fromDartString(raw.toString());
        return Value(thisStr + (wrappedOther.raw as LuaString));
      } else {
        final thisStr = LuaString.fromDartString(raw.toString());
        return Value(thisStr + (wrappedOther.raw as LuaString));
      }
    }

    // Regular string concatenation - return Dart strings for better interop
    if (raw is String) {
      if (wrappedOther.raw is String) {
        return Value(raw + wrappedOther.raw);
      } else if (wrappedOther.raw is num) {
        return Value(raw + wrappedOther.raw.toString());
      }
      return Value(raw + wrappedOther.raw.toString());
    }

    if (raw is num) {
      if (wrappedOther.raw is String) {
        return Value(raw.toString() + wrappedOther.raw);
      } else if (wrappedOther.raw is num) {
        return Value(raw.toString() + wrappedOther.raw.toString());
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

  dynamic operator >(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN > anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debug(
        'COMPARE >: NaN detected, returning false',
        category: 'Value',
      );
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
      Logger.debug(
        'COMPARE >: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
      Logger.debug(
        'COMPARE >: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) > otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) > LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) > otherRaw;
    }
    throw UnsupportedError(
      'Greater than not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  dynamic operator <(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN < anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debug(
        'COMPARE <: NaN detected, returning false',
        category: 'Value',
      );
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
      Logger.debug(
        'COMPARE <: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
      Logger.debug(
        'COMPARE <: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) < otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) < LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) < otherRaw;
    }
    throw UnsupportedError(
      'Less than not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  dynamic operator >=(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN >= anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debug(
        'COMPARE >=: NaN detected, returning false',
        category: 'Value',
      );
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
      Logger.debug(
        'COMPARE >=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
      Logger.debug(
        'COMPARE >=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) >= otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) >= LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) >= otherRaw;
    }
    throw UnsupportedError(
      'Greater than or equal not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  dynamic operator <=(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN <= anything is always false
    if ((raw is num && (raw as num).isNaN) ||
        (otherRaw is num && (otherRaw).isNaN)) {
      Logger.debug(
        'COMPARE <=: NaN detected, returning false',
        category: 'Value',
      );
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
      Logger.debug(
        'COMPARE <=: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
      Logger.debug(
        'COMPARE <=: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt',
        category: 'Value',
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
    if (raw is LuaString && otherRaw is LuaString) {
      return (raw as LuaString) <= otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return (raw as LuaString) <= LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) <= otherRaw;
    }
    throw UnsupportedError(
      'Less than or equal not supported for these types ${raw.runtimeType} and ${other.runtimeType}',
    );
  }

  bool equals(Object other) {
    final otherRaw = other is Value ? other.raw : other;
    // Lua: NaN == anything is always false
    if ((raw is num && raw.isNaN) || (otherRaw is num && otherRaw.isNaN)) {
      Logger.debug(
        'COMPARE ==: NaN detected, returning false',
        category: 'Value',
      );
      return false;
    }
    // Lua: int == float only if float is finite and exactly represents int
    if ((raw is int || raw is BigInt) && otherRaw is double) {
      if (!otherRaw.isFinite) {
        Logger.debug(
          'COMPARE ==: int == non-finite double, returning false',
          category: 'Value',
        );
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
      Logger.debug(
        'COMPARE ==: int=$intVal, double=$doubleVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return isExact;
    }
    if (raw is double && (otherRaw is int || otherRaw is BigInt)) {
      if (!raw.isFinite) {
        Logger.debug(
          'COMPARE ==: double == int, but double is not finite, returning false',
          category: 'Value',
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
      Logger.debug(
        'COMPARE ==: double=$doubleVal, int=$intVal, doubleFromInt=$doubleFromInt, intFromDouble=$intFromDouble, isExact=$isExact',
        category: 'Value',
      );
      return isExact;
    }
    if ((raw is BigInt && otherRaw is double) ||
        (raw is double && otherRaw is BigInt)) {
      final d1 = raw is BigInt ? raw.toDouble() : raw;
      final d2 = otherRaw is BigInt ? otherRaw.toDouble() : otherRaw;
      Logger.debug(
        'COMPARE ==: promoting BigInt to double: $d1 == $d2',
        category: 'Value',
      );
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

    if (raw is LuaString && otherRaw is LuaString) {
      return raw == otherRaw;
    }
    if (raw is LuaString && otherRaw is String) {
      return raw == LuaString.fromDartString(otherRaw);
    }
    if (raw is String && otherRaw is LuaString) {
      return LuaString.fromDartString(raw) == otherRaw;
    }

    if (raw is Map && otherRaw is Map) {
      // Tables compare by reference when no '__eq' metamethod is present.
      // Using the default Dart equality here preserves this behavior.
      return raw == otherRaw;
    }
    return raw == otherRaw;
  }
}
