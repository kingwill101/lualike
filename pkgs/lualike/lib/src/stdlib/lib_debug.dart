import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/stdlib/debug_getinfo.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/stdlib/metatables.dart';

class DebugLib {
  static Map<String, BuiltinFunction> functions = {};
}

/// Interactive debug console
class _DebugInteractive implements BuiltinFunction {
  @override
  dynamic call(List<dynamic> args) async {
    // Simple REPL-like debug console
    Logger.debug("Debug Console: Enter 'cont' to continue", category: 'Debug');

    while (true) {
      await IOLib.defaultOutput.write('debug> ');
      final result = await IOLib.defaultInput.read('l');
      final input = result[0]?.toString();

      if (input == 'cont') break;

      // TODO: Implement actual debug command parsing and execution
    }

    return null;
  }
}

class _GetHook implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Return current hook function, mask and count
    return [Value(null), Value(0), Value(0)];
  }
}

class _GetLocal implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception(
        "debug.getlocal requires thread/function and level arguments",
      );
    }

    final levelArg = args[0] as Value;
    final indexArg = args[1] as Value;

    // Only support numeric level lookups (common case in tests)
    if (levelArg.raw is! num || indexArg.raw is! num) {
      return Value.multi([Value(null), Value(null)]);
    }

    final level = (levelArg.raw as num).toInt();
    final index = (indexArg.raw as num).toInt();

    // Map Lua levels to our call stack: skip this C function's own frame
    final interpreter = Environment.current?.interpreter;
    final frame = interpreter?.callStack.getFrameAtLevel(level + 1);
    if (frame == null) {
      return Value.multi([Value(null), Value(null)]);
    }

    // Enumerate debug locals recorded for the frame
    final locals = frame.debugLocals;
    if (index <= 0 || index > locals.length) {
      return Value.multi([Value(null), Value(null)]);
    }

    final entry = locals[index - 1];
    final name = entry.key;
    final value = entry.value;
    return Value.multi([Value(name), value]);
  }
}

class _GetMetatable implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("debug.getmetatable requires a value");
    final value = args[0] as Value;
    final meta = value.getMetatable();
    if (meta == null) {
      return Value(null);
    }
    if (meta.containsKey('__metatable')) {
      return meta['__metatable'];
    }
    if (value.metatableRef != null) {
      return value.metatableRef;
    }
    return Value(meta);
  }
}

class _GetRegistry implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Return the registry table
    return Value({});
  }
}

class _GetUpvalue implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("debug.getupvalue requires function and index arguments");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value.multi([Value(null), Value(null)]);
    }

    final index = (indexArg.raw as num).toInt();

    // Check if the function has explicit upvalues first
    if (functionArg.upvalues != null &&
        index > 0 &&
        index <= functionArg.upvalues!.length) {
      final upvalue = functionArg.upvalues![index - 1];
      final name = upvalue.name;
      final value = Value(upvalue.getValue());
      return Value.multi([Value(name), value]);
    }

    // For AST-based interpreter, we simulate standard Lua upvalue behavior
    // In Lua, functions typically have _ENV as an upvalue for global access
    if (functionArg.raw is Function) {
      // For any Dart function (with or without functionBody), simulate standard upvalue structure
      if (index == 2) {
        // Second upvalue is typically _ENV in Lua
        final envValue =
            Environment.current?.get('_ENV') ??
            Environment.current?.get('_G') ??
            Value(Environment.current);
        return Value.multi([Value('_ENV'), Value(envValue)]);
      } else if (index == 1) {
        // First upvalue could be any captured variable, return nil for now
        return Value.multi([Value(null), Value(null)]);
      }
    }

    return Value.multi([Value(null), Value(null)]);
  }
}

class _GetUserValue implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception(
        "debug.getuservalue requires userdata and index arguments",
      );
    }
    // Return nth user value
    return Value(null);
  }
}

class _SetHook implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception("debug.sethook requires hook function, mask and count");
    }
    // Set debug hook function
    return Value(null);
  }
}

class _SetLocal implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception(
        "debug.setlocal requires thread/function, index and value",
      );
    }
    // Set local variable value
    return Value(null);
  }
}

