import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/value.dart';

import 'library.dart';

Value _threadValue(LuaRuntime interpreter, Coroutine coroutine) =>
    Value(coroutine, interpreter: interpreter);

Coroutine _expectCoroutine(Object? raw, String functionName, int index) {
  final value = raw is Value ? raw : Value(raw);
  if (value.raw is! Coroutine) {
    throw LuaError.typeError(
      "bad argument #$index to '$functionName' "
      "(thread expected, got ${NumberUtils.typeName(value.raw)})",
    );
  }
  return value.raw as Coroutine;
}

FunctionBody? _requireFunctionBody(Value functionValue, String functionName) {
  final FunctionBody? body =
      functionValue.functionBody ??
      (functionValue.raw is FunctionBody
          ? functionValue.raw as FunctionBody
          : null);
  if (body != null) {
    return body;
  }

  final raw = functionValue.raw;
  if (raw is Function ||
      raw is BuiltinFunction ||
      raw is FunctionDef ||
      raw is FunctionLiteral ||
      raw is FunctionBody) {
    return null;
  }

  throw LuaError.typeError(
    "bad argument #1 to '$functionName' "
    "(Lua function expected, got ${NumberUtils.typeName(raw)})",
  );
}

Environment _resolveClosureEnvironment(
  LuaRuntime interpreter,
  Value functionValue,
) {
  return functionValue.closureEnvironment ?? interpreter.getCurrentEnv();
}

List<Object?> _cloneArgs(List<Object?> args) =>
    args.isEmpty ? const [] : List<Object?>.from(args);

bool _isTrue(Object? value) {
  final dynamic raw = value is Value ? value.raw : value;
  return raw != null && raw != false;
}

String _statusToString(LuaRuntime interpreter, Coroutine coroutine) {
  final Coroutine main = interpreter.getMainThread();
  final Coroutine? current = Coroutine.active;

  if (identical(coroutine, current ?? main)) {
    return "running";
  }

  return switch (coroutine.status) {
    CoroutineStatus.running => "normal",
    CoroutineStatus.normal => "normal",
    CoroutineStatus.suspended => "suspended",
    CoroutineStatus.dead => "dead",
  };
}

CoroutineStatus _closeStatus(LuaRuntime interpreter, Coroutine coroutine) {
  final Coroutine main = interpreter.getMainThread();
  final Coroutine current =
      Coroutine.active ?? interpreter.getCurrentCoroutine() ?? main;

  if (identical(coroutine, current)) {
    return CoroutineStatus.running;
  }

  return switch (coroutine.status) {
    CoroutineStatus.running => CoroutineStatus.normal,
    final status => status,
  };
}

Value _resumeResultToValue(Value resumeResult) {
  if (!resumeResult.isMulti) {
    return resumeResult;
  }
  final raw = resumeResult.raw as List<Object?>;
  return Value.multi(raw);
}

/// Coroutine library implementation using the Library system.
class CoroutineLibrary extends Library {
  @override
  String get name => "coroutine";

  @override
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => {
    "__index": (List<Object?> args) {
      final _ = args[0] as Value;
      final keyValue = args[1] as Value;
      final key = keyValue.raw is String
          ? keyValue.raw as String
          : keyValue.toString();

      switch (key) {
        case "running":
          return _CoroutineRunning(interpreter);
        case "status":
          return _CoroutineStatus(interpreter);
        case "create":
          return _CoroutineCreate(interpreter);
        case "resume":
          return _CoroutineResume(interpreter);
        case "yield":
          return _CoroutineYield(interpreter);
        case "wrap":
          return _CoroutineWrap(interpreter);
        case "close":
          return _CoroutineClose(interpreter);
        case "isyieldable":
          return _CoroutineIsYieldable(interpreter);
        default:
          return Value(null);
      }
    },
  };

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final vm = interpreter!;
    context.define("running", _CoroutineRunning(vm));
    context.define("status", _CoroutineStatus(vm));
    context.define("create", _CoroutineCreate(vm));
    context.define("resume", _CoroutineResume(vm));
    context.define("yield", _CoroutineYield(vm));
    context.define("wrap", _CoroutineWrap(vm));
    context.define("close", _CoroutineClose(vm));
    context.define("isyieldable", _CoroutineIsYieldable(vm));
  }
}

class _CoroutineRunning extends BuiltinFunction {
  _CoroutineRunning(this._interpreter);

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    final Coroutine main = _interpreter.getMainThread();
    final Coroutine current = Coroutine.active ?? main;
    final isMain = identical(current, main);
    return Value.multi([_threadValue(_interpreter, current), Value(isMain)]);
  }
}

class _CoroutineStatus extends BuiltinFunction {
  _CoroutineStatus(this._interpreter);

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'status' (thread expected, got no value)",
      );
    }

    final Coroutine coroutine = _expectCoroutine(args[0], "status", 1);
    return Value(_statusToString(_interpreter, coroutine));
  }
}

class _CoroutineCreate extends BuiltinFunction {
  _CoroutineCreate(this._interpreter);

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'create' (function expected, got no value)",
      );
    }

    final Value functionValue = args[0] is Value
        ? args[0] as Value
        : Value(args[0]);
    if (!functionValue.isCallable()) {
      throw LuaError.typeError(
        "bad argument #1 to 'create' "
        "(function expected, got ${NumberUtils.typeName(functionValue.raw)})",
      );
    }

    final body = _requireFunctionBody(functionValue, "create");
    final closureEnv = _resolveClosureEnvironment(_interpreter, functionValue);
    final coroutine = Coroutine(functionValue, body, closureEnv);
    _interpreter.registerCoroutine(coroutine);
    return _threadValue(_interpreter, coroutine);
  }
}

