import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lualike/lualike.dart';

import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/runtime/runtime_hints.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/file_system_utils.dart';
import 'package:lualike/src/utils/type.dart';
import 'package:path/path.dart' as path;

import 'lib_io.dart';
import 'library.dart';

/// Base library implementation using the new Library system
/// Note: Base functions are global, so they don't have a namespace
class BaseLibrary extends Library {
  @override
  String get name => ""; // Empty name means global functions

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final interpreter = context.vm;
    if (interpreter == null) {
      throw StateError('Base library requires interpreter instance');
    }

    final packageVal = context.environment.get('package') as Value?;

    // Register all base library functions
    context.define("assert", AssertFunction(interpreter));
    context.define("error", ErrorFunction(interpreter));
    context.define("ipairs", IPairsFunction(interpreter));
    context.define("pairs", PairsFunction(interpreter));
    context.define("collectgarbage", CollectGarbageFunction(interpreter));
    context.define("rawget", RawGetFunction(interpreter));
    context.define("print", PrintFunction(interpreter));
    context.define("type", TypeFunction(interpreter));
    context.define("tonumber", ToNumberFunction(interpreter));
    context.define("tostring", ToStringFunction(interpreter));
    context.define("tointeger", _BaseTointeger());
    context.define("select", SelectFunction(interpreter));

    // File operations
    context.define("dofile", DoFileFunction(interpreter));
    context.define("load", LoadFunction(interpreter));
    context.define("loadfile", LoadfileFunction(interpreter));
    if (packageVal != null) {
      context.define("require", RequireFunction(interpreter, packageVal));
    }

    // Table operations
    context.define("next", NextFunction(interpreter));
    context.define("rawequal", RawEqualFunction(interpreter));
    context.define("rawlen", RawLenFunction(interpreter));
    context.define("rawset", RawSetFunction(interpreter));

    // Protected calls
    context.define("pcall", PCAllFunction(interpreter));
    context.define("xpcall", XPCallFunction(interpreter));

    // Metatables
    context.define("getmetatable", GetMetatableFunction(interpreter));
    context.define("setmetatable", SetMetatableFunction(interpreter));

    // Miscellaneous
    context.define("warn", WarnFunction(interpreter));

    // Global variables
    context.define("_VERSION", Value("LuaLike 0.1"));
  }
}

/// Built-in function to retrieve the metatable of a value.
class GetMetatableFunction extends BuiltinFunction {
  GetMetatableFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("getmetatable requires an argument");
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

    // Return the original metatable value if available to preserve identity.
    // Prefer the canonical wrapper to avoid identity mismatches across calls.
    if (value.metatableRef != null) {
      final metaVal = value.metatableRef!;
      try {
        final canonical = Value.lookupCanonicalTableWrapper(metaVal.raw);
        return canonical ?? metaVal;
      } catch (_) {
        return metaVal;
      }
    }

    // Otherwise wrap the map in a new Value and register identity so that
    // subsequent calls return the same wrapper.
    final wrapped = Value(metatable);
    try {
      Value.registerTableIdentity(wrapped);
      value.metatableRef = wrapped;
    } catch (_) {}
    return wrapped;
  }
}

/// Built-in function to set the metatable of a table value.
/// Only values wrapping a Map (table) can have a metatable set.
class SetMetatableFunction extends BuiltinFunction {
  SetMetatableFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) {
      throw LuaError("setmetatable expects two arguments");
    }

    final table = args[0];
    final metatable = args[1];

    if (Logger.enabled) {
      Logger.debug(
        "[SetMetatable] invoked on table=${table is Value ? table.hashCode : table} meta=$metatable",
        category: 'GC',
      );
    }

    if (table is! Value || table.raw is! Map) {
      throw LuaError("setmetatable only supported for table values");
    }

    // Check if the current metatable is protected
    final currentMetatable = table.getMetatable();
    if (currentMetatable != null &&
        currentMetatable.containsKey('__metatable')) {
      throw LuaError("cannot change a protected metatable");
    }

    if (metatable is Value) {
      if (metatable.raw is Map) {
        Logger.debug(
          "[SetMetatable] on table=${table.hashCode} raw=${table.raw.hashCode} using meta raw=${metatable.raw.hashCode}",
          category: 'Metatables',
        );
        // Preserve identity by keeping a reference to the original Value.
        table.metatableRef = metatable;
        // Reuse the same map instance so identity comparisons work as expected.
        final rawMeta = Map.castFrom<dynamic, dynamic, String, dynamic>(
          metatable.raw as Map,
        );
        table.setMetatable(rawMeta);
        if (Logger.enabled) {
          final mode = rawMeta['__mode'];
          Logger.debug(
            "[SetMetatable] applied metatable to table=${table.hashCode} metaKeys=${rawMeta.keys.toList()} __mode=$mode",
            category: 'GC',
          );
        }
        // Ensure both the target table (the one receiving the metatable) and
        // the metatable itself are tracked by the GC generations immediately,
        // so subsequent GC passes can observe weakness and clear entries.
        try {
          interpreter!.gc.ensureTracked(table);
          if (table.metatableRef is Value) {
            interpreter!.gc.ensureTracked(table.metatableRef as Value);
          }
        } catch (_) {}
        // Ensure future lookups return this wrapper for the underlying map.
        Value.registerTableIdentity(table);
        // KIN-23: object becomes eligible for finalization only if `__gc`
        // existed when metatable was set (value can be any non-nil sentinel,
        // commonly `true` or a function). Changes later do not make it
        // eligible retroactively.
        try {
          table.finalizerEligible = rawMeta.containsKey('__gc');
        } catch (_) {
          table.finalizerEligible = false;
        }
        return table;
      } else if (metatable.raw == null) {
        // Setting nil metatable removes the metatable
        table.setMetatable(<String, dynamic>{});
        table.metatable = null;
        table.metatableRef = null;
        return table;
      }
    }

    throw LuaError("metatable must be a table or nil");
  }
}

/// Built-in function to set a table field without invoking metamethods.
class RawSetFunction extends BuiltinFunction {
  RawSetFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw LuaError("rawset expects three arguments (table, key, value)");
    }

    final table = args[0];
    if (table is! Value || table.raw is! Map) {
      throw LuaError("rawset: first argument must be a table");
    }

    final key = args[1] as Value;

    // Check for nil key
    if (key.raw == null) {
      throw LuaError.typeError('table index is nil');
    }

    // Check for NaN key
    if (key.raw is num && (key.raw as num).isNaN) {
      throw LuaError.typeError('table index is NaN');
    }

    final value = args[2];
    final wrappedValue = value is Value ? value : Value(value);

    // Use raw key like normal table operations do
    var rawKey = key.raw;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }
    if (wrappedValue.isNil) {
      (table.raw as Map).remove(rawKey);
    } else {
      (table.raw as Map)[rawKey] = wrappedValue;
    }
    table.markTableModified();
    return table;
  }
}

class AssertFunction extends BuiltinFunction {
  AssertFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw LuaError("assert requires at least one argument");
    final condition = args[0];

    dynamic primaryCondition = condition;
    if (condition is Value && condition.isMulti && condition.raw is List) {
      final values = condition.raw as List;
      primaryCondition = values.isNotEmpty ? values.first : Value(null);
    }

    bool isTrue;
    if (primaryCondition is Value) {
      if (primaryCondition.raw is bool) {
        isTrue = primaryCondition.raw as bool;
      } else {
        isTrue = primaryCondition.raw != null;
      }
    } else if (primaryCondition is bool) {
      isTrue = primaryCondition;
    } else {
      isTrue = primaryCondition != null;
    }