class _SetMetatable implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("debug.setmetatable requires value and metatable");
    }
    final value = args[0] as Value;
    final meta = args[1] as Value;
    if (value.raw is! Map) {
      final type = _typeOf(value.raw);
      if (meta.raw == null) {
        MetaTable().registerDefaultMetatable(type, null);
        return Value(true);
      }
      if (meta.raw is Map) {
        MetaTable().registerDefaultMetatable(
          type,
          ValueClass.create(
            Map.castFrom<dynamic, dynamic, String, dynamic>(meta.raw as Map),
          ),
          meta,
        );
        return Value(true);
      }
    } else {
      if (meta.raw == null) {
        value.metatable = null;
        value.metatableRef = null;
        return Value(true);
      }
      if (meta.raw is Map) {
        value.metatableRef = meta;
        value.setMetatable((meta.raw as Map).cast());
        return Value(true);
      }
    }
    throw Exception("metatable must be a table or nil");
  }

  String _typeOf(Object? raw) {
    if (raw == null) return 'nil';
    if (raw is String || raw is LuaString) return 'string';
    if (raw is num || raw is BigInt) return 'number';
    if (raw is bool) return 'boolean';
    if (raw is Function || raw is BuiltinFunction) return 'function';
    if (raw is Map || raw is List) return 'table';
    if (raw is Coroutine) return 'thread';
    return 'userdata';
  }
}

class _SetUpvalue implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception("debug.setupvalue requires function, index and value");
    }
    // Set upvalue
    return Value(null);
  }
}

class _SetUserValue implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw Exception("debug.setuservalue requires userdata, value and index");
    }
    // Set nth user value
    return Value(null);
  }
}

class _Traceback implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    final message = args.isNotEmpty ? (args[0] as Value).raw.toString() : "";
    //level
    final _ = args.length > 1 ? (args[1] as Value).raw as int : 1;

    final trace = StringBuffer();
    if (message.isNotEmpty) {
      trace.writeln(message);
    }
    trace.writeln("stack traceback:");
    // Add dummy stack trace for now
    trace.writeln("\t[C]: in function 'traceback'");

    return Value(trace.toString());
  }
}

class _UpvalueId implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("debug.upvalueid requires function and index");
    }
    // Return unique id for upvalue
    return Value(null);
  }
}

class _UpvalueJoin implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 4) {
      throw Exception("debug.upvaluejoin requires f1,n1,f2,n2 arguments");
    }
    // Join upvalues
    return Value(null);
  }
}

/// Creates debug library functions with the given interpreter instance
Map<String, BuiltinFunction> createDebugLib(Interpreter? astVm) {
  // Ensure we have a valid VM instance for debug functions
  if (astVm == null) {
    Logger.warning(
      "No VM instance provided to debug library, line tracking might not work correctly",
      category: "Debug",
    );

    // Try to get interpreter from current environment as a fallback
    final env = Environment.current;
    if (env != null && env.interpreter != null) {
      astVm = env.interpreter;
      Logger.info(
        "Found interpreter from Environment.current for debug library",
        category: "Debug",
      );
    }
  }

  // Create debug functions with interpreter reference
  return {
    'debug': _DebugInteractive(),
    'gethook': _GetHook(),
    'getinfo': createGetInfoFunction(astVm), // Use new optimized implementation
    'getlocal': _GetLocal(),
    'getmetatable': _GetMetatable(),
    'getregistry': _GetRegistry(),
    'getupvalue': _GetUpvalue(),
    'getuservalue': _GetUserValue(),
    'sethook': _SetHook(),
    'setlocal': _SetLocal(),
    'setmetatable': _SetMetatable(),
    'setupvalue': _SetUpvalue(),
    'setuservalue': _SetUserValue(),
    'traceback': _Traceback(),
    'upvalueid': _UpvalueId(),
    'upvaluejoin': _UpvalueJoin(),
  };
}

/// Initialize the debug library with the interpreter instance
///
/// This ensures the debug.getinfo function can access line information
/// [env] - The environment to define the debug table in
/// [astVm] - The interpreter instance to use for call stack access
/// [bytecodeVm] - Optional bytecode VM for bytecode mode
void defineDebugLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  // Store interpreter reference in environment for later access
  if (astVm != null) {
    env.interpreter = astVm;
    Logger.debug(
      'Setting interpreter reference in environment for debug library',
      category: 'Debug',
    );
  }

  // Create and define the debug table
  DebugLib.functions = createDebugLib(astVm);
  final debugTable = Value(DebugLib.functions);
  env.define("debug", debugTable);

  // Ensure the same object is stored in package.loaded for require() equality
  final packageTable = env.get("package");
  if (packageTable != null &&
      packageTable is Value &&
      packageTable.raw is Map) {
    final packageMap = packageTable.raw as Map;

    // Ensure package.loaded exists
    if (!packageMap.containsKey("loaded")) {
      packageMap["loaded"] = Value({});
    }

    final loadedTable = packageMap["loaded"];
    if (loadedTable is Value && loadedTable.raw is Map) {
      final loadedMap = loadedTable.raw as Map;
      // Store the same debug table object to ensure require("debug") == debug
      loadedMap["debug"] = debugTable;
      Logger.debug(
        'Debug table stored in package.loaded for require() equality',
        category: 'Debug',
      );
    }
  }

  Logger.debug(
    'Debug library initialized with interpreter: ${astVm != null}',
    category: 'Debug',
  );
}
