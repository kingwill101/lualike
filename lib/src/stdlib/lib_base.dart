import 'dart:async';
import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/coroutine.dart' show Coroutine;
import 'package:lualike/src/number.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:path/path.dart' as path;

/// Built-in function to retrieve the metatable of a value.
class GetMetatableFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("getmetatable requires an argument");
    }

    final value = args[0];
    if (value is! Value) {
      return Value(null);
    }

    // Check for __metatable field first
    final metatable = value.getMetatable();
    if (metatable == null) {
      return Value(null);
    }

    if (metatable.containsKey('__metatable')) {
      return metatable['__metatable'];
    }

    // Return the actual metatable
    return Value(metatable);
  }
}

/// Built-in function to set the metatable of a table value.
/// Only values wrapping a Map (table) can have a metatable set.
class SetMetatableFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) {
      throw Exception("setmetatable expects two arguments");
    }
    var table = args[0];
    var metatable = args[1];

    if (table is! Value || table.raw is! Map) {
      throw Exception("setmetatable only supported for table values");
    }

    if (metatable is Value) {
      if (metatable.raw is Map) {
        // Convert the map to the right type without using 'as'
        final Map<String, dynamic> mtMap = {};
        (metatable.raw as Map).forEach((key, value) {
          if (key is String) {
            mtMap[key] = value;
          } else {
            mtMap[key.toString()] = value;
          }
        });
        table.setMetatable(mtMap);
        return table;
      } else if (metatable.raw == null) {
        // Setting nil metatable removes the metatable
        table.metatable = null;
        return table;
      }
    }

    throw Exception("metatable must be a table or nil");
  }
}

/// Built-in function to set a table field without invoking metamethods.
class RawSetFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 3) {
      throw Exception("rawset expects three arguments (table, key, value)");
    }

    final table = args[0];
    if (table is! Value || table.raw is! Map) {
      throw Exception("rawset: first argument must be a table");
    }

    final key = args[1] is Value ? (args[1] as Value).raw : args[1];
    final value = args[2] is Value ? args[2] : Value(args[2]);

    (table.raw as Map)[key] = value;
    return table;
  }
}

class AssertFunction implements BuiltinFunction {
  final Interpreter? vm;

  AssertFunction([this.vm]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("assert requires at least one argument");
    final condition = args[0];

    bool isTrue;
    if (condition is Value) {
      if (condition.raw is bool) {
        isTrue = condition.raw as bool;
      } else {
        isTrue = condition.raw != null;
      }
    } else if (condition is bool) {
      isTrue = condition;
    } else {
      isTrue = condition != null;
    }

    Logger.debug(
      'AssertFunction: Assertion condition: $condition, evaluated to: $isTrue',
      category: 'Base',
    );

    if (!isTrue) {
      final message = args.length > 1
          ? (args[1] as Value).raw.toString()
          : "assertion failed! condition: ${condition.raw}";
      Logger.debug(
        'AssertFunction: Assertion failed with message: $message',
        category: 'Base',
      );
      if (vm?.callStack.current?.callNode != null) {
        throw LuaError.fromNode(vm!.callStack.current!.callNode!, message);
      }
      throw LuaError(message);
    }

    Logger.debug(
      'AssertFunction: Assertion passed, returning ${args.length > 1 ? args : args[0]}',
      category: 'Base',
    );

    // Return all arguments passed to assert
    return args.length > 1 ? args : args[0];
  }
}

// Static flag to track if an error is already being reported
bool _errorReporting = false;

class ErrorFunction implements BuiltinFunction {
  final Interpreter? vm;

  ErrorFunction([this.vm]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("error requires a message");

    // Get the error value
    final errorValue = args[0] as Value;

    // If the error value is a table, preserve it
    if (errorValue.raw is Map) {
      throw errorValue; // Throw the Value directly instead of converting to Exception
    }

    final message = errorValue.raw.toString();
    final level = args.length > 1 ? (args[1] as Value).raw as int : 1;

    // If we're already reporting an error, just throw the exception
    // without calling reportError again
    if (_errorReporting) {
      throw Exception(message);
    }

    // Set the flag to indicate we're reporting an error
    _errorReporting = true;

    try {
      // If we have access to the VM, use its call stack for better error reporting
      if (vm != null) {
        // Let the VM handle the error reporting with proper stack trace
        vm!.reportError(message);
        // This will never be reached, but needed for type safety
        throw Exception(message);
      } else {
        // Get the current script path if available
        String scriptPath = "unknown";
        if (vm != null) {
          // Try to get the script path from the environment first
          final scriptPathValue = vm!.globals.get('_SCRIPT_PATH');
          if (scriptPathValue is Value && scriptPathValue.raw != null) {
            scriptPath = scriptPathValue.raw.toString();
          } else if (vm!.currentScriptPath != null) {
            scriptPath = vm!.currentScriptPath!;
          }

          // Extract just the filename for display, like Lua does
          scriptPath = scriptPath.split('/').last;
        }

        // Format error message like Lua CLI
        final errorMsg = "$scriptPath: $message";

        // Generate a simple stack trace based on level
        final trace = StringBuffer(errorMsg);
        if (level > 0) {
          trace.writeln();
          trace.writeln("stack traceback:");
          for (var i = 0; i < level; i++) {
            trace.writeln("\t$scriptPath:${i + 1}: in function '?'");
          }
        }

        throw Exception(trace.toString());
      }
    } finally {
      // Reset the flag
      _errorReporting = false;
    }
  }
}

class IPairsFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("ipairs requires a table");
    final table = args[0] as Value;
    if (table.raw is! Map) throw Exception("ipairs requires a table");

    Logger.debug(
      'IPairsFunction: Creating iterator for table: ${table.raw}',
      category: 'Base',
    );

    // Create a function that returns the next index and value
    final iteratorFunction = Value((List<Object?> iterArgs) {
      if (iterArgs.length < 2) {
        throw Exception("iterator requires a table and an index");
      }

      final t = iterArgs[0] as Value;

      if (t.raw is! Map) {
        throw Exception("iterator requires a table as first argument");
      }

      final map = t.raw as Map;

      // The second argument must be a number
      if (iterArgs[1] is! Value || (iterArgs[1] as Value).raw is! num) {
        throw Exception("iterator index must be a number");
      }

      final index = (iterArgs[1] as Value).raw as num;

      Logger.debug(
        'IPairsFunction.iterator: Called with index: $index',
        category: 'Base',
      );

      // In Lua, ipairs iterates over consecutive integer keys starting from 1
      // It stops at the first nil value or non-integer key
      final nextIndex = index + 1;

      // Check if the next index exists in the table
      if (!map.containsKey(nextIndex)) {
        Logger.debug(
          'IPairsFunction.iterator: No next index, returning nil',
          category: 'Base',
        );
        return Value(null);
      }

      // Get the value at the next index
      final value = map[nextIndex];

      // If the value is nil, stop iteration
      if (value == null || (value is Value && value.raw == null)) {
        Logger.debug(
          'IPairsFunction.iterator: Value at index $nextIndex is nil, returning nil',
          category: 'Base',
        );
        return Value(null);
      }

      final nextValue = value is Value ? value : Value(value);

      Logger.debug(
        'IPairsFunction.iterator: Found next index: $nextIndex, value: $nextValue',
        category: 'Base',
      );

      // Return the index and value as multiple values
      return Value.multi([Value(nextIndex), nextValue]);
    });

    Logger.debug(
      'IPairsFunction: Returning iterator components via Value.multi',
      category: 'Base',
    );

    // Return iterator function, table, and initial control value (0) using Value.multi
    // This matches Lua's behavior: ipairs(t) returns iterator, t, 0
    return Value.multi([iteratorFunction, table, Value(0)]);
  }
}

class PrintFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final outputs = <String>[];

    for (final arg in args) {
      if (arg == null) {
        outputs.add("nil");
        continue;
      }

      final value = arg as Value;

      // Check for __tostring metamethod first
      final tostring = value.getMetamethod("__tostring");
      if (tostring != null) {
        final result = tostring([value]);
        outputs.add((result as Value).raw.toString());
        continue;
      }

      // Handle basic types
      if (value.raw == null) {
        outputs.add("nil");
      } else if (value.raw is bool) {
        outputs.add(value.raw.toString());
      } else if (value.raw is num) {
        // Use proper number formatting
        outputs.add(
          value.raw is int
              ? value.raw.toString()
              : (value.raw as double).toString(),
        );
      } else if (value.raw is String) {
        outputs.add(value.raw.toString());
      } else if (value.raw is Map) {
        outputs.add("table: ${value.raw.hashCode}");
      } else if (value.raw is Function || value is BuiltinFunction) {
        outputs.add("function: ${value.hashCode}");
      } else {
        outputs.add(value.raw.toString());
      }
    }

    // Use IOLib's defaultOutput instead of direct stdout access
    final outputStr = "${outputs.join("\t")}\n";

    IOLib.defaultOutput.write(outputStr);

    // Use our LuaFile abstraction for writing
    // Logger.outputSink?.call(outputStr);

    return Value(null);
  }
}

class TypeFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("type requires an argument");
    final value = args[0] as Value;

    if (value.raw == null) return Value("nil");
    if (value.raw is bool) return Value("boolean");
    if (value.raw is num) return Value("number");
    if (value.raw is String) return Value("string");
    if (value.raw is Coroutine) return Value("thread");
    if (value.raw is Map) return Value("table");
    if (value.raw is Function || value is BuiltinFunction) {
      return Value("function");
    }

    return Value("userdata"); // Default for other types
  }
}

class ToNumberFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("tonumber requires an argument");
    }

    final value = args[0] as Value;

    if (value.raw is String) {
      try {
        return Value(LuaNumberParser.parse(value.raw as String));
      } on FormatException {
        return Value(null);
      }
    } else if (value.raw is num) {
      return value;
    } else if (value.raw is BigInt) {
      return Value((value.raw as BigInt).toInt());
    }

    return Value(null);
  }
}

class ToStringFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("tostring requires an argument");
    final value = args[0] as Value;

    // Check for __tostring metamethod
    final tostring = value.getMetamethod("__tostring");
    if (tostring != null) {
      if (tostring is Function) {
        final result = tostring([value]);
        if (result is Value) {
          return result;
        }
      }
    }

    // Handle basic types directly
    if (value.raw == null) return Value("nil");
    if (value.raw is bool) {
      // Special handling for boolean values
      final boolStr = value.raw.toString();
      return Value(boolStr);
    }
    if (value.raw is num) return Value(value.raw.toString());
    if (value.raw is String) return Value(value.raw.toString());
    if (value.raw is Map) return Value("table: ${value.raw.hashCode}");
    if (value.raw is Function || value is BuiltinFunction) {
      return Value("function: ${value.hashCode}");
    }

    return Value(value.raw.toString());
  }
}

class SelectFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("select requires at least one argument");
    final index = args[0] as Value;

    if (index.raw is String && index.raw == "#") {
      return Value(args.length - 1);
    }

    final idx = index.raw as int;
    if (idx <= 0) throw Exception("index out of range");

    if (idx >= args.length) return Value(null);
    return args.sublist(idx);
  }
}

class LoadFunction implements BuiltinFunction {
  final Interpreter vm;

  LoadFunction(this.vm);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("load() requires a string or function argument");
    }

    String source;
    String chunkname;

    if (args[0] is Value) {
      if ((args[0] as Value).raw is String) {
        // Load from string
        source = (args[0] as Value).raw as String;
      } else if ((args[0] as Value).raw is Function) {
        // Load from reader function
        final chunks = <String>[];
        final reader = (args[0] as Value).raw as Function;
        while (true) {
          final chunk = reader([]);
          if (chunk == null || (chunk is Value && chunk.raw == null)) break;
          chunks.add(chunk.toString());
        }
        source = chunks.join();
      } else if ((args[0] as Value).raw is List<int>) {
        // Load from binary chunk
        final bytes = (args[0] as Value).raw as List<int>;
        source = String.fromCharCodes(bytes);
      } else {
        throw Exception(
          "load() first argument must be string, function or binary",
        );
      }
      chunkname = args.length > 1
          ? (args[1] as Value).raw as String
          : "=(load)";
    } else {
      throw Exception("load() first argument must be a string");
    }

    try {
      final ast = parse(source);
      return Value((List<Object?> callArgs) {
        try {
          final result = vm.run(ast.statements);
          return result;
        } catch (e) {
          throw Exception("Error executing loaded chunk '$chunkname': $e");
        }
      });
    } catch (e) {
      return [Value(null), Value("Error parsing source code: $e")];
    }
  }
}

class DoFileFunction implements BuiltinFunction {
  final Interpreter vm;

  DoFileFunction(this.vm);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("dofile requires a filename");
    final filename = (args[0] as Value).raw.toString();

    // Load source using FileManager
    final source = vm.fileManager.loadSource(filename);
    if (source == null) {
      throw Exception("Cannot open file '$filename'");
    }

    try {
      // Parse content into AST
      final ast = parse(source);

      // Execute in current VM context
      final result = vm.run(ast.statements);

      // Return result or nil if no result
      return result;
    } catch (e) {
      throw Exception("Error in dofile('$filename'): $e");
    }
  }
}

class GetmetaFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) return Value(null);
    final obj = args[0];
    if (obj is Value) {
      return Value(obj.getMetatable());
    }
    return Value(null);
  }
}

class SetmetaFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) throw Exception("setmetatable expects 2 arguments");
    final table = args[0];
    final meta = args[1];

    if (table is! Value || meta is! Value) {
      throw Exception("setmetatable requires table and metatable arguments");
    }

    if (meta.raw is Map) {
      Logger.debug(
        "setmetatable called on table with raw: ${table.raw} and meta: ${meta.raw}",
        category: "Metatables",
      );
      table.setMetatable((meta.raw as Map).cast());
      Logger.debug(
        "Metatable set. New metatable: ${table.getMetatable()}",
        category: "Metatables",
      );
      return table;
    }
    throw Exception("metatable must be a table");
  }
}

class LoadfileFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final filename = args.isNotEmpty ? (args[0] as Value).raw.toString() : null;
    //mode
    final _ = args.length > 1 ? (args[1] as Value).raw.toString() : 'bt';

    try {
      final source = filename == null
          ? stdin.readLineSync() ??
                "" // Read from stdin if no filename
          : File(filename).readAsStringSync();

      final ast = parse(source);
      return Value((List<Object?> callArgs) {
        final vm = Interpreter();
        try {
          return vm.run(ast.statements);
        } catch (e) {
          throw Exception("Error executing loaded chunk: $e");
        }
      });
    } catch (e) {
      return Value(null);
    }
  }
}

class NextFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("next requires a table argument");
    final table = args[0] as Value;
    if (table.raw is! Map) throw Exception("next requires a table argument");
    final map = table.raw as Map;

    // Filter out nil values from the map
    final filteredEntries = map.entries.where((entry) {
      final value = entry.value;
      return !(value == null || (value is Value && value.raw == null));
    }).toList();

    final key = args.length > 1 ? (args[1] as Value).raw : null;
    if (key == null) {
      if (filteredEntries.isEmpty) return Value(null);
      final firstEntry = filteredEntries.first;
      return Value.multi([
        Value(firstEntry.key),
        firstEntry.value is Value ? firstEntry.value : Value(firstEntry.value),
      ]);
    }

    bool found = false;
    for (final entry in filteredEntries) {
      if (found) {
        return Value.multi([
          Value(entry.key),
          entry.value is Value ? entry.value : Value(entry.value),
        ]);
      }
      if (entry.key == key) found = true;
    }
    return Value(null);
  }
}

class PCAllFunction implements BuiltinFunction {
  final Interpreter interpreter;

  PCAllFunction(this.interpreter);

  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("pcall requires a function");
    final func = args[0] as Value;
    final callArgs = args.sublist(1);

    // Set non-yieldable state for this protected call
    final previousYieldable = interpreter.isYieldable;
    interpreter.isYieldable = false;

    try {
      Object? callResult;
      if (func.raw is BuiltinFunction) {
        callResult = (func.raw as BuiltinFunction).call(callArgs);
      } else {
        callResult = func.raw(callArgs);
      }

      // Handle both synchronous and asynchronous results
      if (callResult is Future) {
        try {
          final awaitedResult = await callResult;
          return [
            Value(true),
            awaitedResult is Value ? awaitedResult : Value(awaitedResult),
          ];
        } catch (e) {
          return [Value(false), Value(e.toString())];
        }
      } else {
        return [
          Value(true),
          callResult is Value ? callResult : Value(callResult),
        ];
      }
    } catch (e) {
      return [Value(false), Value(e.toString())];
    } finally {
      // Restore previous yieldable state
      interpreter.isYieldable = previousYieldable;
    }
  }
}

class RawEqualFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) throw Exception("rawequal requires two arguments");
    final v1 = args[0] as Value;
    final v2 = args[1] as Value;
    return Value(v1.raw == v2.raw);
  }
}

class RawLenFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("rawlen requires an argument");
    final value = args[0] as Value;
    if (value.raw is String) return Value(value.raw.toString().length);
    if (value.raw is Map) return Value((value.raw as Map).length);
    throw Exception("rawlen requires a string or table");
  }
}

class WarnFunction implements BuiltinFunction {
  bool _enabled = true;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) return Value(null);

    final firstArg = args[0] as Value;
    if (firstArg.raw is String) {
      final message = firstArg.raw.toString();

      // Handle control messages
      if (message == "@off") {
        _enabled = false;
        return Value(null);
      } else if (message == "@on") {
        _enabled = true;
        return Value(null);
      }
    }

    if (_enabled) {
      final messages = args
          .map((arg) {
            final value = arg as Value;
            return value.raw?.toString() ?? "nil";
          })
          .join("\t");

      stderr.writeln("Lua warning: $messages");
      stderr.flush();
    }

    return Value(null);
  }
}

class XPCallFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError("xpcall requires at least two arguments");
    }
    final func = args[0] as Value;
    final msgh = args[1] as Value;
    final callArgs = args.sublist(2);

    if (func.raw is! Function) {
      throw LuaError.typeError(
        "xpcall requires a function as its first argument",
      );
    }

    if (msgh.raw is! Function) {
      throw LuaError.typeError(
        "xpcall requires a function as its second argument",
      );
    }

    try {
      final result = func.raw as Function;
      final callResult = result(callArgs);

      // Handle both synchronous and asynchronous results
      if (callResult is Future) {
        try {
          final awaitedResult = await callResult;
          // Return true (success) followed by the result
          if (awaitedResult is List && awaitedResult.isNotEmpty) {
            return [Value(true), ...awaitedResult];
          } else {
            return [
              Value(true),
              awaitedResult is Value ? awaitedResult : Value(awaitedResult),
            ];
          }
        } catch (e) {
          // Call the message handler with the error
          try {
            final errorHandler = msgh.raw as Function;
            // Unwrap double-wrapped Values before passing to error handler
            final errorValue = e is Value
                ? (e.raw is Value ? e.raw : e)
                : Value(e.toString());
            final handlerResult = errorHandler([errorValue]);

            if (handlerResult is Future) {
              try {
                final awaitedHandlerResult = await handlerResult;
                return [
                  Value(false),
                  awaitedHandlerResult is Value
                      ? awaitedHandlerResult
                      : Value(awaitedHandlerResult),
                ];
              } catch (e2) {
                return [Value(false), Value("Error in error handler: $e2")];
              }
            } else {
              return [
                Value(false),
                handlerResult is Value ? handlerResult : Value(handlerResult),
              ];
            }
          } catch (e2) {
            return [Value(false), Value("Error in error handler: $e2")];
          }
        }
      } else {
        // Handle synchronous result
        if (callResult is List && callResult.isNotEmpty) {
          return [Value(true), ...callResult];
        } else {
          return [
            Value(true),
            callResult is Value ? callResult : Value(callResult),
          ];
        }
      }
    } catch (e) {
      // Call the message handler with the error
      try {
        final errorHandler = msgh.raw as Function;
        // Unwrap double-wrapped Values before passing to error handler
        final errorValue = e is Value
            ? (e.raw is Value ? e.raw : e)
            : Value(e.toString());
        final handlerResult = errorHandler([errorValue]);

        if (handlerResult is Future) {
          try {
            final awaitedHandlerResult = await handlerResult;
            return [
              Value(false),
              awaitedHandlerResult is Value
                  ? awaitedHandlerResult
                  : Value(awaitedHandlerResult),
            ];
          } catch (e2) {
            return [Value(false), Value("Error in error handler: $e2")];
          }
        } else {
          return [
            Value(false),
            handlerResult is Value ? handlerResult : Value(handlerResult),
          ];
        }
      } catch (e2) {
        return [Value(false), Value("Error in error handler: $e2")];
      }
    }
  }
}

class CollectGarbageFunction implements BuiltinFunction {
  final Interpreter vm;
  String _currentMode = "incremental"; // Default mode

  CollectGarbageFunction(this.vm);

  @override
  Object? call(List<Object?> args) {
    final option = args.isNotEmpty
        ? (args[0] as Value).raw.toString()
        : "collect";
    Logger.debug('CollectGarbageFunction: option: $option', category: 'Base');

    switch (option) {
      case "collect":
        // "collect": Performs a full garbage-collection cycle
        vm.gc.majorCollection(vm.getRoots());
        return Value(true);

      case "count":
        // "count": Returns the total memory in use by Lua in Kbytes
        // The value has a fractional part, so that it multiplied by 1024
        // gives the exact number of bytes in use by Lua
        final count = vm.gc.estimateMemoryUse() / 1024.0;
        return Value.multi([
          Value(count),
          Value(vm.gc.minorMultiplier / 100.0),
        ]);

      case "step":
        // "step": Performs a garbage-collection step
        // The step "size" is controlled by arg
        // With a zero value, the collector will perform one basic (indivisible) step
        // For non-zero values, the collector will perform as if that amount of memory
        // (in Kbytes) had been allocated by Lua
        final stepSize = args.length > 1 ? (args[1] as Value).raw as num : 0;
        if (stepSize == 0) {
          vm.gc.minorCollection(vm.getRoots());
        } else {
          vm.gc.simulateAllocation((stepSize * 1024).toInt());
        }
        // Returns true if the step finished a collection cycle
        return Value(vm.gc.isCollectionCycleComplete());

      case "incremental":
        // "incremental": Change the collector mode to incremental
        // Can be followed by three numbers:
        // - the garbage-collector pause
        // - the step multiplier
        // - the step size
        // A zero means to not change that value
        final oldMode = _currentMode;
        _currentMode = "incremental";

        if (args.length > 1) {
          vm.gc.majorMultiplier = (args[1] as Value).raw as int;
        }
        if (args.length > 2) {
          vm.gc.minorMultiplier = (args[2] as Value).raw as int;
        }
        if (args.length > 3) vm.gc.stepSize = (args[3] as Value).raw as int;
        return Value(oldMode);

      case "generational":
        // "generational": Change the collector mode to generational
        // Can be followed by two numbers:
        // - the garbage-collector minor multiplier
        // - the major multiplier
        // A zero means to not change that value
        final oldMode = _currentMode;
        _currentMode = "generational";

        if (args.length > 1) {
          vm.gc.minorMultiplier = (args[1] as Value).raw as int;
        }
        if (args.length > 2) {
          vm.gc.majorMultiplier = (args[2] as Value).raw as int;
        }
        return Value(oldMode);

      case "isrunning":
        // "isrunning": Returns a boolean that tells whether the collector
        // is running (i.e., not stopped)
        return Value(!vm.gc.isStopped);

      case "stop":
        // "stop": Stops automatic execution of the garbage collector
        // The collector will run only when explicitly invoked, until a call to restart it
        vm.gc.stop();
        return Value(true);

      case "restart":
        // "restart": Restarts automatic execution of the garbage collector
        vm.gc.start();
        return Value(true);

      default:
        throw Exception("invalid option for collectgarbage: $option");
    }
  }
}

class RawGetFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("rawget requires table and index arguments");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw Exception("rawget requires a table as first argument");
    }

    final key = args[1] as Value;
    final map = table.raw as Map;

    // Direct table access without metamethods
    final value = map[key.raw];
    return value is Value ? value : Value(value);
  }
}

class PairsFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("pairs requires a table argument");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw Exception("pairs requires a table argument");
    }

    Logger.debug(
      'PairsFunction: Creating iterator for table: ${table.raw}',
      category: 'Base',
    );

    final meta = table.getMetatable();
    if (meta != null && meta.containsKey("__pairs")) {
      Logger.debug('PairsFunction: Using __pairs metamethod', category: 'Base');
      // Use metamethod if available
      final pairsFn = meta["__pairs"];

      if (pairsFn is Value) {
        Logger.debug(
          'PairsFunction: __pairs is a Value, unwrapping',
          category: 'Base',
        );
        if (pairsFn.raw is Function) {
          Logger.debug(
            'PairsFunction: Calling __pairs function',
            category: 'Base',
          );
          final result = (pairsFn.raw as Function)([table]);
          Logger.debug(
            'PairsFunction: __pairs returned: $result',
            category: 'Base',
          );
          return result;
        }
      } else if (pairsFn is Function) {
        Logger.debug(
          'PairsFunction: Calling __pairs function directly',
          category: 'Base',
        );
        final result = pairsFn([table]);
        Logger.debug(
          'PairsFunction: __pairs returned: $result',
          category: 'Base',
        );
        return result;
      }

      Logger.debug(
        'PairsFunction: __pairs is not callable, falling back to default',
        category: 'Base',
      );
    }

    // Create a filtered copy of the table without nil values
    final filteredTable = <dynamic, dynamic>{};
    final map = table.raw as Map;
    map.forEach((key, value) {
      if (!(value == null || (value is Value && value.raw == null))) {
        filteredTable[key] = value;
      }
    });

    // Create a Value wrapper for the filtered table to use in the iterator
    final filteredTableValue = Value(filteredTable);

    // Create the iterator function - this is essentially the 'next' function
    final iteratorFunction = Value((List<Object?> iterArgs) {
      if (iterArgs.length < 2) {
        throw Exception("iterator requires a table and a key");
      }

      // We ignore the original table passed in iterArgs[0] and use our filtered table instead
      final k = iterArgs[1] as Value;

      Logger.debug(
        'PairsFunction.iterator: Called with key: ${k.raw}',
        category: 'Base',
      );

      // If key is nil, return the first key-value pair
      if (k.raw == null) {
        if (filteredTable.isEmpty) {
          Logger.debug(
            'PairsFunction.iterator: Empty table or no non-nil values, returning nil',
            category: 'Base',
          );
          return Value(null);
        }

        // Get the first entry
        final entry = filteredTable.entries.first;
        final nextKey = Value(entry.key);
        final nextValue = entry.value is Value
            ? entry.value
            : Value(entry.value);

        Logger.debug(
          'PairsFunction.iterator: First entry - key: ${nextKey.raw}, value: $nextValue',
          category: 'Base',
        );

        return Value.multi([nextKey, nextValue]);
      }

      // Find the key in the filtered entries
      bool foundKey = false;
      MapEntry? nextEntry;

      // Iterate through entries to find the key and get the next entry
      for (final entry in filteredTable.entries) {
        if (foundKey) {
          nextEntry = entry;
          break;
        }

        if (entry.key == k.raw) {
          foundKey = true;
        }
      }

      // If we found the next entry, return it
      if (nextEntry != null) {
        final nextKey = Value(nextEntry.key);
        final nextValue = nextEntry.value is Value
            ? nextEntry.value
            : Value(nextEntry.value);

        Logger.debug(
          'PairsFunction.iterator: Next entry - key: ${nextKey.raw}, value: $nextValue',
          category: 'Base',
        );

        return Value.multi([nextKey, nextValue]);
      }

      // If we didn't find the next entry, return nil
      Logger.debug(
        'PairsFunction.iterator: No more entries, returning nil',
        category: 'Base',
      );

      return Value(null);
    });

    Logger.debug(
      'PairsFunction: Returning iterator components via Value.multi',
      category: 'Base',
    );

    // Return iterator function, filtered table, and nil as initial key using Value.multi
    // This matches Lua's behavior: pairs(t) returns next, t, nil
    return Value.multi([iteratorFunction, filteredTableValue, Value(null)]);
  }
}

class RequireFunction implements BuiltinFunction {
  final Interpreter vm;

  RequireFunction(this.vm);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw Exception("require() needs a module name");
    final moduleName = (args[0] as Value).raw.toString();

    Logger.debug("Looking for module '$moduleName'", category: 'Require');

    // 0. Check if it's built-in debug module which should be pre-registered
    if (moduleName == "debug") {
      final debugLib = vm.globals.get("debug");
      if (debugLib != null) {
        return debugLib;
      }
    }