class _CoroutineResume extends BuiltinFunction {
  _CoroutineResume(this._interpreter);

  final LuaRuntime _interpreter;

  @override
  Future<Object?> call(List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'resume' (thread expected, got no value)",
      );
    }

    final Coroutine coroutine = _expectCoroutine(args[0], "resume", 1);
    final Coroutine main = _interpreter.getMainThread();
    if (identical(coroutine, main)) {
      return Value.multi([Value(false), Value("cannot resume main thread")]);
    }

    final Coroutine? previous = _interpreter.getCurrentCoroutine();
    if (previous != null &&
        previous != coroutine &&
        previous != main &&
        previous.status != CoroutineStatus.dead) {
      previous.status = CoroutineStatus.normal;
    }

    final resumeArgs = _cloneArgs(args.length > 1 ? args.sublist(1) : const []);
    final Value result = await coroutine.resume(resumeArgs);
    return _resumeResultToValue(result);
  }
}

class _CoroutineYield extends BuiltinFunction {
  _CoroutineYield(this._interpreter);

  final LuaRuntime _interpreter;

  @override
  Future<Object?> call(List<Object?> args) async {
    final Coroutine current =
        Coroutine.active ??
        _interpreter.getCurrentCoroutine() ??
        _interpreter.getMainThread();
    final Coroutine main = _interpreter.getMainThread();
    if (identical(current, main)) {
      throw LuaError("attempt to yield from outside a coroutine");
    }
    if (!_interpreter.isYieldable) {
      throw LuaError("attempt to yield across a C-call boundary");
    }

    await current.yield_(args);
    return Value(null); // Unreachable, included for completeness
  }
}

class _CoroutineWrap extends BuiltinFunction {
  _CoroutineWrap(this._interpreter);

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'wrap' (function expected, got no value)",
      );
    }

    final Value functionValue = args[0] is Value
        ? args[0] as Value
        : Value(args[0]);
    if (!functionValue.isCallable()) {
      throw LuaError.typeError(
        "bad argument #1 to 'wrap' "
        "(function expected, got ${NumberUtils.typeName(functionValue.raw)})",
      );
    }

    final body = _requireFunctionBody(functionValue, "wrap");
    final closureEnv = _resolveClosureEnvironment(_interpreter, functionValue);
    final coroutine = Coroutine(functionValue, body, closureEnv);
    _interpreter.registerCoroutine(coroutine);
    return Value(_WrappedCoroutineFunction(_interpreter, coroutine));
  }
}

class _WrappedCoroutineFunction extends BuiltinFunction
    implements BuiltinFunctionGcRefs {
  _WrappedCoroutineFunction(this._interpreter, this._coroutine);

  final LuaRuntime _interpreter;
  final Coroutine _coroutine;

  @override
  Iterable<Object?> getGcReferences() sync* {
    yield _coroutine;
  }

  @override
  Future<Object?> call(List<Object?> callArgs) async {
    final Value resumeResult = await _coroutine.resume(_cloneArgs(callArgs));

    if (!resumeResult.isMulti) {
      return resumeResult;
    }

    final raw = resumeResult.raw as List<Object?>;
    if (raw.isEmpty) {
      return Value(null);
    }

    final success = _isTrue(raw.first);
    if (!success) {
      final Object? errValue = raw.length > 1 ? raw[1] : Value(null);
      throw errValue is Value ? errValue : Value(errValue);
    }

    if (raw.length == 1) {
      return Value.multi(const <Object?>[]);
    }

    final values = raw
        .sublist(1)
        .map((v) => v is Value ? v : Value(v))
        .toList();
    if (values.length == 1) {
      return values.first;
    }
    return Value.multi(values);
  }
}

class _CoroutineClose extends BuiltinFunction {
  _CoroutineClose([super.interpreter]);

  Object? _closeResultToValue(List<Object?> result) {
    if (result.length == 1) {
      final value = result.first;
      return value is Value ? value : Value(value);
    }
    return Value.multi(result);
  }

  @override
  Future<Object?> call(List<Object?> args) async {
    final LuaRuntime runtime = interpreter!;
    final Coroutine main = runtime.getMainThread();
    final Coroutine current =
        Coroutine.active ?? runtime.getCurrentCoroutine() ?? main;

    final Coroutine coroutine = args.isEmpty
        ? current
        : _expectCoroutine(args[0], "close", 1);
    final Object? error = args.isEmpty
        ? null
        : args.length > 1
        ? args[1]
        : null;
    final normalizedError = error is Value ? error.raw : error;
    final CoroutineStatus status = _closeStatus(runtime, coroutine);

    switch (status) {
      case CoroutineStatus.dead:
      case CoroutineStatus.suspended:
        final List<Object?> result = await coroutine.close(normalizedError);
        return _closeResultToValue(result);
      case CoroutineStatus.normal:
        throw LuaError(
          "cannot close a ${_statusToString(runtime, coroutine)} coroutine",
        );
      case CoroutineStatus.running:
        if (identical(coroutine, main)) {
          throw LuaError("cannot close main thread");
        }
        final List<Object?> result = await coroutine.close(normalizedError);
        if (identical(coroutine, current)) {
          throw CoroutineCloseSignal(result);
        }
        return _closeResultToValue(result);
    }
  }
}

class _CoroutineIsYieldable extends BuiltinFunction {
  _CoroutineIsYieldable([super.interpreter]);

  @override
  Object? call(List<Object?> args) {
    final Coroutine main = interpreter!.getMainThread();

    if (args.isEmpty) {
      final Coroutine current = Coroutine.active ?? main;
      return Value(current.isYieldable(main));
    }

    final Coroutine coroutine = _expectCoroutine(args[0], "isyieldable", 1);
    return Value(coroutine.isYieldable(main));
  }
}
