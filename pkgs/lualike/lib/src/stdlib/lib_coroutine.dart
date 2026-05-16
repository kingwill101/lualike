import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/stdlib/doc.dart';
import 'package:lualike/src/value.dart';

import 'library.dart';

Value _threadValue(LuaRuntime interpreter, Coroutine coroutine) =>
    Value(coroutine, interpreter: interpreter);

Coroutine _expectCoroutine(Object? raw, String functionName, int index) {
  final target = rawLuaSlot(raw);
  if (target is! Coroutine) {
    throw LuaError.typeError(
      "bad argument #$index to '$functionName' "
      "(thread expected, got ${NumberUtils.typeName(target)})",
    );
  }
  return target;
}

FunctionBody? _requireFunctionBody(Value functionValue, String functionName) {
  final raw = rawLuaSlot(functionValue);
  final FunctionBody? body =
      functionValue.functionBody ?? (raw is FunctionBody ? raw : null);
  if (body != null) {
    return body;
  }

  // Bytecode-backed Lua callables (LuaCallableArtifact) are produced by the
  // bytecode VM and must be treated as callable for coroutine creation, even
  // though they don't carry an AST FunctionBody. Narrowing this check would
  // silently break coroutines over bytecode closures.
  if (raw is LuaCallableArtifact ||
      raw is Function ||
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

Object? _resumeResultToValue(Object? resumeResult) {
  final resultValues = luaResultValues(resumeResult);
  if (resultValues == null) {
    return resumeResult;
  }
  return LuaResults(resultValues);
}

/// Coroutine library implementation using the Library system.
class CoroutineLibrary extends Library {
  @override
  String get name => "coroutine";

  @override
  String get description => 'Coroutine support for cooperative multitasking.';

  @override
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => {
    "__index": (List<Object?> args) {
      final keyValue = args[1];
      final rawKey = rawLuaSlot(keyValue);
      final key = rawKey is String ? rawKey : keyValue.toString();

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
          return interpreter.constantPrimitiveValue(null);
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

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Returns the running coroutine and a boolean indicating if it is the main thread.',
    params: [],
    returns: 'The coroutine object and a boolean.',
    category: 'coroutine',
    example: 'local co, isMain = coroutine.running()',
  );

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    final Coroutine main = _interpreter.getMainThread();
    final Coroutine current = Coroutine.active ?? main;
    final isMain = identical(current, main);
    return LuaResults([_threadValue(_interpreter, current), isMain]);
  }
}

class _CoroutineStatus extends BuiltinFunction {
  _CoroutineStatus(this._interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Returns the status of a coroutine: "running", "suspended", "normal", or "dead".',
    params: [DocParam('co', 'thread', 'The coroutine to check.')],
    returns: 'The status string.',
    category: 'coroutine',
    example: 'print(coroutine.status(co))',
  );

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'status' (thread expected, got no value)",
      );
    }

    final Coroutine coroutine = _expectCoroutine(args[0], "status", 1);
    return valueFromLuaSlot(
      _interpreter,
      _statusToString(_interpreter, coroutine),
    );
  }
}

class _CoroutineCreate extends BuiltinFunction {
  _CoroutineCreate(this._interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Creates a new coroutine from a function.',
    params: [DocParam('f', 'function', 'The function for the coroutine body.')],
    returns: 'A new coroutine (thread).',
    category: 'coroutine',
    example: 'local co = coroutine.create(function() print("hello") end)',
  );

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'create' (function expected, got no value)",
      );
    }

    final functionValue = valueFromLuaSlot(_interpreter, args[0]);
    if (!functionValue.isCallable()) {
      throw LuaError.typeError(
        "bad argument #1 to 'create' "
        "(function expected, got "
        "${NumberUtils.typeName(rawLuaSlot(functionValue))})",
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

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Resumes execution of a coroutine, passing values as arguments.',
    params: [
      DocParam('co', 'thread', 'The coroutine to resume.'),
      DocParam(
        '...',
        'any',
        'Values to pass to the coroutine.',
        optional: true,
      ),
    ],
    returns: 'true if no error, plus values yielded/returned by the coroutine.',
    category: 'coroutine',
    example: 'local ok, res = coroutine.resume(co, 42)',
  );

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
      return LuaResults([false, "cannot resume main thread"]);
    }

    final Coroutine? previous = _interpreter.getCurrentCoroutine();
    if (previous != null &&
        previous != coroutine &&
        previous != main &&
        previous.status != CoroutineStatus.dead) {
      previous.status = CoroutineStatus.normal;
    }

    final resumeArgs = _cloneArgs(args.length > 1 ? args.sublist(1) : const []);
    final result = await coroutine.resume(resumeArgs);
    return _resumeResultToValue(result);
  }
}