    // Get package.loaded table
    final packageVal = vm.globals.get("package");
    if (packageVal is! Value || packageVal.raw is! Map) {
      throw Exception("package is not a table");
    }

    // Get the raw Map from the package table
    final packageTable = packageVal;

    // Ensure package.loaded exists
    if (!packageTable.containsKey("loaded")) {
      packageTable["loaded"] = Value({});
      Logger.debug("Created new package.loaded table", category: 'Require');
    }

    // Get the loaded table as a Value
    final loadedValue = packageTable["loaded"] as Value;
    final loaded = loadedValue;

    Logger.debug(
      "Loaded: $loaded with keys: ${loaded.keys}",
      category: 'Require',
    );

    // Step 1: Check if module is already loaded
    if (loaded.containsKey(moduleName) && loaded[moduleName] != false) {
      Logger.debug(
        "Module '$moduleName' already loaded: ${loaded[moduleName]}",
        category: 'Require',
      );
      return loaded[moduleName];
    }

    // Mark module as being loaded to handle circular requires
    loaded[moduleName] = Value(false);

    // Step 2: Try the preload table first
    final preloadTable = packageTable["preload"];
    if (preloadTable != null &&
        preloadTable is Value &&
        preloadTable.raw is Map) {
      final preloadMap = preloadTable.raw as Map;
      if (preloadMap.containsKey(moduleName)) {
        Logger.debug(
          "Found module '$moduleName' in preload table",
          category: 'Require',
        );
        final loader = preloadMap[moduleName];

        if (loader is Value && loader.isCallable()) {
          try {
            final result = await (loader.raw as Function)([]);
            loaded[moduleName] = result;
            return result;
          } catch (e) {
            throw Exception(
              "error loading module '$moduleName' from preload: $e",
            );
          }
        }
      }
    }

    // Special case: If the current script is in a special directory like .lua-tests,
    // and the module name doesn't contain a path separator, try to load it from the same directory first
    String? modulePath;
    if (!moduleName.contains('.') &&
        !moduleName.contains('/') &&
        vm.currentScriptPath != null) {
      final scriptDir = path.dirname(vm.currentScriptPath!);
      final directPath = path.join(scriptDir, '$moduleName.lua');
      Logger.debug(
        "DEBUG: Trying direct path in script directory: $directPath",
      );

      if (File(directPath).existsSync()) {
        Logger.debug("DEBUG: Module found in script directory: $directPath");
        modulePath = directPath;
      }
    }

    // If not found in the script directory, use the regular resolution
    if (modulePath == null) {
      modulePath = vm.fileManager.resolveModulePath(moduleName);

      // Print the resolved globs for debugging
      vm.fileManager.printResolvedGlobs();
    }

