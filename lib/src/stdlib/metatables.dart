// import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/stdlib/lib_string.dart' show StringLib;

import '../../lualike.dart';
import 'lib_string.dart';

/// Handles default metatables and metamethods for built-in types
class MetaTable {
  static final MetaTable _instance = MetaTable._internal();
  static Interpreter? _interpreter;

  bool _initialized = false;
  final Map<String, ValueClass> _typeMetatables = {};
  final List<Value> _finalizationList = [];

  factory MetaTable() {
    return _instance;
  }

  MetaTable._internal();

  static void initialize(Interpreter interpreter) {
    _interpreter = interpreter;
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
      '__concat': (List<Object?> args) {
        final a = args[0] as Value;
        final b = args[1] as Value;
        Logger.debug(
          'String __concat metamethod called: "${a.raw}" .. "${b.raw}"',
          category: 'Metatables',
        );

        // For better interop, return Dart strings unless LuaString is needed
        if (a.raw is LuaString || b.raw is LuaString) {
          // If either operand is a LuaString, preserve byte-level operations
          final aStr = a.raw is LuaString
              ? (a.raw as LuaString)
              : LuaString.fromDartString(a.raw.toString());
          final bStr = b.raw is LuaString
              ? (b.raw as LuaString)
              : LuaString.fromDartString(b.raw.toString());
          return Value(aStr + bStr);
        } else {
          // Both operands are normal types, return Dart string
          return Value(a.raw.toString() + b.raw.toString());
        }
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
                'String method ${key.raw} called with ${callArgs.length} arguments',
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
      '__gc': (List<Object?> args) {
        final table = args[0] as Value;
        Logger.debug(
          'Table __gc metamethod called for table:${table.hashCode}',
          category: 'Metatables',
        );

        // Track finalization in the finalized table
        final finalized = _interpreter!.globals.get('finalized');
        if (finalized == null) {
          Logger.debug(
            'Finalized table not found, skipping finalization',
            category: 'Metatables',
          );
          _interpreter!.globals.define(
            'finalized',
            ValueClass.table({table.hashCode.toString(): Value(true)}),
          );
          return Value(null);
        }
        if (finalized is Value) {
          finalized[Value(table.hashCode.toString())] = Value(true);
        }

        return Value(null);
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

  /// Register a default metatable for a type
  void registerDefaultMetatable(String type, ValueClass metatable) {
    Logger.debug(
      'Registering default metatable for type: $type',
      category: 'Metatables',
    );
    _typeMetatables[type] = metatable;
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

    // In Lua, tables don't have default metatables - they only get metatables when explicitly assigned
    if (type == 'table') {
      Logger.debug(
        'Not applying default metatable to table - tables have no default metatable',
        category: 'Metatables',
      );
      return;
    }

    final metatable = getTypeMetatable(type);
    if (metatable != null) {
      Logger.debug('Setting metatable for $type value', category: 'Metatables');
      value.setMetatable(metatable.metamethods);

      // Mark for finalization if it has a __gc metamethod
      if (metatable.metamethods.containsKey('__gc')) {
        Logger.debug(
          'Found __gc metamethod for type $type, marking for finalization',
          category: 'Metatables',
        );
        markForFinalization(value);
      } else {
        Logger.debug(
          'No __gc metamethod found for type $type',
          category: 'Metatables',
        );
      }
    } else {
      Logger.debug(
        'No default metatable found for type: $type',
        category: 'Metatables',
      );
    }
  }

  /// Marks an object for finalization if it has a __gc metamethod.
  ///
  /// This implements the behavior described in section 2.5.3 of the Lua reference manual:
  /// "For an object (table or userdata) to be finalized when collected, you must
  /// mark it for finalization. You mark an object for finalization when you set
  /// its metatable and the metatable has a __gc metamethod."
  ///
  /// Objects marked for finalization are added to a list and their finalizers
  /// will be called during the next garbage collection cycle.
  void markForFinalization(Value value) {
    Logger.debug(
      'Checking if object ${value.hashCode} needs finalization',
      category: 'Metatables',
    );

    if (value.metatable?.containsKey('__gc') ?? false) {
      Logger.debug(
        'Object ${value.hashCode} has __gc metamethod, marking for finalization',
        category: 'Metatables',
      );
      _finalizationList.add(value);
      Logger.debug(
        'Added object ${value.hashCode} to finalization list (size: ${_finalizationList.length})',
        category: 'Metatables',
      );
    } else {
      Logger.debug(
        'Object ${value.hashCode} has no __gc metamethod',
        category: 'Metatables',
      );
    }
  }

  /// Runs finalizers for objects marked for finalization.
  ///
  /// This implements the behavior described in section 2.5.3 of the Lua reference manual:
  /// "When a marked object becomes dead, it is not collected immediately by the garbage collector.
  /// Instead, Lua puts it in a list. After the collection, Lua goes through that list. For each
  /// object in the list, it checks the object's __gc metamethod: If it is present, Lua calls it
  /// with the object as its single argument."
  ///
  /// The finalizers are called in reverse order of marking, as specified in the manual:
  /// "At the end of each garbage-collection cycle, the finalizers are called in the reverse
  /// order that the objects were marked for finalization, among those collected in that cycle."
  void runFinalizers() {
    Logger.debug(
      'Running finalizers for ${_finalizationList.length} objects',
      category: 'Metatables',
    );

    // Process finalizers in reverse order
    for (var i = _finalizationList.length - 1; i >= 0; i--) {
      final obj = _finalizationList[i];
      Logger.debug(
        'Processing finalizer for object ${obj.hashCode}',
        category: 'Metatables',
      );

      final finalizer = obj.metatable?['__gc'];
      if (finalizer != null) {
        try {
          Logger.debug(
            'Running __gc metamethod for object ${obj.hashCode}',
            category: 'Metatables',
          );
          finalizer([obj]);

          // Track finalized objects in the finalized table
          final finalized = _interpreter!.globals.get('finalized') as Value;
          if (finalized.raw is Map) {
            Logger.debug(
              'Marking object ${obj.hashCode} as finalized',
              category: 'Metatables',
            );
            (finalized.raw as Map)[obj.hashCode.toString()] = Value(true);
          }
        } catch (e, s) {
          // As per section 2.5.3: "Any error while running a finalizer generates a warning;
          // the error is not propagated."
          Logger.error(
            'Error in finalizer for object ${obj.hashCode}: $e',
            error: e,
            trace: s,
            category: 'Metatables',
          );
        }
      }
    }

    Logger.debug('Clearing finalization list', category: 'Metatables');
    _finalizationList.clear();
  }
}