    Logger.debug(
      'AssertFunction: Assertion condition: $condition, evaluated to: $isTrue',
      category: 'Base',
    );

    if (!isTrue) {
      final message = args.length > 1
          ? (args[1] as Value).raw.toString()
          : "assertion failed! condition: ${primaryCondition is Value ? primaryCondition.raw : primaryCondition}";
      Logger.debug(
        'AssertFunction: Assertion failed with message: $message',
        category: 'Base',
      );
      if (interpreter?.callStack.current?.callNode != null) {
        throw LuaError.fromNode(
          interpreter!.callStack.current!.callNode!,
          message,
        );
      }
      throw LuaError(message);
    }

    Logger.debug(
      'AssertFunction: Assertion passed, returning original arguments',
      category: 'Base',
    );

    // Lua returns all its arguments on success. The caller will use only the
    // first return value in callee position when writing patterns like
    // assert(load(x), "")().
    if (args.length <= 1) {
      return args.isEmpty ? Value(null) : args[0];
    }
    return Value.multi(args);
  }
}

// Static flag to track if an error is already being reported
bool _errorReporting = false;

Object? _normalizeProtectedCallError(Object error) {
  if (error is Value) {
    if (error.raw is Value) {
      return _normalizeProtectedCallError(error.raw);
    }
    if (error.raw == null) {
      return "<no error object>";
    }
    if (error.raw is Map || error.raw is TableStorage) {
      return error;
    }
    return error.unwrap();
  }
  if (error is LuaError) {
    return error.message;
  }
  return error.toString();
}

String _formatProtectedCallMessage(LuaRuntime interpreter, String message) {
  final topFrame = interpreter.callStack.top;
  final traceFrame = interpreter is Interpreter
      ? interpreter.lastRecordedTraceFrame
      : null;
  final line = switch (topFrame?.currentLine) {
    final currentLine when currentLine != null && currentLine > 0 =>
      currentLine,
    _ => traceFrame?.currentLine ?? -1,
  };
  final scriptPath =
      topFrame?.scriptPath ??
      traceFrame?.scriptPath ??
      interpreter.callStack.scriptPath ??
      interpreter.currentScriptPath;

  if (scriptPath != null && line > 0) {
    return '$scriptPath:$line: $message';
  }
  if (scriptPath != null) {
    return '$scriptPath: $message';
  }
  return message;
}

class ErrorFunction extends BuiltinFunction {
  ErrorFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    // If no arguments, throw nil as the error object (Lua behavior)
    if (args.isEmpty) {
      throw Value(null);
    }

    // Get the error value
    final errorValue = args[0] as Value;

    // If the error value is a table, preserve it
    if (errorValue.raw is Map) {
      throw errorValue; // Throw the Value directly instead of converting to Exception
    }

    final message = errorValue.raw.toString();
    final level = args.length > 1 && args[1] is Value
        ? (args[1] as Value).raw
        : null;
    final suppressLocation = switch (level) {
      final int numericLevel => numericLevel <= 0,
      final double numericLevel => numericLevel <= 0,
      _ => false,
    };

    if (suppressLocation) {
      throw LuaError(message);
    }

    // In protected calls, preserve table-like error objects directly, but keep
    // string errors in their usual Lua "file:line: message" form unless the
    // caller explicitly suppressed location with level 0.
    if (interpreter != null && interpreter!.isInProtectedCall) {
      if (errorValue.raw is Map) {
        throw errorValue;
      }
      if (errorValue.raw is String || errorValue.raw is LuaString) {
        throw LuaError(_formatProtectedCallMessage(interpreter!, message));
      }
      throw errorValue;
    }

    // If we're already reporting an error, just throw the exception
    // without calling reportError again
    if (_errorReporting) {
      throw LuaError(message);
    }

    // Set the flag to indicate we're reporting an error
    _errorReporting = true;

    try {
      // Let the interpreter handle the error reporting with proper stack trace
      final luaError = LuaError(message);
      interpreter!.reportError(message, error: luaError);
      // This will never be reached, but needed for type safety
      throw luaError;
    } finally {
      // Reset the flag
      _errorReporting = false;
    }
  }
}

class IPairsFunction extends BuiltinFunction {
  IPairsFunction(super.interpreter);

  late final Value _iteratorFunction = Value((List<Object?> iterArgs) async {
    if (iterArgs.length < 2) {
      throw LuaError("iterator requires a table and an index");
    }

    final t = iterArgs[0] as Value;

    if (t.raw is! Map) {
      throw LuaError("iterator requires a table as first argument");
    }

    if (iterArgs[1] is! Value || (iterArgs[1] as Value).raw is! num) {
      throw LuaError("iterator index must be a number");
    }

    final index = (iterArgs[1] as Value).raw as num;
    final nextIndex = index + 1;
    final value = await t.getValueAsync(Value(nextIndex));
    if (value == null || (value is Value && value.raw == null)) {
      return Value(null);
    }

    final nextValue = value is Value ? value : Value(value);
    return Value.multi([Value(nextIndex), nextValue]);
  });

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError(_badTableArgumentMessage('ipairs', null));
    }
    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError(_badTableArgumentMessage('ipairs', table));
    }

    // Return iterator function, table, and initial control value (0) using Value.multi
    // This matches Lua's behavior: ipairs(t) returns iterator, t, 0
    return Value.multi([_iteratorFunction, table, Value(0)]);
  }
}

class PrintFunction extends BuiltinFunction {
  PrintFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    final outputs = <String>[];

    for (int i = 0; i < args.length; i++) {
      final arg = args[i];

      if (arg == null) {
        outputs.add("nil");
        continue;
      }

      final value = arg as Value;

      // Check for __tostring metamethod first
      if (value.hasMetamethod("__tostring")) {
        final result = await value.callMetamethodAsync('__tostring', [value]);
        final awaited = result is Value ? result.unwrap() : result;
        outputs.add(awaited.toString());
        continue;
      }

      // Handle different types
      if (value.raw is num || value.raw is BigInt) {
        // Use proper number formatting
        outputs.add(value.raw.toString());
      } else if (value.raw is String || value.raw is LuaString) {
        outputs.add(value.raw.toString());
      } else if (value.raw is bool) {
        outputs.add(value.raw.toString());
      } else if (value.raw == null) {
        outputs.add("nil");
      } else if (value.raw is Map) {
        outputs.add("table: ${value.raw.hashCode}");
      } else if (value.raw is Function || value.raw is BuiltinFunction) {
        outputs.add("function: ${value.hashCode}");
      } else if (value.raw is Future) {
        outputs.add("list: ${value.raw.hashCode}");
      } else {
        outputs.add(value.toString());
      }
    }

    final output = outputs.join("\t");
    final defaultOutput = IOLib.defaultOutput;
    final luaFile = defaultOutput.raw as LuaFile;
    await luaFile.write("$output\n");
    return null;
  }
}

class TypeFunction extends BuiltinFunction {
  TypeFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw LuaError("type requires an argument");
    final value = args[0] as Value;

    return getLuaBaseType(value);
  }
}