    if (modulePath != null) {
      Logger.debug(
        "(REQUIRE) RequireFunction: Loading module '$moduleName' from path: $modulePath",
        category: 'Require',
      );

      final source = vm.fileManager.loadSource(modulePath);
      if (source != null) {
        try {
          Logger.debug(
            "REQUIRE: Module source loaded, parsing and executing",
            category: 'Require',
          );
          // Parse the module code
          final ast = parse(source);

          // Create a new environment for the module
          final moduleEnv = Environment(parent: vm.globals, interpreter: vm);

          // Execute the module code in the new environment
          final interpreter = Interpreter(
            environment: moduleEnv,
            fileManager: vm.fileManager,
          );

          // Set the current script path to the module path
          String absoluteModulePath;
          if (path.isAbsolute(modulePath)) {
            absoluteModulePath = modulePath;
          } else {
            // Use the FileManager to resolve the absolute path instead of duplicating logic
            absoluteModulePath = vm.fileManager.resolveAbsoluteModulePath(
              modulePath,
            );
          }

          // Get the directory part of the script path
          final moduleDir = path.dirname(absoluteModulePath);

          // Set the current script path in the interpreter
          interpreter.currentScriptPath = absoluteModulePath;

          // Store the script path in the module environment
          moduleEnv.define('_SCRIPT_PATH', Value(absoluteModulePath));
          moduleEnv.define('_SCRIPT_DIR', Value(moduleDir));

          // Also set _MODULE_NAME global
          moduleEnv.define('_MODULE_NAME', Value(moduleName));
          moduleEnv.define('_MAIN_CHUNK', Value(false));

          Logger.debug(
            "DEBUG: Module environment set up with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$moduleName",
          );

          Object? result;
          try {
            // Run the module code
            await interpreter.run(ast.statements);
            // If no explicit return, the result is nil
            result = Value(null);
          } on ReturnException catch (e) {
            // Handle explicit return from module
            result = e.value;
          }

          // If the module didn't return anything, return an empty table
          if (result == null || (result is Value && result.raw == null)) {
            result = Value({});
          }

          Logger.debug(
            "(REQUIRE) RequireFunction: Module '$moduleName' loaded successfully",
            category: 'Require',
          );

          // Store the result in package.loaded
          loaded[moduleName] = result;
          Logger.debug(
            "Module '$moduleName' stored in package.loaded",
            category: 'Require',
          );
          Logger.debug(
            "Loaded table now contains: ${loaded.keys.join(",")}",
            category: 'Require',
          );

          // Return the loaded module
          return result;
        } catch (e) {
          throw Exception("error loading module '$moduleName': $e");
        }
      }

      // Step 3: If direct loading failed, try the searchers
      if (!packageTable.containsKey("searchers") ||
          packageTable["searchers"] is! Value) {
        throw Exception("package.searchers is not a table");
      }
      final searchersVal = packageTable["searchers"] as Value;
      if (searchersVal.raw is! List) {
        throw Exception("package.searchers is not a list");
      }
      final searchers = searchersVal.raw as List;

      // Try each searcher in order
      final errors = <String>[];

      for (int i = 0; i < searchers.length; i++) {
        final searcher = searchers[i];
        if (searcher is! Value || searcher.raw is! Function) {
          continue;
        }

        Logger.debug(
          "RequireFunction: Trying searcher #$i for '$moduleName'",
          category: 'Require',
        );

        try {
          // Call the searcher with the module name
          final result = await (searcher.raw as Function)([Value(moduleName)]);

          // If the searcher returns a loader function
          if (result is List &&
              result.isNotEmpty &&
              result[0] is Value &&
              result[0].raw is Function) {
            final loader = result[0] as Value;
            final loaderData = result.length > 1 ? result[1] : Value(null);

            Logger.debug(
              "RequireFunction: Found loader for '$moduleName' with data: $loaderData",
              category: 'Require',
            );

            // Call the loader with the module name and loader data
            final moduleResult = await (loader.raw as Function)([
              Value(moduleName),
              loaderData,
            ]);

            // Store the result in package.loaded
            if (moduleResult != null) {
              loaded[moduleName] = moduleResult;
            } else if (!loaded.containsKey(moduleName) ||
                loaded[moduleName] == false) {
              // If nothing was returned and nothing was stored, store true
              loaded[moduleName] = Value(true);
            }

            // Return the loaded module
            return loaded[moduleName];
          } else if (result is String) {
            // If the searcher returns an error message
            errors.add(result);
          } else if (result is Value && result.raw is String) {
            errors.add(result.raw.toString());
          }
        } catch (e) {
          errors.add("searcher #$i error: $e");
        }
      }

      // If we get here, no searcher found the module
      final errorMsg =
          "module '$moduleName' not found:${errors.isNotEmpty ? '\n\t${errors.join('\n\t')}' : ''}";
      throw Exception(errorMsg);
    }

    // If we couldn't find the module anywhere, throw an error
    throw Exception("module '$moduleName' not found");
  }
}

void defineBaseLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final vm = astVm ?? Interpreter();

  // Create a map of all functions and variables
  final baseLib = {
    // Core functions
    "assert": AssertFunction(vm),
    "error": ErrorFunction(vm),
    "ipairs": IPairsFunction(),
    "pairs": PairsFunction(),
    "collectgarbage": CollectGarbageFunction(vm),
    "rawget": RawGetFunction(),
    "print": PrintFunction(),
    "type": TypeFunction(),
    "tonumber": ToNumberFunction(),
    "tostring": ToStringFunction(),
    "select": SelectFunction(),

    // File operations
    "dofile": DoFileFunction(vm),
    "load": LoadFunction(vm),
    "loadfile": LoadfileFunction(),
    "require": RequireFunction(vm),

    // Table operations
    "next": NextFunction(),
    "rawequal": RawEqualFunction(),
    "rawlen": RawLenFunction(),
    "rawset": RawSetFunction(),

    // Protected calls
    "pcall": PCAllFunction(vm),
    "xpcall": XPCallFunction(),

    // Metatables
    "getmetatable": GetMetatableFunction(),
    "setmetatable": SetMetatableFunction(),

    // Miscellaneous
    "warn": WarnFunction(),

    // Global variables
    "_VERSION": Value("LuaLike 0.1"),
  };

  // Define all functions and variables at once
  env.defineAll(baseLib);

  // Create a special _G table that directly references the environment
  final gTable = <dynamic, dynamic>{};

  // Create a proxy map that will forward all operations to the environment
  final proxyHandler = <String, Function>{
    '__index': (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;
      final keyStr = key.raw.toString();

      // Get the value from the environment
      final value = env.get(keyStr);
      return value ?? Value(null);
    },
    '__newindex': (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;
      final value = args[2] as Value;
      final keyStr = key.raw.toString();

      // Set the value in the environment
      try {
        env.define(keyStr, value);
      } catch (_) {
        env.define(keyStr, value);
      }

      return Value(null);
    },
  };

  // Create the _G value with the proxy metatable
  final gValue = Value(gTable);
  gValue.setMetatable(proxyHandler);

  // Make _G point to itself
  gTable["_G"] = gValue;

  // Define _G in the environment
  env.define("_G", gValue);
}