class _CoroutineYield extends BuiltinFunction {
  _CoroutineYield(this._interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Suspends the running coroutine and returns values to the resumer.',
    params: [DocParam('...', 'any', 'Values to yield back.', optional: true)],
    returns: 'The values passed to coroutine.resume on the next resume.',
    category: 'coroutine',
    example: 'coroutine.yield("paused")',
  );

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
    // Unreachable, included for completeness.
    return _interpreter.constantPrimitiveValue(null);
  }
}

class _CoroutineWrap extends BuiltinFunction {
  _CoroutineWrap(this._interpreter);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary:
        'Wraps a function into a coroutine-based function that auto-resumes.',
    params: [DocParam('f', 'function', 'The function to wrap.')],
    returns: 'A wrapped function that creates and resumes a coroutine.',
    category: 'coroutine',
    example: 'local f = coroutine.wrap(function() print("hi") end)',
  );

  final LuaRuntime _interpreter;

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError.typeError(
        "bad argument #1 to 'wrap' (function expected, got no value)",
      );
    }

    final functionValue = valueFromLuaSlot(_interpreter, args[0]);
    if (!functionValue.isCallable()) {
      throw LuaError.typeError(
        "bad argument #1 to 'wrap' "
        "(function expected, got "
        "${NumberUtils.typeName(rawLuaSlot(functionValue))})",
      );
    }

    final body = _requireFunctionBody(functionValue, "wrap");
    final closureEnv = _resolveClosureEnvironment(_interpreter, functionValue);
    final coroutine = Coroutine(functionValue, body, closureEnv);
    _interpreter.registerCoroutine(coroutine);
    return valueFromLuaSlot(
      _interpreter,
      _WrappedCoroutineFunction(_interpreter, coroutine),
    );
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
    final resumeResult = await _coroutine.resume(_cloneArgs(callArgs));

    final resultValues = luaResultValues(resumeResult);
    if (resultValues == null) {
      return resumeResult;
    }

    final raw = resultValues;
    if (raw.isEmpty) {
      return _interpreter.constantPrimitiveValue(null);
    }

    final success = isLuaTruthy(raw.first);
    if (!success) {
      final Object? errValue = raw.length > 1
          ? raw[1]
          : _interpreter.constantPrimitiveValue(null);
      throw valueFromLuaSlot(_interpreter, errValue);
    }

    if (raw.length == 1) {
      return const LuaResults.empty();
    }

    final values = raw.sublist(1);
    if (values.length == 1) {
      return values.first;
    }
    return LuaResults(values);
  }
}

class _CoroutineClose extends BuiltinFunction {
  _CoroutineClose([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Closes a coroutine, setting it to the dead state.',
    params: [DocParam('co', 'thread', 'The coroutine to close.')],
    returns: 'true if successful.',
    category: 'coroutine',
    example: 'coroutine.close(co)',
  );

  Object? _closeResultToValue(LuaRuntime runtime, List<Object?> result) {
    if (result.length == 1) {
      return valueFromLuaSlot(runtime, result.first);
    }
    return LuaResults(result);
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
    final normalizedError = rawLuaSlot(error);
    final CoroutineStatus status = _closeStatus(runtime, coroutine);

    switch (status) {
      case CoroutineStatus.dead:
      case CoroutineStatus.suspended:
        final List<Object?> result = await coroutine.close(normalizedError);
        return _closeResultToValue(runtime, result);
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
        return _closeResultToValue(runtime, result);
    }
  }
}

class _CoroutineIsYieldable extends BuiltinFunction {
  _CoroutineIsYieldable([super.interpreter]);

  @override
  FunctionDoc? get doc => FunctionDoc(
    summary: 'Returns true if the running coroutine can yield.',
    params: [],
    returns: 'true if yieldable, false otherwise.',
    category: 'coroutine',
    example: 'print(coroutine.isyieldable())',
  );

  @override
  Object? call(List<Object?> args) {
    final Coroutine main = interpreter!.getMainThread();

    if (args.isEmpty) {
      final Coroutine current = Coroutine.active ?? main;
      return primitiveValue(current.isYieldable(main));
    }

    final Coroutine coroutine = _expectCoroutine(args[0], "isyieldable", 1);
    return primitiveValue(coroutine.isYieldable(main));
  }
}