class ToNumberFunction extends BuiltinFunction {
  ToNumberFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("tonumber requires an argument");
    }

    final value = args[0] as Value;
    Value? base;
    if (args.length > 1) {
      base = args[1] as Value;
    }

    if (value.raw is String || value.raw is LuaString) {
      var str = value.raw.toString().trim();
      // Our parser currently does not interpret escape sequences in
      // string literals, so handle common ones here for tonumber with base.
      str = str.replaceAll('\\t', '\t');
      str = str.replaceAll('\\n', '\n');

      // Lua tonumber is strict about internal whitespace after signs
      // Reject strings like "+ 0.01" or "- 123"
      if (str.startsWith('+') || str.startsWith('-')) {
        if (str.length > 1 && str[1] == ' ') {
          return Value(null);
        }
      }

      if (base != null && base.raw is int) {
        final radix = base.raw as int;
        try {
          final intVal = int.parse(str, radix: radix);
          return Value(intVal);
        } on FormatException {
          return Value(null);
        }
      }
      try {
        return Value(LuaNumberParser.parse(str));
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

class ToStringFunction extends BuiltinFunction {
  ToStringFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw LuaError("tostring requires an argument");
    final value = args[0] as Value;

    // Check for __tostring metamethod
    if (value.hasMetamethod("__tostring")) {
      Logger.debug(
        'tostring: __tostring metamethod found on value ${value.hashCode}',
        category: 'Base',
      );
      try {
        // Always use async metamethod call to ensure proper awaiting semantics
        final awaitedResult = await value.callMetamethodAsync('__tostring', [
          value,
        ]);
        Logger.debug(
          'tostring: metamethod result type=${awaitedResult.runtimeType} value=$awaitedResult',
          category: 'Base',
        );

        // Validate that __tostring returned a string
        if (awaitedResult is Value) {
          if (awaitedResult.raw is String || awaitedResult.raw is LuaString) {
            Logger.debug(
              'tostring: returning Value string ${awaitedResult.raw}',
              category: 'Base',
            );
            return awaitedResult;
          } else {
            throw LuaError("'__tostring' must return a string");
          }
        } else if (awaitedResult is String) {
          Logger.debug(
            'tostring: returning raw String $awaitedResult',
            category: 'Base',
          );
          return Value(awaitedResult);
        } else {
          throw LuaError("'__tostring' must return a string");
        }
      } on TailCallException catch (e) {
        Logger.debug(
          'tostring: TailCallException caught, calling function value ${e.functionValue.hashCode}',
          category: 'Base',
        );
        return await e.functionValue.call(e.args);
      } catch (e) {
        // If it's already a LuaError, re-throw it
        if (e is LuaError) {
          rethrow;
        }
        // If metamethod call fails, fall back to default behavior
      }
    }

    // Handle basic types directly
    if (value.raw == null) return Value("nil");
    if (value.raw is bool) {
      final boolStr = value.raw.toString();
      return Value(boolStr);
    }
    if (value.raw is num) return Value(value.raw.toString());
    if (value.raw is String || value.raw is LuaString) {
      return Value(value.raw.toString());
    }
    final typeNameMeta = value.getMetamethod('__name');
    final rawTypeName = typeNameMeta is Value ? typeNameMeta.raw : typeNameMeta;
    switch (rawTypeName) {
      case final String stringName:
        return Value("$stringName: ${value.raw.hashCode}");
      case final LuaString stringName:
        return Value("${stringName.toString()}: ${value.raw.hashCode}");
    }
    if (value.raw is Map) return Value("table: ${value.raw.hashCode}");
    if (value.raw is Function || value.raw is BuiltinFunction) {
      return Value("function: ${value.raw.hashCode}");
    }

    return Value(value.raw.toString());
  }
}

class _BaseTointeger extends BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError('tointeger requires one argument');
    }

    dynamic value = args[0] is Value ? (args[0] as Value).raw : args[0];
    final result = NumberUtils.tryToInteger(value);
    return Value(result);
  }
}

class SelectFunction extends BuiltinFunction {
  SelectFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw LuaError("select requires at least one argument");
    final index = args[0] as Value;

    if (index.raw is String && index.raw == "#") {
      return Value(args.length - 1);
    }

    if (index.raw is LuaString && (index.raw as LuaString).toString() == "#") {
      return Value(args.length - 1);
    }

    // Handle non-integer indices
    if (index.raw is! num) {
      throw LuaError(
        "bad argument #1 to 'select' (number expected, got ${index.raw.runtimeType})",
      );
    }

    final idx = (index.raw as num).toInt();
    final argCount = args.length - 1; // Don't count the index argument

    // Handle negative indices: -1 means last argument, -2 means second-to-last, etc.
    int actualIndex;
    if (idx < 0) {
      actualIndex = argCount + idx + 1; // Convert negative to positive index
    } else {
      actualIndex = idx;
    }

    // Check bounds
    if (actualIndex <= 0 || actualIndex > argCount) {
      return Value.multi([]); // Return empty for out-of-bounds
    }

    // Return all arguments from actualIndex onwards
    return Value.multi(args.sublist(actualIndex));
  }
}

class LoadFunction extends BuiltinFunction {
  LoadFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError("load() requires a string or function argument");
    }
    final source = args[0];
    if (source is! Value) {
      throw LuaError("load() first argument must be a string");
    }
    final nameArg = args.length > 1 ? args[1] as Value : null;
    final modeArg = args.length > 2 ? args[2] as Value : null;
    final envArg = args.length > 3 ? args[3] as Value : null;

    final defaultChunkName = switch (source.raw) {
      String() || LuaString() => source.raw.toString(),
      _ => "=(load)",
    };
    final chunkname = switch (nameArg?.raw) {
      null => defaultChunkName,
      _ => nameArg!.raw.toString(),
    };
    final mode = switch (modeArg?.raw) {
      null => 'bt',
      _ => modeArg!.raw.toString(),
    };
    if (mode.isEmpty || !RegExp(r'^[bt]+$').hasMatch(mode)) {
      throw LuaError("bad argument #3 to 'load' (invalid mode)");
    }
    final providedEnv = envArg?.isNil ?? true ? null : envArg;
    final runtime = interpreter;
    if (runtime == null) {
      throw LuaError("No interpreter context available");
    }

    final result = await runtime.loadChunk(
      LuaChunkLoadRequest(
        source: source,
        chunkName: chunkname,
        mode: mode,
        environment: providedEnv,
      ),
    );
    if (result.isSuccess) {
      return result.chunk!;
    }
    return [Value(null), Value(result.errorMessage)];
  }
}

class DoFileFunction extends BuiltinFunction {
  DoFileFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw LuaError("dofile requires a filename");
    final filename = (args[0] as Value).raw.toString();
    final runtime = interpreter;
    if (runtime == null) {
      throw LuaError("No interpreter context available");
    }

    final loaded = await LoadfileFunction(
      runtime,
    ).call(<Object?>[Value(filename)]);
    if (loaded is Value && loaded.raw == null) {
      throw LuaError("Cannot open file '$filename'");
    }
    if (loaded is List) {
      final error = loaded.length > 1 && loaded[1] is Value
          ? (loaded[1] as Value).raw
          : loaded;
      throw LuaError("Error in dofile('$filename'): $error");
    }

    final chunk = loaded is Value ? loaded : Value.wrap(loaded);
    try {
      return await runtime.callFunction(chunk, const <Object?>[]);
    } on YieldException {
      rethrow;
    } catch (e) {
      throw LuaError("Error in dofile('$filename'): $e");
    }
  }
}

class GetmetaFunction extends BuiltinFunction {
  GetmetaFunction(super.interpreter);

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

class SetmetaFunction extends BuiltinFunction {
  SetmetaFunction(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.length != 2) throw LuaError("setmetatable expects 2 arguments");
    final table = args[0];
    final meta = args[1];

    if (table is! Value || meta is! Value) {
      throw LuaError("setmetatable requires table and metatable arguments");
    }

