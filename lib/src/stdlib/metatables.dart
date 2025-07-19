// import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/stdlib/lib_string.dart' show StringLib;

import '../../lualike.dart';
import 'lib_string.dart';

/// Handles default metatables and metamethods for built-in types
class MetaTable {
  static final MetaTable _instance = MetaTable._internal();

  bool _initialized = false;
  final Map<String, ValueClass> _typeMetatables = {};
  final Map<String, Value?> _typeMetatableRefs = {};
  bool _numberMetatableEnabled = false;

  factory MetaTable() {
    return _instance;
  }

  MetaTable._internal();

  static void initialize(Interpreter interpreter) {
    _instance._initialize();
  }

  void _initialize() {
    if (_initialized) {
      Logger.debug(
        'MetaTable already initialized, skipping',
        category: 'Metatables',
      );
      return;
    }

    Logger.debug('Initializing MetaTable', category: 'Metatables');

    // String metatable
    _typeMetatables['string'] = ValueClass.create({
      '__len': (List<Object?> args) {
        final str = args[0] as Value;
        Logger.debug(
          'String __len metamethod called for "${str.raw}"',
          category: 'Metatables',
        );
        if (str.raw is LuaString) {
          return Value((str.raw as LuaString).length);
        }
        return Value(str.raw.toString().length);
      },
      '__index': (List<Object?> args) {
        final str = args[0] as Value;
        final key = args[1] as Value;
        Logger.debug(
          'String __index metamethod called for "${str.raw}"[${key.raw}]',
          category: 'Metatables',
        );

        if (key.raw is String) {
          final method = StringLib.functions[key.raw];
          if (method != null) {
            Logger.debug(
              'Found string method: ${key.raw}',
              category: 'Metatables',
            );

            // Return a function that will be called later
            return Value((callArgs) {
              Logger.debug(
                'String method ${key.raw} cal led with ${callArgs.length} arguments',
                category: 'Metatables',
              );

              if (callArgs.isNotEmpty && callArgs.first == str) {
                return method.call(callArgs);
              }

              return method.call([str, ...callArgs]);
            });
          }
        }

        Logger.debug(
          'String method not found: ${key.raw}',
          category: 'Metatables',
        );
        return Value(null);
      },
      '__eq': (List<Object?> args) {
        final a = args[0] as Value;
        final b = args[1] as Value;
        Logger.debug(
          'String __eq metamethod called: "${a.raw}" == "${b.raw}"',
          category: 'Metatables',
        );
        return Value(a == b);
      },
    });
    Logger.debug('String metatable initialized', category: 'Metatables');

    // Number metatable
    _typeMetatables['number'] = ValueClass.create({
      '__add': (List<Object?> args) =>
          Value.wrap(args[0]) + Value.wrap(args[1]),
      '__sub': (List<Object?> args) =>
          Value.wrap(args[0]) - Value.wrap(args[1]),
      '__mul': (List<Object?> args) =>
          Value.wrap(args[0]) * Value.wrap(args[1]),
      '__div': (List<Object?> args) =>
          Value.wrap(args[0]) / Value.wrap(args[1]),
      '__idiv': (List<Object?> args) =>
          Value.wrap(args[0]) ~/ Value.wrap(args[1]),
      '__mod': (List<Object?> args) =>
          Value.wrap(args[0]) % Value.wrap(args[1]),
      '__pow': (List<Object?> args) =>
          Value.wrap(args[0]).exp(Value.wrap(args[1])),
      '__unm': (List<Object?> args) => -Value.wrap(args[0]),
      '__bnot': (List<Object?> args) => ~Value.wrap(args[0]),
      '__band': (List<Object?> args) =>
          Value.wrap(args[0]) & Value.wrap(args[1]),
      '__bor': (List<Object?> args) =>
          Value.wrap(args[0]) | Value.wrap(args[1]),
      '__bxor': (List<Object?> args) =>
          Value.wrap(args[0]) ^ Value.wrap(args[1]),
      '__shl': (List<Object?> args) =>
          Value.wrap(args[0]) << Value.wrap(args[1]),
      '__shr': (List<Object?> args) =>
          Value.wrap(args[0]) >> Value.wrap(args[1]),
      '__eq': (List<Object?> args) =>
          Value(Value.wrap(args[0]) == Value.wrap(args[1])),
      '__lt': (List<Object?> args) =>
          Value(Value.wrap(args[0]) < Value.wrap(args[1])),
      '__le': (List<Object?> args) =>
          Value(Value.wrap(args[0]) <= Value.wrap(args[1])),
    });
    Logger.debug('Number metatable initialized', category: 'Metatables');

    // Table metatable
    _typeMetatables['table'] = ValueClass.create({
      '__len': (List<Object?> args) {
        final table = args[0] as Value;
        Logger.debug(
          'Table __len metamethod called for table:${table.hashCode}',
          category: 'Metatables',
        );
        if (table.raw is Map) {
          // Count only non-nil values
          int count = 0;
          (table.raw as Map).forEach((key, value) {
            if (value != null && (value is! Value || value.raw != null)) {
              count++;
            }
          });
          Logger.debug(
            'Table length calculated: $count',
            category: 'Metatables',
          );
          return Value(count);
        } else if (table.raw is List) {
          return Value((table.raw as List).length);
        }

        throw Exception("attempt to get length of non-table value");
      },
      // Removed '__index' and '__newindex' from default table metatable
      // These should only be present when explicitly set by the user
      '__pairs': (List<Object?> args) {
        final table = args[0] as Value;
        Logger.debug(
          'Table __pairs metamethod called for table:${table.hashCode}',
          category: 'Metatables',
        );
        Logger.debug(
          'Table content: ${(table.raw as Map).toString()}',
          category: 'Metatables',
        );
        if (table.raw is! Map) {
          Logger.debug(
            'Error: Attempt to iterate over non-table value of type ${table.raw.runtimeType}',
            category: 'Metatables',
          );
          throw Exception("attempt to iterate over non-table value");
        }

        // Create a filtered map without nil values
        final map = table.raw as Map;
        Logger.debug(
          'Raw map entries before filtering: ${map.entries.length}',
          category: 'Metatables',
        );
        final filteredEntries = map.entries.where((entry) {
          final value = entry.value;
          final keep =
              !(value == null || (value is Value && value.raw == null));
          Logger.debug(
            'Filter entry: key=${entry.key}, value=${entry.value}, keep=$keep',
            category: 'Metatables',
          );
          return keep;
        }).toList();

        Logger.debug(
          'Table pairs iterator created with ${filteredEntries.length} entries',
          category: 'Metatables',
        );
        for (final entry in filteredEntries) {
          Logger.debug(
            'Entry in filtered list: ${entry.key} -> ${entry.value}',
            category: 'Metatables',
          );
        }

        // Return iterator function, table, and nil
        Logger.debug(
          'Returning iterator function and state',
          category: 'Metatables',
        );
        return Value.multi([
          Value((List<Object?> args) {
            final state = args[0] as Value;
            final k = args[1] as Value;
            Logger.debug(
              'Table pairs iterator called with state:${state.hashCode} key: ${k.raw}',
              category: 'Metatables',
            );

            int foundIndex = -1;
            if (k.raw == null) {
              Logger.debug(
                'Initial call with nil key, returning first entry if available',
                category: 'Metatables',
              );
              foundIndex = 0;
            } else {
              Logger.debug(
                'Looking for entry after key ${k.raw}',
                category: 'Metatables',
              );
              // Find the index of the entry that matches the current key
              for (int i = 0; i < filteredEntries.length; i++) {
                final entry = filteredEntries[i];
                Logger.debug(
                  'Checking entry $i: key=${entry.key}, current key=${k.raw}',
                  category: 'Metatables',
                );
                if (entry.key == k.raw) {
                  foundIndex = i + 1; // Return next entry
                  Logger.debug(
                    'Found matching entry at index $i, will return index $foundIndex next',
                    category: 'Metatables',
                  );
                  break;
                }
              }
            }

            if (foundIndex >= 0 && foundIndex < filteredEntries.length) {
              final entry = filteredEntries[foundIndex];
              Logger.debug(
                'Returning next entry: key=${entry.key}, value=${entry.value}',
                category: 'Metatables',
              );
              return [
                Value(entry.key),
                entry.value is Value ? entry.value : Value(entry.value),
              ];
            }

            Logger.debug(
              'Table pairs iterator finished, no more entries',
              category: 'Metatables',
            );
            return [Value(null)];
          }),
          table,
          Value(null),
        ]);
      },
    });
    Logger.debug('Table metatable initialized', category: 'Metatables');

    // Function metatable
    _typeMetatables['function'] = ValueClass.create({
      '__call': (List<Object?> args) {
        final func = args[0] as Value;
        final callArgs = args.sublist(1);
        Logger.debug(
          'Function __call metamethod called for function:${func.hashCode} with ${callArgs.length} args',
          category: 'Metatables',
        );
        if (func.raw is Function) {
          final result = (func.raw as Function)(callArgs);
          Logger.debug('Function call result: $result', category: 'Metatables');
          return result;
        } else if (func.raw is BuiltinFunction) {
          final result = (func.raw as BuiltinFunction).call(callArgs);
          Logger.debug('Function call result: $result', category: 'Metatables');
          return result;
        }

        throw Exception("attempt to call non-function value");
      },
    });
    Logger.debug('Function metatable initialized', category: 'Metatables');

    // Coroutine metatable
    _typeMetatables['thread'] = ValueClass.create({
      '__tostring': (List<Object?> args) {
        final thread = args[0] as Value;
        final coroutine = thread.raw as Coroutine;
        Logger.debug(
          'Thread __tostring metamethod called for coroutine:${thread.hashCode}',
          category: 'Metatables',
        );
        return Value('thread: ${thread.hashCode} [${coroutine.status}]');
      },
      '__gc': (List<Object?> args) {
        final thread = args[0] as Value;
        final coroutine = thread.raw as Coroutine;
        Logger.debug(
          'Thread __gc metamethod called for coroutine:${thread.hashCode}',
          category: 'Metatables',
        );

        // Close the coroutine when it's collected
        coroutine.markAsDead();
        return Value(null);
      },
    });
    Logger.debug('Thread metatable initialized', category: 'Metatables');
    // Register coroutine metatable as a default for thread objects
    registerDefaultMetatable('thread', _typeMetatables['thread']!);

    // Userdata metatable
    _typeMetatables['userdata'] = ValueClass.create({
      '__tostring': (List<Object?> args) {
        final userdata = args[0] as Value;
        Logger.debug(
          'Userdata __tostring metamethod called for userdata:${userdata.hashCode}',
          category: 'Metatables',
        );
        return Value('userdata: ${userdata.hashCode}');
      },
      '__len': (List<Object?> args) {
        final table = args[0] as Value;
        Logger.debug(
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
        Logger.debug(
          'Userdata __gc metamethod called for userdata:${userdata.hashCode}',
          category: 'Metatables',
        );
        return Value(null);
      },
    });
    Logger.debug('Userdata metatable initialized', category: 'Metatables');

    _initialized = true;
    Logger.debug(
      'All default metatables initialized successfully',
      category: 'Metatables',
    );
  }

  /// Get metatable for a given type
  ValueClass? getTypeMetatable(String type) {
    Logger.debug('Getting type metatable for: $type', category: 'Metatables');
    return _typeMetatables[type];
  }

  /// Register a default metatable for a type. If [metatable] is null, any
  /// existing default metatable for the type will be removed.
  void registerDefaultMetatable(
    String type,
    ValueClass? metatable, [
    Value? original,
  ]) {
    Logger.debug(
      'Registering default metatable for type: $type',
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

  String _determineType(Object? value) {
    return switch (value) {
      null => 'nil',
      String() => 'string',
      LuaString() => 'string',
      num() => 'number',
      BigInt() => 'number',
      bool() => 'boolean',
      Function() => 'function',
      BuiltinFunction() => 'function',
      Map() => 'table',
      List() => 'table',
      Coroutine() => 'thread',
      _ => 'userdata',
    };
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
    if (!_initialized) {
      _initialize();
    }
    final type = _determineType(value.raw);
    Logger.debug('Determined type for value: $type', category: 'Metatables');

    // Tables do not receive a default metatable. Numbers only receive one
    // after debug.setmetatable registers it.
    if (type == 'table' || (type == 'number' && !_numberMetatableEnabled)) {
      Logger.debug(
        'Not applying default metatable to $type - defaults are nil',
        category: 'Metatables',
      );
      return;
    }

    final metatable = getTypeMetatable(type);
    if (metatable != null) {
      Logger.debug('Setting metatable for $type value', category: 'Metatables');
      value.setMetatable(metatable.metamethods);
      value.metatableRef = _typeMetatableRefs[type];
    } else {
      Logger.debug(
        'No default metatable found for type: $type',
        category: 'Metatables',
      );
    }
  }
}
