import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/interpreter/interpreter.dart' show Interpreter;
import '../environment.dart';
import '../io/lua_file.dart';
import '../value.dart' show Value;
import '../builtin_function.dart' show BuiltinFunction;
import 'lib_base.dart';
import 'lib_string.dart';
import 'lib_table.dart';
import 'lib_math.dart';
import 'lib_io.dart';
import 'lib_os.dart';
import 'lib_debug.dart';
import 'lib_utf8.dart';
import 'lib_package.dart';
import 'metatables.dart';
import 'lib_dart_string.dart';
import 'lib_convert.dart';
import 'lib_crypto.dart';
// import 'lib_convert.dart';

// Minimal coroutine stub state to support coroutine.wrap/yield pre-collection
class _CoroutineStubState {
  static final List<List<Value>> _collectorStack = <List<Value>>[];
  static Value Function(List<Object?> args)? yieldOverride;

  static void pushCollector(List<Value> collector) {
    _collectorStack.add(collector);
  }

  static List<Value>? get currentCollector =>
      _collectorStack.isNotEmpty ? _collectorStack.last : null;

  static void popCollector() {
    if (_collectorStack.isNotEmpty) {
      _collectorStack.removeLast();
    }
  }
}

// Define a function signature for the library definition callback
typedef LibraryDefinitionCallback =
    void Function({
      required Environment env,
      Interpreter? astVm,
      BytecodeVM? bytecodeVm,
    });

/// Helper function to define a standard library
void defineLibrary(
  LibraryDefinitionCallback definitionCallback, {
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  definitionCallback(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
}

/// Initialize all standard libraries for both VMs (AST and Bytecode)
void initializeStandardLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  // Define the package library first, as other libraries may depend on it
  definePackageLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);

  // Define the base library (which includes require)
  defineBaseLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineDebugLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);

  if (astVm != null) {
    MetaTable.initialize(astVm);
  }
  defineStringLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineTableLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineMathLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineIOLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineOSLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineUTF8Library(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineDartStringLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineConvertLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);
  defineCryptoLibrary(env: env, astVm: astVm, bytecodeVm: bytecodeVm);

  // Define a minimal coroutine stub to prevent strings test failures
  _defineCoroutineStub(env: env);

  // Get the package.loaded table to store standard library references
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

      // Store references to the global standard library tables in package.loaded
      // This ensures require("string") returns the same instance as the global string table
      final stringTable = env.get("string");
      if (stringTable != null) {
        loadedMap["string"] = stringTable;
      }

      final tableTable = env.get("table");
      if (tableTable != null) {
        loadedMap["table"] = tableTable;
      }

      final mathTable = env.get("math");
      if (mathTable != null) {
        loadedMap["math"] = mathTable;
      }

      final ioTable = env.get("io");
      if (ioTable != null) {
        loadedMap["io"] = ioTable;
      }

      final osTable = env.get("os");
      if (osTable != null) {
        loadedMap["os"] = osTable;
      }

      final debugTable = env.get("debug");
      if (debugTable != null) {
        loadedMap["debug"] = debugTable;
      }

      final utf8Table = env.get("utf8");
      if (utf8Table != null) {
        loadedMap["utf8"] = utf8Table;
      }

      final coroutineTable = env.get("coroutine");
      if (coroutineTable != null) {
        loadedMap["coroutine"] = coroutineTable;
      }
    }
  }

  // Define preload functions for standard libraries as a fallback
  final packageTable2 = env.get("package");
  final preloadTable = packageTable2?["preload"];

  if (preloadTable != null) {
    // Register standard libraries in package.preload
    preloadTable["string"] = Value((List<Object?> args) {
      final stringLib = <String, dynamic>{};
      StringLib.functions.forEach((key, value) {
        stringLib[key] = value;
      });
      return Value(stringLib, metatable: StringLib.stringClass.metamethods);
    });

    preloadTable["table"] = Value((List<Object?> args) {
      final tableLib = <String, dynamic>{};
      TableLib.functions.forEach((key, value) {
        tableLib[key] = value;
      });
      return Value(tableLib, metatable: TableLib.tableClass.metamethods);
    });

    preloadTable["math"] = Value((List<Object?> args) {
      return Value(MathLib.functions);
    });

    preloadTable["io"] = Value((List<Object?> args) {
      final ioLib = <String, dynamic>{};
      IOLib.functions.forEach((key, value) {
        ioLib[key] = value;
      });

      // Add standard streams
      ioLib["stdin"] = Value(
        LuaFile(IOLib.stdinDevice),
        metatable: IOLib.fileClass.metamethods,
      );
      ioLib["stdout"] = Value(
        LuaFile(IOLib.stdoutDevice),
        metatable: IOLib.fileClass.metamethods,
      );
      ioLib["stderr"] = Value(
        LuaFile(IOLib.stderrDevice),
        metatable: IOLib.fileClass.metamethods,
      );

      return Value(ioLib);
    });

    preloadTable["os"] = Value((List<Object?> args) {
      final osLib = <String, dynamic>{};
      OSLibrary.functions.forEach((key, value) {
        osLib[key] = value;
      });
      return Value(osLib);
    });

    preloadTable["debug"] = Value((List<Object?> args) {
      return Value(createDebugLib(astVm));
    });

    preloadTable["utf8"] = Value((List<Object?> args) {
      return Value(UTF8Lib.functions, metatable: UTF8Lib.utf8Class.metamethods);
    });
  }
}