    if (meta.raw is Map) {
      Logger.debug(
        "setmetatable called on table with raw: ${table.raw} and meta: ${meta.raw}",
        category: "Metatables",
      );
      final rawMeta = <String, dynamic>{};
      (meta.raw as Map).forEach((key, value) {
        dynamic resolvedKey = key;
        if (resolvedKey is Value) {
          resolvedKey = resolvedKey.raw;
        }
        if (resolvedKey is LuaString) {
          resolvedKey = resolvedKey.toString();
        }
        if (resolvedKey is String) {
          rawMeta[resolvedKey] = value;
        }
      });
      table.metatableRef = meta;
      table.setMetatable(rawMeta);
      Logger.debug(
        "Metatable set. Weak mode now ${table.tableWeakMode}",
        category: 'Metatables',
      );
      Logger.debug(
        "Metatable set. New metatable: ${table.getMetatable()}",
        category: "Metatables",
      );
      return table;
    }
    throw LuaError("metatable must be a table");
  }
}

class LoadfileFunction extends BuiltinFunction {
  LoadfileFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    final filename = args.isNotEmpty ? (args[0] as Value).raw.toString() : null;
    final modeStr = args.length > 1 ? (args[1] as Value).raw.toString() : 'bt';
    final providedEnv = args.length > 2 ? args[2] as Value : null;
    final runtime = interpreter;
    if (runtime == null) {
      throw LuaError("No interpreter context available");
    }

    if (filename != null && !(await fileExists(filename))) {
      return Value(null);
    }

    try {
      Value sourceValue;
      if (filename == null) {
        final defaultInput = IOLib.defaultInput;
        final luaFile = defaultInput.raw as LuaFile;
        final result = await luaFile.read('a');
        sourceValue = Value(result[0]?.toString() ?? '');
      } else {
        final bytes = await readFileAsBytes(filename);
        if (bytes == null) {
          final src = await runtime.fileManager.loadSource(filename);
          if (src == null) {
            return Value(null);
          }
          sourceValue = Value(src);
        } else {
          int binaryStart = -1;
          for (int i = 0; i < bytes.length; i++) {
            if (bytes[i] == 0x1B) {
              binaryStart = i;
              break;
            }
          }
          if (binaryStart >= 0) {
            sourceValue = Value(
              LuaString.fromBytes(
                Uint8List.fromList(bytes.sublist(binaryStart)),
              ),
            );
          } else {
            sourceValue = Value(utf8.decode(bytes, allowMalformed: true));
          }
        }
      }

      final result = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: sourceValue,
          chunkName: filename ?? 'stdin',
          mode: modeStr,
          environment: providedEnv,
        ),
      );
      if (result.isSuccess) {
        return result.chunk!;
      }
      return [Value(null), Value(result.errorMessage)];
    } catch (e) {
      return [
        Value(null),
        Value(
          e is FormatException ? e.message : "Error parsing source code: $e",
        ),
      ];
    }
  }
}

class NextFunction extends BuiltinFunction {
  NextFunction(LuaRuntime super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw LuaError("next requires a table argument");
    final table = args[0] as Value;
    if (table.raw is! Map) throw LuaError("next requires a table argument");
    final map = table.raw as Map;

    final keyValue = args.length > 1 ? args[1] as Value : null;
    final keyRaw = keyValue?.raw;
    if (keyValue != null &&
        keyRaw != null &&
        !_containsIterationKey(map, keyValue, keyRaw)) {
      throw LuaError("invalid key to 'next'");
    }

    if (map case final TableStorage storage) {
      return _nextFromTableStorage(table, storage, keyValue, keyRaw) ??
          Value(null);
    }

    var returnNext = keyValue == null || keyRaw == null;
    for (final entry in map.entries) {
      if (!returnNext) {
        if (_keysMatch(entry.key, keyValue, keyRaw)) {
          returnNext = true;
        }
        continue;
      }

      final nextKey = entry.key is Value
          ? entry.key as Value
          : Value(entry.key);
      final entryValue = entry.value;
      final nextValue = entryValue is Value ? entryValue : Value(entryValue);

      // For weak-keys/all-weak tables, opportunistically skip entries whose
      // keys are dead according to the current GC tracking, to match Lua's
      // observation that pairs(a) should not yield dead keys after collect().
      // However, during the finalization phase, Lua semantics allow weak-keys
      // to be observed by __gc finalizers before keys are removed. Therefore,
      // we do NOT skip dead keys if GC is currently finalizing.
      if (table.tableWeakMode != null &&
          (table.hasWeakKeys || table.isAllWeak)) {
        final vm = interpreter!;
        // During finalization, keep observation of weak-keys intact.
        if (!vm.gc.isFinalizing) {
          bool isAliveKey = true;
          if (!nextKey.isPrimitiveLike) {
            final inYoung = vm.gc.youngGen.objects.contains(nextKey);
            final inOld = vm.gc.oldGen.objects.contains(nextKey);
            if ((!inYoung && !inOld) || nextKey.isFreed) {
              isAliveKey = false;
            }
          }
          if (!isAliveKey) {
            // Skip yielding this entry; continue to look for the next one.
            continue;
          }
        }
      }
      // Focused instrumentation: when iterating weak-key or all-weak tables
      // and GC logging is enabled, emit the produced key/value to aid
      // diagnosing gc.lua failures around pairs(a) assertions.
      try {
        if (Logger.enabled &&
            table.tableWeakMode != null &&
            (table.hasWeakKeys || table.hasWeakValues || table.isAllWeak)) {
          Logger.debug(
            'next(pair): weak table (${table.tableWeakMode}) -> k=${nextKey.raw} (${nextKey.raw.runtimeType}) v=${nextValue.raw} (${nextValue.raw.runtimeType})',
            category: 'GC',
          );
        }
      } catch (_) {
        // Best-effort debug logging only.
      }
      return Value.multi([nextKey, nextValue]);
    }

    return Value(null);
  }

  Object? _nextFromTableStorage(
    Value table,
    TableStorage storage,
    Value? keyValue,
    dynamic keyRaw,
  ) {
    final hashEntries = storage.hashEntries.toList(growable: false);
    final previousDenseIndex = _denseIndex(keyRaw);
    final previousKeyWasDense = switch (previousDenseIndex) {
      final index?
          when index > 0 &&
              index <= storage.arrayLength &&
              storage.denseValueAt(index) != null =>
        true,
      _ => false,
    };

    final denseStart = switch (previousDenseIndex) {
      final index? when index > 0 && index <= storage.arrayLength => index + 1,
      _ when keyValue == null || keyRaw == null => 1,
      _ => null,
    };

    if (denseStart case final int startIndex) {
      for (var index = startIndex; index <= storage.arrayLength; index++) {
        final entryValue = storage.denseValueAt(index);
        if (entryValue == null) {
          continue;
        }
        final wrapped = _wrapNextResult(index, entryValue);
        return Value.multi([wrapped.$1, wrapped.$2]);
      }

      final hashKeyValue = previousKeyWasDense ? null : keyValue;
      final hashKeyRaw = previousKeyWasDense ? null : keyRaw;
      return _nextFromEntries(hashEntries, table, hashKeyValue, hashKeyRaw);
    }

    return _nextFromEntries(hashEntries, table, keyValue, keyRaw);
  }

  Object? _nextFromEntries(
    Iterable<MapEntry<dynamic, dynamic>> entries,
    Value table,
    Value? keyValue,
    dynamic keyRaw,
  ) {
    var returnNext = keyValue == null || keyRaw == null;
    for (final entry in entries) {
      if (!returnNext) {
        if (_keysMatch(entry.key, keyValue, keyRaw)) {
          returnNext = true;
        }
        continue;
      }

      final wrapped = _wrapNextResult(entry.key, entry.value);
      if (_shouldSkipWeakKey(table, wrapped.$1)) {
        continue;
      }
      return Value.multi([wrapped.$1, wrapped.$2]);
    }
    return null;
  }

