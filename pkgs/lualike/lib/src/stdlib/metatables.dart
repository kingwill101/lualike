// import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/utils/type.dart';

import '../../lualike.dart';

Object? _callMetatableCallable(Object? callable, List<Object?> args) {
  final rawCallable = rawLuaSlot(callable);
  if (rawCallable is Function) {
    return rawCallable(args);
  }
  if (rawCallable is BuiltinFunction) {
    return rawCallable.call(args);
  }
  return callable;
}

/// Provides the default metatables and metamethod caches for built-in Lua
/// types.
class MetaTable {
  static final MetaTable _instance = MetaTable._internal();

  bool _initialized = false;
  final Map<String, ValueClass> _typeMetatables = {};
  final Map<String, Value?> _typeMetatableRefs = {};
  bool _numberMetatableEnabled = false;
  LuaRuntime? _interpreter;

  // Cache for stdlib methods to avoid repeated lookups and wrapper creation
  final Map<String, dynamic> _cachedStringMethods = {};

  // Cache method wrappers per-string-instance to avoid creating new closures
  static final Expando<Map<String, Value>> _stringMethodCache =
      Expando<Map<String, Value>>('stringMethodCache');

  factory MetaTable() {
    return _instance;
  }

  MetaTable._internal();

  /// Initializes the singleton with the active runtime.
  ///
  /// Repeated calls are allowed. The first call installs the default
  /// metatables, and later calls simply refresh the runtime handle used for
  /// stdlib lookups and string-method caching.
  static void initialize(LuaRuntime interpreter) {
    _instance._interpreter = interpreter;
    _instance._initialize(interpreter);
  }

  /// Refreshes cached string-library method lookups for the current runtime.
  ///
  /// String indexing uses this cache on hot paths to avoid repeated library
  /// table lookups and wrapper allocation for method dispatch like
  /// `"abc":sub(...)`.
  static void refreshStringCache() {
    final instance = _instance;
    final interpreter = instance._interpreter;
    if (interpreter == null) {
      return;
    }
    instance._cacheStdlibMethods(interpreter, force: true);
  }