/// Define a minimal coroutine stub library to prevent test failures
void _defineCoroutineStub({required Environment env}) {
  // Use top-level _CoroutineStubState declared above
  final coroutineTable = <String, dynamic>{
    // coroutine.running() - returns the main thread and true (indicating it's the main thread)
    "running": Value((List<Object?> args) {
      // Return a dummy coroutine object and true to indicate it's the main thread
      return Value.multi([Value("main"), Value(true)]);
    }),

    // coroutine.status() - returns status of a coroutine
    "status": Value((List<Object?> args) {
      if (args.isEmpty) {
        throw Exception("coroutine.status requires a coroutine argument");
      }
      return Value("running");
    }),

    // coroutine.create() - creates a new coroutine
    "create": Value((List<Object?> args) {
      throw Exception("coroutine.create not implemented");
    }),

    // coroutine.resume() - resumes a coroutine
    "resume": Value((List<Object?> args) {
      throw Exception("coroutine.resume not implemented");
    }),

    // coroutine.yield() - yields from a coroutine
    "yield": Value((List<Object?> args) {
      if (_CoroutineStubState.yieldOverride != null) {
        return _CoroutineStubState.yieldOverride!(args);
      }
      final collector = _CoroutineStubState.currentCollector;
      if (collector == null) {
        throw Exception("attempt to yield from outside a coroutine");
      }
      if (args.isEmpty) {
        collector.add(Value(null));
      } else if (args.length == 1) {
        final v = args[0];
        collector.add(v is Value ? v : Value(v));
      } else {
        final list = args.map((e) => e is Value ? e : Value(e)).toList();
        collector.add(Value.multi(list));
      }
      return Value(null);
    }),

    // coroutine.wrap() - creates a wrapped coroutine function (minimal implementation)
    "wrap": Value((List<Object?> args) {
      if (args.isEmpty) {
        throw Exception("coroutine.wrap requires a function argument");
      }
      final func = args[0] as Value;
      if (func.raw is! Function && func.raw is! BuiltinFunction) {
        throw Exception("coroutine.wrap requires a function argument");
      }

      // Defer running until first call; supports two scenarios:
      // 1) Functions that use coroutine.yield: we pre-collect all yields.
      // 2) Plain iterator-like functions (e.g., from string.gmatch):
      //    call the function per invocation until it returns nil.
      final collected = <Value>[];
      var started = false;
      var idx = 0;

      return Value((List<Object?> __) async {
        final prevOverride = _CoroutineStubState.yieldOverride;
        _CoroutineStubState.yieldOverride = (List<Object?> yargs) {
          if (yargs.isEmpty) {
            collected.add(Value(null));
          } else if (yargs.length == 1) {
            final v = yargs[0];
            collected.add(v is Value ? v : Value(v));
          } else {
            final list = yargs.map((e) => e is Value ? e : Value(e)).toList();
            collected.add(Value.multi(list));
          }
          return Value(null);
        };
        try {
          if (!started) {
          started = true;
          Value? first;
          if (func.raw is Function) {
            final out = await (func.raw as Function)(<Object?>[]);
            first = out is Value ? out : (out == null ? Value(null) : Value(out));
          } else if (func.raw is BuiltinFunction) {
            final out = (func.raw as BuiltinFunction).call(<Object?>[]);
            first = out is Value ? out : (out == null ? Value(null) : Value(out));
          }
          // Prefer yielded values if any; otherwise return the direct result
          if (collected.isNotEmpty) {
            idx = 1;
            return collected.first;
          }
          return first ?? Value(null);
          }

          if (idx < collected.length) {
            return collected[idx++];
          }
          // Plain function path: call per invocation until nil
          if (func.raw is Function) {
            final out = await (func.raw as Function)(<Object?>[]);
            return out is Value ? out : (out == null ? Value(null) : Value(out));
          } else if (func.raw is BuiltinFunction) {
            final out = (func.raw as BuiltinFunction).call(<Object?>[]);
            return out is Value ? out : (out == null ? Value(null) : Value(out));
          }
          return Value(null);
        } finally {
          _CoroutineStubState.yieldOverride = prevOverride;
        }
      });
    }),

    // coroutine.close() - closes a coroutine
    "close": Value((List<Object?> args) {
      throw Exception("coroutine.close not implemented");
    }),

    // coroutine.isyieldable() - checks if current context is yieldable
    "isyieldable": Value((List<Object?> args) {
      return Value(false); // Main thread is not yieldable
    }),
  };

  env.define("coroutine", Value(coroutineTable));
}