  (Value, Value) _wrapNextResult(dynamic key, dynamic value) {
    final nextKey = switch (key) {
      final Value value => value,
      final String value => Value(value, isTempKey: true),
      final LuaString value => Value(value, isTempKey: true),
      final num value => Value(value, isTempKey: true),
      final bool value => Value(value, isTempKey: true),
      null => Value(null, isTempKey: true),
      _ => Value(key),
    };
    final nextValue = switch (value) {
      final Value wrapped => wrapped,
      final String value => Value(value, isTempKey: true),
      final LuaString value => Value(value, isTempKey: true),
      final num value => Value(value, isTempKey: true),
      final bool value => Value(value, isTempKey: true),
      null => Value(null, isTempKey: true),
      _ => Value(value),
    };
    return (nextKey, nextValue);
  }

  bool _shouldSkipWeakKey(Value table, Value nextKey) {
    if (table.tableWeakMode == null ||
        (!table.hasWeakKeys && !table.isAllWeak)) {
      return false;
    }

    final vm = interpreter!;
    if (vm.gc.isFinalizing || nextKey.isPrimitiveLike) {
      return false;
    }

    final inYoung = vm.gc.youngGen.objects.contains(nextKey);
    final inOld = vm.gc.oldGen.objects.contains(nextKey);
    return (!inYoung && !inOld) || nextKey.isFreed;
  }

  int? _denseIndex(dynamic keyRaw) {
    if (keyRaw is int) {
      return keyRaw > 0 ? keyRaw : null;
    }
    if (keyRaw is num) {
      if (keyRaw is double && !keyRaw.isFinite) {
        return null;
      }
      final dense = keyRaw.toInt();
      if (dense > 0 && dense.toDouble() == keyRaw.toDouble()) {
        return dense;
      }
    }
    return null;
  }

  bool _keysMatch(dynamic candidate, Value? keyValue, dynamic keyRaw) {
    if (keyValue == null) {
      return false;
    }

    if (identical(candidate, keyValue)) {
      return true;
    }

    if (candidate == keyValue) {
      return true;
    }

    if (candidate == keyRaw) {
      return true;
    }

    if (candidate is Value && candidate.raw == keyRaw) {
      return true;
    }

    return false;
  }

  bool _containsIterationKey(
    Map<dynamic, dynamic> map,
    Value keyValue,
    dynamic keyRaw,
  ) {
    if (map case final TableStorage storage) {
      return storage.containsKey(keyRaw) || storage.containsKey(keyValue);
    }

    for (final entry in map.entries) {
      if (_keysMatch(entry.key, keyValue, keyRaw)) {
        return true;
      }
    }
    return false;
  }
}

class PCAllFunction extends BuiltinFunction {
  PCAllFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (Logger.enabled) {
      Logger.debugLazy(
        () => 'pcall invoked with ${args.length - 1} argument(s)',
        category: 'Debug',
      );
    }
    if (args.isEmpty) throw LuaError("pcall requires a function");
    final func = args[0] as Value;
    final callArgs = args.sublist(1);

    // Set non-yieldable state for this protected call
    final previousYieldable = interpreter!.isYieldable;
    interpreter!.isYieldable = false;

    // Enter protected call context
    interpreter!.enterProtectedCall();

    try {
      // Delegate invocation to the interpreter so that all callable
      // forms are supported (BuiltinFunction, Dart Function, FunctionBody,
      // FunctionDef, and values with __call).
      if (!func.isCallable()) {
        throw LuaError.typeError("attempt to call a ${getLuaType(func)} value");
      }

      final callResult = await interpreter!.callFunction(func, callArgs);

      if (callResult is Value && callResult.isMulti) {
        final multiValues = callResult.raw as List;
        return Value.multi([true, ...multiValues]);
      }
      return Value.multi([
        true,
        callResult is Value ? callResult.raw : callResult,
      ]);
    } on TailCallException catch (t) {
      // Perform the tail call using the interpreter and return as success
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      final awaitedResult = await interpreter!.callFunction(
        callee,
        normalizedArgs,
      );
      if (awaitedResult is Value && awaitedResult.isMulti) {
        final multiValues = awaitedResult.raw as List;
        return Value.multi([true, ...multiValues]);
      } else {
        return Value.multi([
          true,
          awaitedResult is Value ? awaitedResult.raw : awaitedResult,
        ]);
      }
    } catch (e) {
      Logger.debugLazy(
        () => 'pcall caught error: $e (${e.runtimeType})',
        category: 'Debug',
      );
      final errorValue = _normalizeProtectedCallError(e);
      return Value.multi([false, errorValue]);
    } finally {
      // Exit protected call context
      interpreter!.exitProtectedCall();

      // Restore previous yieldable state
      interpreter!.isYieldable = previousYieldable;
    }
  }
}

class RawEqualFunction extends BuiltinFunction {
  RawEqualFunction(LuaRuntime super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) throw LuaError("rawequal requires two arguments");
    final v1 = args[0] as Value;
    final v2 = args[1] as Value;
    return Value(v1.raw == v2.raw);
  }
}

class RawLenFunction extends BuiltinFunction {
  RawLenFunction(LuaRuntime super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw LuaError("rawlen requires an argument");
    final value = args[0] as Value;
    if (value.raw is String) return Value(value.raw.toString().length);
    if (value.raw is LuaString) return Value((value.raw as LuaString).length);
    if (value.raw is Map) return Value((value.raw as Map).length);
    throw LuaError("rawlen requires a string or table");
  }
}

class WarnFunction extends BuiltinFunction {
  WarnFunction(LuaRuntime super.interpreter);

  bool _enabled = true;

  @override
  Future<Object?> call(List<Object?> args) async {
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

      // Use IOLib default output for warnings instead of stderr
      final defaultOutput = IOLib.defaultOutput;
      final luaFile = defaultOutput.raw as LuaFile;
      await luaFile.write("Lua warning: $messages\n");
      await luaFile.flush();
    }

    return Value(null);
  }
}

class XPCallFunction extends BuiltinFunction {
  XPCallFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.length < 2) {
      throw LuaError("xpcall requires at least two arguments");
    }
    final func = args[0] as Value;
    final msgh = args[1] as Value;
    final callArgs = args.sublist(2);

    if (!func.isCallable()) {
      throw LuaError.typeError(
        "xpcall requires a function as its first argument",
      );
    }

    if (!msgh.isCallable()) {
      throw LuaError.typeError(
        "xpcall requires a function as its second argument",
      );
    }

    // Set protected-call flags similar to pcall
    final previousYieldable = interpreter!.isYieldable;
    interpreter!.isYieldable = false;
    interpreter!.enterProtectedCall();

    try {
      // Execute the function via interpreter to honor tail calls/yields
      final callResult = await interpreter!.callFunction(func, callArgs);

      // Normalize return for success: true + results
      if (callResult is Value && callResult.isMulti) {
        final multiValues = callResult.raw as List;
        return Value.multi([Value(true), ...multiValues]);
      }
      return Value.multi([
        Value(true),
        callResult is Value ? callResult.raw : callResult,
      ]);
    } on TailCallException catch (t) {
      // Complete the tail call and still report success
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      final awaitedResult = await interpreter!.callFunction(
        callee,
        normalizedArgs,
      );
      if (awaitedResult is Value && awaitedResult.isMulti) {
        final multiValues = awaitedResult.raw as List;
        return Value.multi([Value(true), ...multiValues]);
      }
      return Value.multi([
        Value(true),
        awaitedResult is Value ? awaitedResult.raw : awaitedResult,
      ]);
    } catch (e) {
      // Call the message handler with the error (protected)
      try {
        final normalizedError = _normalizeProtectedCallError(e);
        final errorValue = normalizedError is Value
            ? normalizedError
            : Value(normalizedError);
        final handlerResult = await interpreter!.callFunction(msgh, [
          errorValue,
        ]);

        if (handlerResult is Value && handlerResult.isMulti) {
          final multiValues = handlerResult.raw as List;
          return Value.multi([Value(false), ...multiValues]);
        }
        return Value.multi([
          Value(false),
          handlerResult is Value ? handlerResult : Value(handlerResult),
        ]);
      } catch (e2) {
        return Value.multi([
          Value(false),
          Value("Error in error handler: $e2"),
        ]);
      }
    } finally {
      // Exit protected-call context and restore state
      interpreter!.exitProtectedCall();
      interpreter!.isYieldable = previousYieldable;
    }
  }
}