  void _initialize(LuaRuntime interpreter) {
    if (_initialized) {
      Logger.debugLazy(
        () => 'MetaTable already initialized, skipping',
        category: 'Metatables',
      );
      return;
    }

    Logger.debugLazy(() => 'Initializing MetaTable', category: 'Metatables');

    // String metatable
    _typeMetatables['string'] = ValueClass.create({
      '__len': (List<Object?> args) {
        final rawStr = rawLuaSlot(args[0]);
        Logger.debugLazy(
          () => 'String __len metamethod called for "$rawStr"',
          category: 'Metatables',
        );
        if (rawStr is LuaString) {
          return _primitiveValue(rawStr.length);
        }
        return _primitiveValue(rawStr.toString().length);
      },
      '__index': (List<Object?> args) {
        final str = args[0] as Value;
        final key = args[1];
        final rawStr = rawLuaSlot(str);
        final rawKey = rawLuaSlot(key);
        Logger.debugLazy(
          () => 'String __index metamethod called for "$rawStr"[$rawKey]',
          category: 'Metatables',
        );

        final keyStr = switch (rawKey) {
          final String stringValue => stringValue,
          final LuaString stringValue => stringValue.toString(),
          _ => null,
        };

        if (keyStr != null) {
          // Check if we've cached a wrapper for this string+method combination
          var methodCache = _stringMethodCache[str];
          if (methodCache != null) {
            final cachedWrapper = methodCache[keyStr];
            if (cachedWrapper != null) {
              Logger.debugLazy(
                () => 'Returning cached method wrapper for $keyStr',
                category: 'Metatables',
              );
              return cachedWrapper;
            }
          }

          // Use cached method lookup to avoid repeated string table access
          var method = _cachedStringMethods[keyStr];
          if (method == null && _interpreter != null) {
            _interpreter!.libraryRegistry.initializeLibraryByName('string');
            _cacheStdlibMethods(_interpreter!, force: true);
            method = _cachedStringMethods[keyStr];
          }
          if (method != null) {
            Logger.debugLazy(
              () => 'Found cached string method: $keyStr',
              category: 'Metatables',
            );

            // Create method wrapper and cache it on this string instance
            final wrapper = Value(
              (callArgs) {
                Logger.debugLazy(
                  () =>
                      'String method $rawKey called with ${callArgs.length} arguments',
                  category: 'Metatables',
                );

                // was the method invoked with the string already as first arg?
                final hasSelf = callArgs.isNotEmpty && callArgs.first == str;

                if (hasSelf) {
                  return _callMetatableCallable(method, callArgs);
                }

                // prepend the string itself (obj:func() syntax)
                return _callMetatableCallable(method, [str, ...callArgs]);
              },
              isTempKey: true,
              interpreter: _interpreter,
            ); // Don't count this wrapper in GC debt

            // Cache the wrapper on this string instance
            if (methodCache == null) {
              methodCache = <String, Value>{};
              _stringMethodCache[str] = methodCache;
            }
            methodCache[keyStr] = wrapper;

            return wrapper;
          }
        }

        Logger.debugLazy(
          () => 'String method not found: $rawKey',
          category: 'Metatables',
        );
        return _primitiveValue(null);
      },
      '__eq': (List<Object?> args) {
        final a = args[0];
        final b = args[1];
        Logger.debugLazy(
          () =>
              'String __eq metamethod called: "${rawLuaSlot(a)}" == "${rawLuaSlot(b)}"',
          category: 'Metatables',
        );
        return _primitiveValue(rawLuaSlotsEqual(a, b));
      },
    });
    Logger.debugLazy(
      () => 'String metatable initialized',
      category: 'Metatables',
    );

    // Number metatable
    _typeMetatables['number'] = ValueClass.create({
      '__add': (List<Object?> args) => _argumentValue(args[0]) + args[1],
      '__sub': (List<Object?> args) => _argumentValue(args[0]) - args[1],
      '__mul': (List<Object?> args) => _argumentValue(args[0]) * args[1],
      '__div': (List<Object?> args) => _argumentValue(args[0]) / args[1],
      '__idiv': (List<Object?> args) => _argumentValue(args[0]) ~/ args[1],
      '__mod': (List<Object?> args) => _argumentValue(args[0]) % args[1],
      '__pow': (List<Object?> args) => _argumentValue(args[0]).exp(args[1]),
      '__unm': (List<Object?> args) => -_argumentValue(args[0]),
      '__bnot': (List<Object?> args) => ~_argumentValue(args[0]),
      '__band': (List<Object?> args) => _argumentValue(args[0]) & args[1],
      '__bor': (List<Object?> args) => _argumentValue(args[0]) | args[1],
      '__bxor': (List<Object?> args) => _argumentValue(args[0]) ^ args[1],
      '__shl': (List<Object?> args) => _argumentValue(args[0]) << args[1],
      '__shr': (List<Object?> args) => _argumentValue(args[0]) >> args[1],
      '__eq': (List<Object?> args) =>
          _primitiveValue(_argumentValue(args[0]) == args[1]),
      '__lt': (List<Object?> args) =>
          _primitiveValue(_argumentValue(args[0]) < _comparisonArg(args[1])),
      '__le': (List<Object?> args) =>
          _primitiveValue(_argumentValue(args[0]) <= _comparisonArg(args[1])),
    });
    Logger.debugLazy(
      () => 'Number metatable initialized',
      category: 'Metatables',
    );

    // Table metatable (do not define __len by default; '#' should use array boundary rule)
    _typeMetatables['table'] = ValueClass.create({
      // Removed '__index' and '__newindex' from default table metatable
      // These should only be present when explicitly set by the user
      '__pairs': (List<Object?> args) {
        final table = args[0] as Value;
        final rawTable = rawLuaSlot(table);
        Logger.debugLazy(
          () => 'Table __pairs metamethod called for table:${table.hashCode}',
          category: 'Metatables',
        );
        Logger.debugLazy(
          () => 'Table content: ${(rawTable as Map).toString()}',
          category: 'Metatables',
        );
        if (rawTable is! Map) {
          Logger.debugLazy(
            () =>
                'Error: Attempt to iterate over non-table value of type ${rawTable.runtimeType}',
            category: 'Metatables',
          );
          throw LuaError("attempt to iterate over non-table value");
        }

        // Create a filtered map without nil values
        final map = rawTable;
        Logger.debugLazy(
          () => 'Raw map entries before filtering: ${map.entries.length}',
          category: 'Metatables',
        );
        final filteredEntries = map.entries.where((entry) {
          final value = entry.value;
          final keep = !isLuaNilSlot(value);
          Logger.debugLazy(
            () =>
                'Filter entry: key=${entry.key}, value=${entry.value}, keep=$keep',
            category: 'Metatables',
          );
          return keep;
        }).toList();

        Logger.debugLazy(
          () =>
              'Table pairs iterator created with ${filteredEntries.length} entries',
          category: 'Metatables',
        );
        for (final entry in filteredEntries) {
          Logger.debugLazy(
            () => 'Entry in filtered list: ${entry.key} -> ${entry.value}',
            category: 'Metatables',
          );
        }

        // Return iterator function, table, and nil
        Logger.debugLazy(
          () => 'Returning iterator function and state',
          category: 'Metatables',
        );
        return LuaResults([
          Value((List<Object?> args) {
            final state = args[0] as Value;
            final k = args[1];
            final rawK = rawLuaSlot(k);
            Logger.debugLazy(
              () =>
                  'Table pairs iterator called with state:${state.hashCode} key: $rawK',
              category: 'Metatables',
            );

            int foundIndex = -1;
            if (rawK == null) {
              Logger.debugLazy(
                () =>
                    'Initial call with nil key, returning first entry if available',
                category: 'Metatables',
              );
              foundIndex = 0;
            } else {
              Logger.debugLazy(
                () => 'Looking for entry after key $rawK',
                category: 'Metatables',
              );
              // Find the index of the entry that matches the current key
              for (int i = 0; i < filteredEntries.length; i++) {
                final entry = filteredEntries[i];
                Logger.debugLazy(
                  () =>
                      'Checking entry $i: key=${entry.key}, current key=$rawK',
                  category: 'Metatables',
                );
                if (entry.key == rawK) {
                  foundIndex = i + 1; // Return next entry
                  Logger.debugLazy(
                    () =>
                        'Found matching entry at index $i, will return index $foundIndex next',
                    category: 'Metatables',
                  );
                  break;
                }
              }
            }

            if (foundIndex >= 0 && foundIndex < filteredEntries.length) {
              final entry = filteredEntries[foundIndex];
              Logger.debugLazy(
                () =>
                    'Returning next entry: key=${entry.key}, value=${entry.value}',
                category: 'Metatables',
              );
              return [
                cachedPrimitiveOrValue(_interpreter, entry.key),
                cachedPrimitiveOrValue(_interpreter, entry.value),
              ];
            }

            Logger.debugLazy(
              () => 'Table pairs iterator finished, no more entries',
              category: 'Metatables',
            );
            return [_primitiveValue(null)];
          }, interpreter: _interpreter),
          table,
          _primitiveValue(null),
        ]);
      },
    });
    Logger.debugLazy(
      () => 'Table metatable initialized',
      category: 'Metatables',
    );

    // Function metatable
    _typeMetatables['function'] = ValueClass.create({
      '__call': (List<Object?> args) {
        final func = args[0];
        final callArgs = args.sublist(1);
        final rawFunc = rawLuaSlot(func);
        Logger.debugLazy(
          () =>
              'Function __call metamethod called for function:${func.hashCode} with ${callArgs.length} args',
          category: 'Metatables',
        );
        if (rawFunc is Function) {
          final result = rawFunc(callArgs);
          Logger.debugLazy(
            () => 'Function call result: $result',
            category: 'Metatables',
          );
          return result;
        } else if (rawFunc is BuiltinFunction) {
          final result = rawFunc.call(callArgs);
          Logger.debugLazy(
            () => 'Function call result: $result',
            category: 'Metatables',
          );
          return result;
        }

        throw LuaError("attempt to call non-function value");
      },
    });
    Logger.debugLazy(
      () => 'Function metatable initialized',
      category: 'Metatables',
    );

    // Coroutine metatable
    _typeMetatables['thread'] = ValueClass.create({
      '__tostring': (List<Object?> args) {
        final thread = args[0] as Value;
        final coroutine = rawLuaSlot(thread) as Coroutine;
        Logger.debugLazy(
          () =>
              'Thread __tostring metamethod called for coroutine:${thread.hashCode}',
          category: 'Metatables',
        );
        return valueFromOptionalLuaSlot(
          _interpreter,
          'thread: ${thread.hashCode} [${coroutine.status}]',
        );
      },
    });
    Logger.debugLazy(
      () => 'Thread metatable initialized',
      category: 'Metatables',
    );
    // Register coroutine metatable as a default for thread objects
    registerDefaultMetatable('thread', _typeMetatables['thread']!);

    // Userdata metatable
    _typeMetatables['userdata'] = ValueClass.create({
      '__tostring': (List<Object?> args) {
        final userdata = args[0] as Value;
        Logger.debugLazy(
          () =>
              'Userdata __tostring metamethod called for userdata:${userdata.hashCode}',
          category: 'Metatables',
        );
        return valueFromOptionalLuaSlot(
          _interpreter,
          'userdata: ${userdata.hashCode}',
        );
      },
      '__len': (List<Object?> args) {
        final table = args[0] as Value;
        Logger.debugLazy(
          () =>
              'Userdata __len metamethod called for userdata:${table.hashCode}',
          category: 'Metatables',
        );

        return switch (table.unwrap().runtimeType) {
          (const (Map)) => table.unwrap().length,
          (const (List)) => table.unwrap().length,
          (const (List<Object?>)) => table.unwrap().length,
          (const (LuaString)) => (table.unwrap() as LuaString).length,
          _ => throw LuaError(
            "attempt to get length of unknown value ${table.unwrap().runtimeType}",
          ),
        };
      },
      '__gc': (List<Object?> args) {
        final userdata = args[0] as Value;
        Logger.debugLazy(
          () =>
              'Userdata __gc metamethod called for userdata:${userdata.hashCode}',
          category: 'Metatables',
        );
        return _primitiveValue(null);
      },
    });
    Logger.debugLazy(
      () => 'Userdata metatable initialized',
      category: 'Metatables',
    );

    // Pre-cache string table and methods to reduce wrapper creation
    _cacheStdlibMethods(interpreter);

    _initialized = true;
    Logger.debugLazy(
      () => 'All default metatables initialized successfully',
      category: 'Metatables',
    );
  }

