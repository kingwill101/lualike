import 'dart:io';

import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';

class DebugLib {
  static final Map<String, BuiltinFunction> functions = {
    'debug': _DebugInteractive(),
    'gethook': _GetHook(),
    'getinfo': _GetInfo(),
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

/// Interactive debug console
class _DebugInteractive implements BuiltinFunction {
  @override
  dynamic call(List<dynamic> args) {
    // Simple REPL-like debug console
    Logger.debug("Debug Console: Enter 'cont' to continue", category: 'Debug');

    while (true) {
      stdout.write('debug> ');
      final input = stdin.readLineSync();

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

class _GetInfo implements BuiltinFunction {
  final Interpreter? vm;

  _GetInfo([this.vm]);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("debug.getinfo requires function/level argument");
    }

    final firstArg = args[0] as Value;
    String? what = args.length > 1
        ? (args[1] as Value).raw.toString()
        : "flnStu";

    // Handle level-based lookup (when first arg is a number)
    if (firstArg.raw is num) {
      final level = (firstArg.raw as num).toInt();

      // Get function info from call stack at the specified level
      // We need to add 1 to the level to account for debug.getinfo's own call frame
      final actualLevel = level + 1;
      if (vm != null && vm!.callStack.depth >= actualLevel) {
        final frame = vm!.callStack.getFrameAtLevel(actualLevel);
        if (frame != null) {
          String? functionName = frame.functionName;
          if (functionName == "unknown" || functionName == "function") {
            functionName = null;
          }

          // Create debug info table with actual function name
          Map<String, Value> debugInfo = {};

          // Add fields based on what parameter
          if (what.contains('n')) {
            debugInfo['name'] = Value(functionName);
            debugInfo['namewhat'] = Value(functionName != null ? "local" : "");
          }
          if (what.contains('S')) {
            debugInfo['what'] = Value("Lua");
            debugInfo['source'] = Value("=[C]");
            debugInfo['short_src'] = Value("[C]");
            debugInfo['linedefined'] = Value(-1);
            debugInfo['lastlinedefined'] = Value(-1);
          }
          if (what.contains('l')) {
            debugInfo['currentline'] = Value(-1);
          }
          if (what.contains('t')) {
            debugInfo['istailcall'] = Value(false);
          }
          if (what.contains('u')) {
            debugInfo['nups'] = Value(0);
            debugInfo['nparams'] = Value(0);
            debugInfo['isvararg'] = Value(false);
          }
          if (what.contains('f')) {
            // Would return the function itself, but we don't have access to it here
          }

          return Value(debugInfo);
        }
      }
    }

    // Default debug info table when no specific info available
    Map<String, Value> debugInfo = {};

    if (what.contains('n')) {
      debugInfo['name'] = Value(null);
      debugInfo['namewhat'] = Value("");
    }
    if (what.contains('S')) {
      debugInfo['what'] = Value("Lua");
      debugInfo['source'] = Value("=[C]");
      debugInfo['short_src'] = Value("[C]");
      debugInfo['linedefined'] = Value(-1);
      debugInfo['lastlinedefined'] = Value(-1);
    }
    if (what.contains('l')) {
      debugInfo['currentline'] = Value(-1);
    }
    if (what.contains('t')) {
      debugInfo['istailcall'] = Value(false);
    }
    if (what.contains('u')) {
      debugInfo['nups'] = Value(0);
      debugInfo['nparams'] = Value(0);
      debugInfo['isvararg'] = Value(false);
    }

    return Value(debugInfo);
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
    // Return name and value of local variable
    return [Value(null), Value(null)];
  }
}

class _GetMetatable implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw Exception("debug.getmetatable requires a value");
    final value = args[0] as Value;
    return Value(value.getMetatable());
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
    // Return name and value of upvalue
    return [Value(null), Value(null)];
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
    if (meta.raw == null) {
      value.metatable = null;
      return Value(true);
    }
    if (meta.raw is Map) {
      value.setMetatable((meta.raw as Map).cast());
      return Value(true);
    }
    throw Exception("metatable must be a table or nil");
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
  return {
    'debug': _DebugInteractive(),
    'gethook': _GetHook(),
    'getinfo': _GetInfo(astVm), // Pass the interpreter instance
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

void defineDebugLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  env.define("debug", createDebugLib(astVm));
}