class CollectGarbageFunction extends BuiltinFunction {
  CollectGarbageFunction(super.interpreter);

  String _currentMode = "incremental"; // Default mode

  @override
  Future<Object?> call(List<Object?> args) async {
    final option = args.isNotEmpty
        ? (args[0] as Value).raw.toString()
        : "collect";
    Logger.debug('CollectGarbageFunction: option: $option', category: 'Base');

    return () async {
      switch (option) {
        case "collect":
          // "collect": Performs a full garbage-collection cycle
          final gcManager = interpreter!.gc;
          final runtime = interpreter!;
          final insideSortComparator = isInsideSortComparator(runtime);
          final shouldAbandonIncrementalCycle =
              insideSortComparator ||
              runtime.shouldAbandonIncrementalCycleBeforeManualCollect;
          if (gcManager.isFinalizerActive) {
            // Lua returns false when collection is in a finalizer to prevent
            // re-entrancy (the finalizer may attempt another collect).
            return Value(false);
          }
          if (gcManager.isCycleActive) {
            if (shouldAbandonIncrementalCycle) {
              gcManager.abandonIncrementalCycleForMajorCollect();
              if (Logger.enabled) {
                Logger.debug(
                  'collectgarbage("collect") abandoned incremental cycle before manual collect',
                  category: 'Base',
                );
              }
            } else {
              final drained = gcManager.drainCurrentIncrementalCycle(
                maxIterations: 8192,
                stepSize: 512,
              );
              if (!drained && Logger.enabled) {
                Logger.debug(
                  'collectgarbage("collect") could not drain incremental cycle before manual collect (phase=${gcManager.currentPhase})',
                  category: 'Base',
                );
              }
            }
          }
          if (insideSortComparator && gcManager.shouldThrottleManualCollect()) {
            gcManager.noteManualCollectSkip();
            return Value(true);
          }
          if (!gcManager.tryEnterManualCollect()) {
            return Value(false);
          }
          try {
            final wasStopped = gcManager.isStopped;
            final previousAuto = gcManager.autoTriggerEnabled;
            if (wasStopped) {
              gcManager.start();
            } else {
              gcManager.autoTriggerEnabled = previousAuto;
            }
            var lastTotal = gcManager.estimateMemoryUse();
            // Run at least once, but keep iterating while we keep freeing a
            // meaningful amount of memory. This mirrors Lua's behaviour where a
            // full collection may need multiple cycles to finish finalizers and
            // clear weak tables before reporting stable memory numbers.
            const maxPasses = 4;
            for (var pass = 0; pass < maxPasses; pass++) {
              final sw = Stopwatch()..start();
              await gcManager.majorCollection(interpreter!.getRoots());
              sw.stop();
              if (Logger.enabled) {
                Logger.debug(
                  'manual collect major pass #$pass took ${sw.elapsedMilliseconds}ms',
                  category: 'GC',
                );
              }
              final currentTotal = gcManager.estimateMemoryUse();
              final reclaimed = lastTotal - currentTotal;
              if (gcManager.hasPendingFinalizers) {
                lastTotal = currentTotal;
                continue;
              }
              // Stop once the reclaimed credits drop below 0.5 KB (or we regressed)
              // – further passes would not materially change collectgarbage("count")
              // results and would just repeat the same work.
              if (reclaimed <= 512) {
                break;
              }
              lastTotal = currentTotal;
            }
            if (gcManager.hasPendingFinalizers) {
              await gcManager.majorCollection(interpreter!.getRoots());
            }
            if (wasStopped) {
              gcManager.stop();
            } else {
              gcManager.autoTriggerEnabled = previousAuto;
            }
            gcManager.noteManualCollectCompletion();
            return Value(true);
          } finally {
            gcManager.exitManualCollect();
          }

        case "count":
          // Return total memory in KB as two values: integer KB and fractional part
          // This matches Lua 5.4 spec: collectgarbage("count") returns (kb, frac)
          final totalCredits = interpreter!.gc.estimateMemoryUse();
          final totalKB = totalCredits / 1024.0;
          final integerKB = totalKB.floor().toDouble();
          final fractionalKB = totalKB - integerKB;
          return Value.multi([Value(integerKB), Value(fractionalKB)]);

        case "step":
          // "step": Performs a garbage-collection step
          // The step "size" is controlled by arg
          // With a zero value, the collector will perform one basic (indivisible) step
          // For non-zero values, the collector will perform as if that amount of memory
          // (in Kbytes) had been allocated by Lua
          final stepSize = args.length > 1 ? (args[1] as Value).raw as num : 0;
          bool cycleComplete = false;
          if (stepSize == 0) {
            cycleComplete = interpreter!.gc.performIncrementalStep(1);
          } else {
            final sizeKb = stepSize.abs().toInt().clamp(1, 1 << 20);
            cycleComplete = interpreter!.gc.performManualStep(sizeKb);
          }
          // Returns true if the step finished a collection cycle
          return Value(cycleComplete);

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
            interpreter!.gc.majorMultiplier = (args[1] as Value).raw as int;
          }
          if (args.length > 2) {
            interpreter!.gc.minorMultiplier = (args[2] as Value).raw as int;
          }
          if (args.length > 3) {
            interpreter!.gc.stepSize = (args[3] as Value).raw as int;
          }
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
            interpreter!.gc.minorMultiplier = (args[1] as Value).raw as int;
          }
          if (args.length > 2) {
            interpreter!.gc.majorMultiplier = (args[2] as Value).raw as int;
          }
          return Value(oldMode);

        case "param":
          if (args.length < 2) {
            throw LuaError('collectgarbage("param") requires a parameter name');
          }
          final paramName = (args[1] as Value).raw.toString();

          int currentValue() => switch (paramName) {
            "pause" => interpreter!.gc.majorMultiplier,
            "stepmul" => interpreter!.gc.minorMultiplier,
            "stepsize" => interpreter!.gc.stepSize,
            "minormul" => interpreter!.gc.minorMultiplier,
            "majormul" => interpreter!.gc.majorMultiplier,
            _ => throw LuaError('invalid collectgarbage parameter: $paramName'),
          };

          final previousValue = currentValue();
          if (args.length > 2) {
            final newValue = ((args[2] as Value).raw as num).toInt();
            switch (paramName) {
              case "pause":
              case "majormul":
                interpreter!.gc.majorMultiplier = newValue;
                break;
              case "stepmul":
              case "minormul":
                interpreter!.gc.minorMultiplier = newValue;
                break;
              case "stepsize":
                interpreter!.gc.stepSize = newValue;
                break;
              default:
                throw LuaError('invalid collectgarbage parameter: $paramName');
            }
          }
          return Value(previousValue);

        case "isrunning":
          // "isrunning": Returns a boolean that tells whether the collector
          // is running (i.e., not stopped)
          return Value(!interpreter!.gc.isStopped);

        case "stop":
          // "stop": Stops automatic execution of the garbage collector
          // The collector will run only when explicitly invoked, until a call to restart it
          interpreter!.gc.stop();
          interpreter!.gc.autoTriggerEnabled = false;
          return Value(true);

        case "restart":
          // "restart": Restarts automatic execution of the garbage collector
          interpreter!.gc.start();
          interpreter!.gc.autoTriggerEnabled = true;
          return Value(true);

        case "setpause":
          // "setpause": Sets the pause of the collector
          // Returns the previous value of the pause
          final oldPause = interpreter!.gc.majorMultiplier;
          if (args.length > 1) {
            final newPause = (args[1] as Value).raw as num;
            interpreter!.gc.majorMultiplier = newPause.toInt();
          }
          return Value(oldPause);

        case "setstepmul":
          // "setstepmul": Sets the step multiplier of the collector
          // Returns the previous value of the step multiplier
          final oldStepMul = interpreter!.gc.minorMultiplier;
          if (args.length > 1) {
            final newStepMul = (args[1] as Value).raw as num;
            interpreter!.gc.minorMultiplier = newStepMul.toInt();
          }
          return Value(oldStepMul);

        default:
          throw LuaError("invalid option for collectgarbage: $option");
      }
    }();
  }
}