  /// Pre-cache stdlib methods to avoid creating temporary wrappers on each access
  void _cacheStdlibMethods(LuaRuntime interpreter, {bool force = false}) {
    if (!force && _cachedStringMethods.isNotEmpty) {
      return;
    }
    // Cache string methods from the global string table
    final stringTable = interpreter.globals.get('string');
    final rawStringTable = rawLuaSlot(stringTable);
    if (rawStringTable is Map) {
      final stringMap = rawStringTable;

      // Cache all string methods to avoid repeated map lookups
      for (final entry in stringMap.entries) {
        _cachedStringMethods[entry.key.toString()] = entry.value;
      }

      Logger.debugLazy(
        () => 'Cached ${_cachedStringMethods.length} string methods',
        category: 'Metatables',
      );
    }
  }

  /// Get metatable for a given type
  ValueClass? getTypeMetatable(String type) {
    Logger.debugLazy(
      () => 'Getting type metatable for: $type',
      category: 'Metatables',
    );
    return _typeMetatables[type];
  }

  bool get numberMetatableEnabled => _numberMetatableEnabled;

  Value _primitiveValue(Object? raw) {
    return cachedPrimitiveOrValue(_interpreter, raw);
  }

  Value _argumentValue(Object? raw) {
    return cachedPrimitiveOrValue(_interpreter, raw);
  }

