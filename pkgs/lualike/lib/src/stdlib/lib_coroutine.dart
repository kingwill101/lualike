// ignore_for_file: unused_element

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/exceptions.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'library.dart';

/// Minimal coroutine stub state to support coroutine.wrap/yield pre-collection
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

/// Coroutine library implementation using the Library system
class CoroutineLibrary extends Library {
  @override
  String get name => "coroutine";

  @override
  Map<String, Function>? getMetamethods(Interpreter interpreter) => {
    "__index": (List<Object?> args) {
      final _ = args[0] as Value;
      final key = args[1] as Value;

      // Convert key to string if needed
      final keyStr = key.raw is String ? key.raw as String : key.toString();

      // Return the function from our registry if it exists
      switch (keyStr) {
        case "running":
          return _CoroutineRunning();
        case "status":
          return _CoroutineStatus();
        case "create":
          return _CoroutineCreate();
        case "resume":
          return _CoroutineResume();
        case "yield":
          return _CoroutineYield();
        case "wrap":
          return _CoroutineWrap(interpreter);
        case "close":
          return _CoroutineClose();
        case "isyieldable":
          return _CoroutineIsYieldable();
        default:
          return Value(null);
      }
    },
  };

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all coroutine functions
    context.define("running", _CoroutineRunning());
    context.define("status", _CoroutineStatus());
    context.define("create", _CoroutineCreate());
    context.define("resume", _CoroutineResume());
    context.define("yield", _CoroutineYield());
    context.define("wrap", _CoroutineWrap(interpreter!));
    context.define("close", _CoroutineClose());
    context.define("isyieldable", _CoroutineIsYieldable());
  }
}

class _CoroutineRunning extends BuiltinFunction {
  _CoroutineRunning() : super();

  @override
  Object? call(List<Object?> args) {
    // Return a dummy coroutine object and true to indicate it's the main thread
    return Value.multi([Value("main"), Value(true)]);
  }
}

class _CoroutineStatus extends BuiltinFunction {
  _CoroutineStatus() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'status' (thread expected, got no value)",
      );
    }
    return Value("running");
  }
}

class _CoroutineCreate extends BuiltinFunction {
  _CoroutineCreate() : super();

  @override
  Object? call(List<Object?> args) {
    throw Exception("coroutine.create not implemented");
  }
}

class _CoroutineResume extends BuiltinFunction {
  _CoroutineResume() : super();

  @override
  Object? call(List<Object?> args) {
    throw Exception("coroutine.resume not implemented");
  }
}

class _CoroutineYield extends BuiltinFunction {
  _CoroutineYield() : super();

  @override
  Object? call(List<Object?> args) {
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
  }
}

class _CoroutineWrap extends BuiltinFunction {
  _CoroutineWrap(Interpreter super.interpreter);

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'wrap' (function expected, got no value)",
      );
    }

    final func = args[0] as Value;
    if (func.raw is! Function && func.raw is! BuiltinFunction) {
      throw LuaError.typeError(
        "bad argument #1 to 'wrap' (function expected, got ${NumberUtils.typeName(func.raw)})",
      );
    }

    // Defer running until first call; supports two scenarios:
    // 1) Functions that use coroutine.yield: we pre-collect all yields.
    // 2) Plain iterator-like functions (e.g., from string.gmatch):
    //    call the function per invocation until it returns nil.
    final collected = <Value>[];
    var started = false;
    var idx = 0;

    return Value((List<Object?> args) async {
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
          try {
            if (func.raw is Function) {
              final out = await (func.raw as Function)(args);
              first = out is Value
                  ? out
                  : (out == null ? Value(null) : Value(out));
            } else if (func.raw is BuiltinFunction) {
              final out = (func.raw as BuiltinFunction).call(args);
              first = out is Value
                  ? out
                  : (out == null ? Value(null) : Value(out));
            }
          } on TailCallException catch (t) {
            final currentVm = interpreter;
            if (currentVm == null) {
              rethrow;
            }
            final callee = t.functionValue is Value
                ? t.functionValue as Value
                : Value(t.functionValue);
            final normalizedArgs = t.args
                .map((a) => a is Value ? a : Value(a))
                .toList();
            final out = await currentVm.callFunction(callee, normalizedArgs);
            first = out is Value
                ? out
                : (out == null ? Value(null) : Value(out));
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
        try {
          if (func.raw is Function) {
            final out = await (func.raw as Function)(args);
            return out is Value
                ? out
                : (out == null ? Value(null) : Value(out));
          } else if (func.raw is BuiltinFunction) {
            final out = (func.raw as BuiltinFunction).call(args);
            return out is Value
                ? out
                : (out == null ? Value(null) : Value(out));
          }
        } on TailCallException catch (t) {
          final currentVm = interpreter;
          if (currentVm == null) {
            rethrow;
          }
          final callee = t.functionValue is Value
              ? t.functionValue as Value
              : Value(t.functionValue);
          final normalizedArgs = t.args
              .map((a) => a is Value ? a : Value(a))
              .toList();
          final out = await currentVm.callFunction(callee, normalizedArgs);
          return out is Value ? out : (out == null ? Value(null) : Value(out));
        }
        return Value(null);
      } finally {
        _CoroutineStubState.yieldOverride = prevOverride;
      }
    });
  }
}

class _CoroutineClose extends BuiltinFunction {
  _CoroutineClose() : super();

  @override
  Object? call(List<Object?> args) {
    throw Exception("coroutine.close not implemented");
  }
}

class _CoroutineIsYieldable extends BuiltinFunction {
  _CoroutineIsYieldable() : super();

  @override
  Object? call(List<Object?> args) {
    return Value(false); // Main thread is not yieldable
  }
}