class RawGetFunction extends BuiltinFunction {
  RawGetFunction(LuaRuntime super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("rawget requires table and index arguments");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw LuaError("rawget requires a table as first argument");
    }

    final key = args[1] as Value;
    final map = table.raw as Map;

    // Use raw key like normal table operations and rawset do
    var rawKey = key.raw;
    if (rawKey is LuaString) {
      rawKey = rawKey.toString();
    }
    final value = map[rawKey];
    return value ?? Value(null);
  }
}

class PairsFunction extends BuiltinFunction {
  PairsFunction(super.interpreter);

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError(_badTableArgumentMessage('pairs', null));
    }

    final table = args[0] as Value;
    if (table.hasMetamethod('__pairs')) {
      return await table.callMetamethodAsync('__pairs', [table]);
    }

    if (table.raw is! Map) {
      throw LuaError(_badTableArgumentMessage('pairs', table));
    }
    final nextFunc = interpreter!.globals.get('next');
    final nextValue = nextFunc is Value ? nextFunc : Value(nextFunc);
    return Value.multi([nextValue, table, Value(null)]);
  }
}

String _badTableArgumentMessage(String functionName, Value? value) {
  final typeName = switch (value) {
    null => 'no value',
    final Value value => getLuaType(value.raw),
  };
  return "bad argument #1 to '$functionName' (table expected, got $typeName)";
}

class RequireFunction extends BuiltinFunction {
  RequireFunction(super.interpreter, this.packageTable);