  Object _comparisonArg(Object? raw) {
    return raw ?? _argumentValue(raw);
  }

  bool isDefaultMetatableActive(String type) => switch (type) {
    'table' => false,
    'number' => _numberMetatableEnabled,
    _ => _typeMetatables.containsKey(type),
  };

  /// Register a default metatable for a type. If [metatable] is null, any
  /// existing default metatable for the type will be removed.
  void registerDefaultMetatable(
    String type,
    ValueClass? metatable, [
    Value? original,
  ]) {
    Logger.debugLazy(
      () => 'Registering default metatable for type: $type',
      category: 'Metatables',
    );
    if (metatable == null) {
      _typeMetatables.remove(type);
      _typeMetatableRefs.remove(type);
      if (type == 'number') {
        _numberMetatableEnabled = false;
      }
      return;
    }

    _typeMetatables[type] = metatable;
    _typeMetatableRefs[type] = original;
    if (type == 'number') {
      _numberMetatableEnabled = true;
    }
  }

  /// Applies the default metatable for a value based on its type.
  ///
  /// This method determines the appropriate metatable for a value based on its type
  /// and applies it. If the metatable contains a __gc metamethod, the object is also
  /// marked for finalization.
  ///
  /// As per section 2.5.3 of the Lua reference manual:
  /// "It is a good practice to add all needed metamethods to a table before setting it
  /// as a metatable of some object. In particular, the __gc metamethod works only when
  /// this order is followed."
  void applyDefaultMetatable(Value value) {
    if (!_initialized && _interpreter != null) {
      _initialize(_interpreter!);
    }
    final type = getLuaType(value);
    Logger.debugLazy(
      () => 'Determined type for value: $type',
      category: 'Metatables',
    );

    // Tables do not receive a default metatable. Numbers only receive one
    // after debug.setmetatable registers it.
    if (type == 'table' || (type == 'number' && !_numberMetatableEnabled)) {
      Logger.debugLazy(
        () => 'Not applying default metatable to $type - defaults are nil',
        category: 'Metatables',
      );
      return;
    }

    final metatable = getTypeMetatable(type);
    if (metatable != null) {
      Logger.debugLazy(
        () => 'Setting metatable for $type value',
        category: 'Metatables',
      );
      value.setMetatable(metatable.metamethods);
      value.metatableRef = _typeMetatableRefs[type];
    } else {
      Logger.debugLazy(
        () => 'No default metatable found for type: $type',
        category: 'Metatables',
      );
    }
  }
}
