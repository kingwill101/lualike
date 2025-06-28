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
  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw Exception("debug.getinfo requires function/level argument");
    }

    // Create debug info table
    return Value({
      'name': Value(null),
      'namewhat': Value(""),
      'what': Value("Lua"),
      'source': Value("=[C]"),
      'currentline': Value(-1),
      'linedefined': Value(-1),
      'lastlinedefined': Value(-1),
      'nups': Value(0),
      'nparams': Value(0),
      'isvararg': Value(false),
      'istailcall': Value(false),
      'short_src': Value("[C]"),
    });
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
    value.setMetatable((meta.raw as Map).cast());
    return Value(true);
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
    final level = args.length > 1 ? (args[1] as Value).raw as int : 1;

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

void defineDebugLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final debugTable = <String, dynamic>{};
  DebugLib.functions.forEach((key, value) {
    debugTable[key] = value;
  });

  env.define("debug", DebugLib.functions);
}