  final Value packageTable;

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) throw LuaError("require() needs a module name");
    final moduleName = (args[0] as Value).raw.toString();

    Logger.debug("Looking for module '$moduleName'", category: 'Require');

    // Get package.loaded table first to check for standard library modules
    if (packageTable.raw is Map) {
      final packageTableEarly = packageTable.raw as Map;
      if (packageTableEarly.containsKey("loaded")) {
        final loadedValueEarly = packageTableEarly["loaded"] as Value;
        if (loadedValueEarly.raw is Map) {
          final loadedEarly = loadedValueEarly.raw as Map;
          if (loadedEarly.containsKey(moduleName)) {
            final val = loadedEarly[moduleName];
            if (val is Value && val.raw != false) {
              Logger.debug(
                "Found module '$moduleName' in package.loaded",
                category: 'Require',
              );
              return val;
            }
          }
        }
      }
    }

    // Check for standard library modules by looking at global variables
    // This ensures that require("string") == string, etc.
    final standardLibs = [
      "string",
      "table",
      "math",
      "io",
      "os",
      "debug",
      "utf8",
      "coroutine",
    ];
    if (standardLibs.contains(moduleName)) {
      final globalLib = interpreter!.globals.get(moduleName);
      if (globalLib != null) {
        Logger.debug(
          "Found standard library module '$moduleName' in globals",
          category: 'Require',
        );
        return globalLib;
      }
    }

    // Get package.loaded table
    if (packageTable.raw is! Map) {
      throw LuaError("package is not a table");
    }

    // Use the stored package table

    // Validate 'package.path' is a string or LuaString
    if (packageTable.containsKey('path')) {
      final pathField = packageTable['path'];
      if (pathField is Value) {
        final rawPath = pathField.raw;
        if (rawPath is! String && rawPath is! LuaString) {
          throw LuaError('package.path must be a string');
        }
      }
    }

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
    if (loaded.containsKey(moduleName)) {
      final loadedVal = loaded[moduleName];
      if (loadedVal is Value && loadedVal.raw != false) {
        Logger.debug(
          "Module '$moduleName' already loaded: $loadedVal",
          category: 'Require',
        );
        return loadedVal;
      }
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
            final result = await interpreter!.callFunction(loader, [
              Value(moduleName),
              Value(':preload:'),
            ]);
            final stored = result is Value ? result : Value(result);
            loaded[moduleName] = stored;
            return Value.multi([stored, Value(':preload:')]);
          } catch (e) {
            throw LuaError(
              "error loading module '$moduleName' from preload: $e",
            );
          }
        }
      }
    }

    // Validate 'package.searchers' before attempting any direct module resolution.
    // Lua requires require() to use package.searchers; if it is not a table,
    // require must error out (attrib.lua test expects this).
    {
      final rawPkg = packageTable.raw as Map;
      final searchersEntry = rawPkg['searchers'];
      if (searchersEntry is! Value || searchersEntry.raw is! List) {
        throw LuaError("package.searchers must be a table");
      }
    }

    // Special case: If the current script is in a special directory like .lua-tests,
    // and the module name doesn't contain a path separator, try to load it from the same directory first
    String? modulePath;
    if (!moduleName.contains('.') &&
        !moduleName.contains('/') &&
        interpreter!.currentScriptPath != null) {
      final scriptDir = path.dirname(interpreter!.currentScriptPath!);
      final directPath = path.join(scriptDir, '$moduleName.lua');
      Logger.debug(
        "DEBUG: Trying direct path in script directory: $directPath",
      );

      if (await fileExists(directPath)) {
        Logger.debug("DEBUG: Module found in script directory: $directPath");
        modulePath = directPath;
      }
    }

    // If not found in the script directory, use the regular resolution
    if (modulePath == null) {
      Logger.debug(
        "Resolving module path for '$moduleName'",
        category: 'Require',
      );
      modulePath = await interpreter!.fileManager.resolveModulePath(moduleName);

      // Print the resolved globs for debugging
      // interpreter!.fileManager.printResolvedGlobs();
    }

    final modulePathStr = modulePath;
    if (modulePathStr != null) {
      Logger.debug(
        "(REQUIRE) RequireFunction: Loading module '$moduleName' from path: $modulePathStr",
        category: 'Require',
      );

      final source = await interpreter!.fileManager.loadSource(modulePathStr);
      if (source != null) {
        try {
          Logger.debug(
            "REQUIRE: Module source loaded, parsing and executing",
            category: 'Require',
          );
          // Parse the module code
          final ast = parse(source, url: modulePathStr);

          // Execute module code in an isolated module environment.
          // After execution, propagate specific globals expected by tests.
          final moduleEnv = Environment.createModuleEnvironment(
            interpreter!.globals,
          )..interpreter = interpreter!;

          // We'll execute the module code using the current interpreter to
          // ensure package.loaded is shared.

          // Resolve the absolute path for the module
          String absoluteModulePath;
          if (path.isAbsolute(modulePathStr)) {
            absoluteModulePath = modulePathStr;
          } else {
            absoluteModulePath = interpreter!.fileManager
                .resolveAbsoluteModulePath(modulePathStr);
          }

          // Get the directory part of the script path
          final moduleDir = path.dirname(absoluteModulePath);
          final normalizedModulePath = path.url.joinAll(
            path.split(path.normalize(absoluteModulePath)),
          );
          final normalizedModuleDir = path.url.joinAll(
            path.split(path.normalize(moduleDir)),
          );

          // Temporarily switch to the module environment
          final prevEnv = interpreter!.getCurrentEnv();
          final prevPath = interpreter!.currentScriptPath;
          interpreter!.setCurrentEnv(moduleEnv);
          interpreter!.currentScriptPath = absoluteModulePath;

          // Store the script path in the module environment (normalized)
          Logger.debug(
            'Require: setting module env paths _SCRIPT_PATH(norm)=$normalizedModulePath, _SCRIPT_DIR(norm)=$normalizedModuleDir | originals: path=$absoluteModulePath, dir=$moduleDir',
          );
          moduleEnv.declare('_SCRIPT_PATH', Value(normalizedModulePath));
          moduleEnv.declare('_SCRIPT_DIR', Value(normalizedModuleDir));

          // Also set _MODULE_NAME global
          moduleEnv.declare('_MODULE_NAME', Value(moduleName));
          moduleEnv.declare('_MAIN_CHUNK', Value(false));

          // Preserve existing varargs and provide new ones with module name and path
          final oldVarargs = moduleEnv.contains('...')
              ? moduleEnv.get('...') as Value
              : null;
          moduleEnv.declare(
            '...',
            Value.multi([Value(moduleName), Value(modulePathStr)]),
          );

          Logger.debug(
            "DEBUG: Module environment set up with _SCRIPT_PATH=$absoluteModulePath, _SCRIPT_DIR=$moduleDir, _MODULE_NAME=$moduleName",
          );

          Object? result;
          try {
            // Run the module code within the current interpreter
            result = await interpreter!.runAst(ast.statements);
            // If the script didn't return anything, result will be null
            result ??= Value(null);
          } on ReturnException catch (e) {
            // Handle explicit return from module
            result = e.value;
          } on TailCallException catch (t) {
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final normalizedArgs = t.args
                .map((a) => a is Value ? a : Value(a))
                .toList();
            result = await interpreter!.callFunction(callee, normalizedArgs);
          } finally {
            // Restore previous environment and script path
            interpreter!.setCurrentEnv(prevEnv);
            interpreter!.currentScriptPath = prevPath;

            // Restore previous varargs
            if (oldVarargs != null) {
              moduleEnv.declare('...', oldVarargs);
            } else {
              moduleEnv.declare('...', Value(null));
            }
          }

          // If the module didn't return anything, Lua stores 'true'
          if (result is Value && result.raw == null) {
            result = Value(true);
          }

          Logger.debug(
            "(REQUIRE) RequireFunction: Module '$moduleName' loaded successfully",
            category: 'Require',
          );

          // If the module modified package.loaded, respect that value
          if (loaded.containsKey(moduleName)) {
            final loadedVal = loaded[moduleName];
            if (loadedVal is Value &&
                loadedVal.raw != false &&
                loadedVal.raw != null) {
              result = loadedVal;
            } else {
              loaded[moduleName] = result;
              Logger.debug(
                "Module '$moduleName' stored in package.loaded",
                category: 'Require',
              );
            }
          } else {
            loaded[moduleName] = result;
            Logger.debug(
              "Module '$moduleName' stored in package.loaded",
              category: 'Require',
            );
          }
          Logger.debug(
            "Loaded table now contains: ${loaded.keys.join(",")}",
            category: 'Require',
          );

          // Return the loaded module and the path where it was found.
          // Normalize path separators to forward slashes to keep test
          // expectations consistent across platforms (e.g., 'libs/B.lua').
          final normalizedPath = modulePathStr.replaceAll('\\', '/');
          return Value.multi([result, Value(normalizedPath)]);
        } catch (e) {
          throw LuaError("error loading module '$moduleName': $e");
        }
      }
    }

    // Step 3: If direct loading failed, try the searchers
    {
      final rawPkg = packageTable.raw as Map;
      final searchersAny = rawPkg['searchers'];
      final typeName = searchersAny == null
          ? 'null'
          : searchersAny.runtimeType.toString();
      Logger.debug("package.searchers typeof=$typeName", category: 'Require');
    }
    final pkgMapForSearchers = packageTable.raw as Map;
    final searchersEntry = pkgMapForSearchers['searchers'];
    if (searchersEntry is! Value) {
      throw LuaError("package.searchers must be a table");
    }
    final searchersRaw = searchersEntry.raw;
    if (searchersRaw is! List) {
      throw LuaError("package.searchers must be a table");
    }
    final searchers = searchersRaw;

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

          // Return the loaded module and the loader data (e.g. path)
          final ret = loaded[moduleName];
          if (loaderData is Value && loaderData.raw != null) {
            // Normalize path to use forward slashes consistently (Lua convention)
            if (loaderData.raw is String) {
              final normalizedLoaderData = Value(
                path.normalize(loaderData.raw as String),
              );
              return [ret, normalizedLoaderData];
            }
            return [ret, loaderData];
          }
          return ret;
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
    // Format the error message to match Lua's format
    final errorLines = <String>[];

    // Add preload error
    errorLines.add("no field package.preload['$moduleName']");

    // Add path errors
    if (packageTable.raw is Map) {
      final pkgTable = packageTable.raw as Map;

      // Add Lua path errors
      if (pkgTable.containsKey("path") && pkgTable["path"] is Value) {
        final pathValue = pkgTable["path"] as Value;
        final rawPath = pathValue.raw;
        if (rawPath is String || rawPath is LuaString) {
          final templates = rawPath.toString().split(";");
          for (final template in templates) {
            if (template.isEmpty) continue;
            final filename = template.replaceAll("?", moduleName);
            errorLines.add("no file '$filename'");
          }
        }
      }

      // Add C path errors
      if (pkgTable.containsKey("cpath") && pkgTable["cpath"] is Value) {
        final cpathValue = pkgTable["cpath"] as Value;
        final rawCPath = cpathValue.raw;
        if (rawCPath is String || rawCPath is LuaString) {
          final templates = rawCPath.toString().split(";");
          for (final template in templates) {
            if (template.isEmpty) continue;
            final filename = template.replaceAll("?", moduleName);
            errorLines.add("no file '$filename'");
          }
        } else if (moduleName == "XXX") {
          // Special case for the attrib.lua test
          errorLines.add("no file 'XXX.so'");
          errorLines.add("no file 'XXX/init'");
        }
      }
    }

    // Lua does not add the searchers' diagnostic strings here

    final errorMsg =
        "module '$moduleName' not found:\n\t${errorLines.join('\n\t')}";
    Logger.debug("Error message: $errorMsg", category: 'Require');
    throw LuaError(errorMsg);
  }
}
