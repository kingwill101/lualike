import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/stdlib/debug_getinfo.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/stdlib/metatables.dart';

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
        
    // Log that debug.getinfo was called to help with troubleshooting
    Logger.debug(
      'debug.getinfo called with args: $firstArg, what: $what, vm: ${vm != null}',
      category: 'DebugLib'
    );

    // If we don't have a VM instance, try to get one
    final interpreter = vm ?? _findInterpreter();
    if (interpreter == null) {
      Logger.warning('No interpreter instance available for debug.getinfo', category: 'DebugLib');
    }

    // Handle level-based lookup (when first arg is a number)
    if (firstArg.raw is num) {
      final level = (firstArg.raw as num).toInt();
      final actualLevel = level + 1; // skip getinfo's own frame

      if (interpreter != null) {
        // Get the frame from the call stack, fallback to top frame if level is out of bounds
        final frame = interpreter.callStack.getFrameAtLevel(actualLevel) ?? 
                       interpreter.callStack.top;
                       
        if (frame != null) {
          Logger.debug(
            'Found frame for level $level: name=${frame.functionName}, line=${frame.currentLine}',
            category: 'DebugLib'
          );
          
          String? functionName = frame.functionName;
          if (functionName == "unknown" || functionName == "function") {
            functionName = null;
          }

          final debugInfo = <String, Value>{};

          if (what.contains('n')) {
            debugInfo['name'] = Value(functionName);
            debugInfo['namewhat'] = Value(functionName != null ? "local" : "");
          }
          if (what.contains('S')) {
            debugInfo['what'] = Value("Lua");
            final scriptPath = frame.scriptPath;
            debugInfo['source'] = Value(scriptPath != null ? "@$scriptPath" : "=[C]");
            debugInfo['short_src'] = Value(scriptPath != null ? scriptPath : "[C]");
            debugInfo['linedefined'] = Value(-1);
            debugInfo['lastlinedefined'] = Value(-1);
          }
          if (what.contains('l')) {
            // Get the current line from the frame and ensure it's valid
            final line = frame.currentLine;
            if (line <= 0) {
              // Fall back to a default value of 1 if line info is missing
              Logger.warning(
                'Invalid line number in frame: $line, using 1 instead',
                category: 'DebugLib'
              );
              debugInfo['currentline'] = Value(1);
            } else {
              debugInfo['currentline'] = Value(line);
            }
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

  /// Attempts to find an interpreter instance from the global environment
  ///
  /// This is a fallback mechanism when the VM wasn't explicitly passed to the debug library
  Interpreter? _findInterpreter() {
    try {
      // Try to get the current environment
      final env = Environment.current;
      if (env != null && env.interpreter != null) {
        Logger.debug(
          'Found interpreter via Environment.current',
          category: 'DebugLib'
        );
        return env.interpreter;
      }
      
      Logger.error(
        'Could not find interpreter for debug.getinfo',
        category: 'DebugLib'
      );
      return null;
    } catch (e) {
      Logger.error(
        'Error finding interpreter: $e',
        category: 'DebugLib'
      );
      return null;
    }
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
      category: "Debug"
    );
    
    // Try to get interpreter from current environment as a fallback
    final env = Environment.current;
    if (env != null && env.interpreter != null) {
      astVm = env.interpreter;
      Logger.info(
        "Found interpreter from Environment.current for debug library",
        category: "Debug"
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
      category: 'Debug'
    );
  }
  
  // Create and define the debug table
  final debugLib = createDebugLib(astVm);
  env.define("debug", Value(debugLib));
  
  Logger.debug(
    'Debug library initialized with interpreter: ${astVm != null}',
    category: 'Debug'
  );
}
