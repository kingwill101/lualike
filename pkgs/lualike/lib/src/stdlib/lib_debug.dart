import 'package:lualike/lualike.dart';

import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/gc/memory_credits.dart';
import 'package:lualike/src/io/lua_file.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/stdlib/metatables.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/utils/type.dart' show getLuaType;
import 'library.dart';

String? _debugFrameSourceKey(CallFrame frame) {
  return frame.callable?.functionBody?.span?.sourceUrl?.toString() ??
      frame.scriptPath;
}

Interpreter? _resolveDebugInterpreter(LuaRuntime? runtime) {
  if (runtime case final Interpreter interpreter) {
    return interpreter;
  }
  if (runtime == null) {
    return null;
  }
  try {
    final debugInterpreter = (runtime as dynamic).debugInterpreter;
    if (debugInterpreter is Interpreter) {
      return debugInterpreter;
    }
  } catch (_) {
    // Fall through to environment-bound interpreter discovery.
  }
  final envInterpreter = runtime.getCurrentEnv().interpreter;
  return envInterpreter is Interpreter ? envInterpreter : null;
}

bool _hasStrippedDebugInfo(Value? callable) =>
    callable?.strippedDebugInfo == true;

bool _frameHasStrippedDebugInfo(CallFrame frame) =>
    _hasStrippedDebugInfo(frame.callable);

bool _isInheritedClosureBinding(
  CallFrame frame,
  Environment env,
  String name,
  Box<dynamic> box,
) {
  final closureEnv = frame.callable?.closureEnvironment;
  if (closureEnv == null || identical(env, closureEnv)) {
    return false;
  }
  final inherited = closureEnv.values[name];
  return inherited != null && identical(inherited, box);
}

CallFrame? _resolveDebugCoroutineFrame(Coroutine coroutine, int level) {
  var resolvedLevel = level;
  final initialFrame = coroutine.debugFrameAtLevel(level);
  if (initialFrame == null) {
    return null;
  }
  final originalFrame = initialFrame;
  var frame = initialFrame;
  while (frame.callable != null && frame.callable?.functionBody == null) {
    final nextFrame = coroutine.debugFrameAtLevel(resolvedLevel + 1);
    if (nextFrame == null) {
      break;
    }
    frame = nextFrame;
    resolvedLevel += 1;
  }
  if (frame.callable == null && frame.env != null) {
    final lexicalFrame = coroutine.debugFrameAtLevel(resolvedLevel + 1);
    if (lexicalFrame != null &&
        lexicalFrame.callable?.functionBody != null &&
        _debugFrameSourceKey(lexicalFrame) == _debugFrameSourceKey(frame)) {
      frame = lexicalFrame;
      resolvedLevel += 1;
    }
  }
  if (frame.callable?.functionBody != null &&
      originalFrame.callable == null &&
      _debugFrameSourceKey(originalFrame) == _debugFrameSourceKey(frame) &&
      originalFrame.currentLine > 0 &&
      originalFrame.currentLine > frame.currentLine) {
    frame.currentLine = originalFrame.currentLine;
  }
  if (frame.currentLine <= 0 &&
      coroutine.functionBody != null &&
      coroutine.debugCurrentLine > 0 &&
      (level == 1 || frame.callable?.functionBody != null)) {
    frame.currentLine = coroutine.debugCurrentLine;
  }
  if (level == 1 && coroutine.functionBody != null) {
    final wrappedEnv = frame.env ?? coroutine.debugEnvironment;
    final wrappedCallable = frame.callable?.functionBody != null
        ? frame.callable!
        : Value(
            () => null,
            closureEnvironment: coroutine.closureEnvironment,
            functionBody: coroutine.functionBody,
            functionName: coroutine.functionValue.functionName,
            strippedDebugInfo: coroutine.functionValue.strippedDebugInfo,
          );
    frame = CallFrame(
      coroutine.functionValue.functionName ?? frame.functionName,
      callNode: frame.callNode,
      scriptPath: frame.scriptPath,
      currentLine: frame.currentLine,
      env: wrappedEnv,
      debugName: null,
      debugNameWhat: '',
      callable: wrappedCallable,
      lastDebugHookLine: frame.lastDebugHookLine,
      debugLocals: List<MapEntry<String, Value>>.from(frame.debugLocals),
      ftransfer: 0,
      ntransfer: 0,
      transferValues: const <Value>[],
      extraArgs: frame.extraArgs,
      isDebugHook: frame.isDebugHook,
      isTailCall: frame.isTailCall,
    );
  }
  return frame;
}

class DebugLib {
  static Map<String, BuiltinFunction> functions = {};
}

/// Debug library implementation using the new Library system
class DebugLibrary extends Library {
  @override
  String get name => "debug";

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all debug functions individually
    context.define("debug", _DebugInteractive());
    context.define("gethook", _GetHook(interpreter));
    context.define("getinfo", _GetInfoImpl(interpreter!));
    context.define("getlocal", _GetLocal(interpreter!));
    context.define("getmetatable", _GetMetatable());
    context.define("getregistry", _GetRegistry(interpreter));
    context.define("getupvalue", _GetUpvalue(interpreter!));
    context.define("getuservalue", _GetUserValue());
    context.define("sethook", _SetHook(interpreter));
    context.define("setlocal", _SetLocal(interpreter!));
    context.define("setmetatable", _SetMetatable());
    context.define("setupvalue", _SetUpvalue());
    context.define("setuservalue", _SetUserValue());
    context.define("traceback", _Traceback(interpreter));
    context.define("upvalueid", _UpvalueId());
    context.define("upvaluejoin", _UpvalueJoin());

    // Memory debugging functions
    context.define("memtrace", _MemTrace());
    context.define("memtree", _MemTree());
  }
}

/// Interactive debug console
class _DebugInteractive extends BuiltinFunction {
  _DebugInteractive() : super();
  @override
  dynamic call(List<dynamic> args) async {
    // Simple REPL-like debug console
    Logger.debugLazy(
      () => "Debug Console: Enter 'cont' to continue",
      category: 'Debug',
    );

    while (true) {
      final defaultOutput = IOLib.defaultOutput;
      final outputLuaFile = defaultOutput.raw as LuaFile;
      await outputLuaFile.write('debug> ');

      final defaultInput = IOLib.defaultInput;
      final inputLuaFile = defaultInput.raw as LuaFile;
      final result = await inputLuaFile.read('l');
      final input = result[0]?.toString();

      if (input == 'cont') break;

      // TODO: Implement actual debug command parsing and execution
    }

    return null;
  }
}

class _GetHook extends BuiltinFunction {
  _GetHook(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    final runtime = _resolveDebugInterpreter(interpreter);
    if (runtime == null) {
      return Value.multi([Value(null), Value(null), Value(0)]);
    }
    Coroutine? thread;
    if (args.isNotEmpty &&
        args[0] is Value &&
        (args[0] as Value).raw is Coroutine) {
      thread = (args[0] as Value).raw as Coroutine;
    } else {
      final current = runtime.getCurrentCoroutine();
      final main = runtime.getMainThread();
      if (current != null && !identical(current, main)) {
        thread = current;
      }
    }
    final hook = thread?.debugHookFunction ?? runtime.debugHookFunction;
    if (hook == null) {
      return Value.multi([Value(null), Value(null), Value(0)]);
    }
    return Value.multi([
      hook,
      Value(thread?.debugHookMask ?? runtime.debugHookMask),
      Value(thread?.debugHookCount ?? runtime.debugHookCount),
    ]);
  }
}

class _GetLocal extends BuiltinFunction {
  _GetLocal(LuaRuntime super.i);

  String? _frameSourceKey(CallFrame frame) {
    return frame.callable?.functionBody?.span?.sourceUrl?.toString() ??
        frame.scriptPath;
  }

  int _requireInt(Value value, String name) {
    if (value.raw is! num) {
      throw LuaError("bad argument to 'debug.getlocal' ($name expected)");
    }
    return (value.raw as num).toInt();
  }

  CallFrame _requireFrame(Interpreter runtime, int level) {
    final frame = runtime.getVisibleFrameAtLevel(
      level + 1,
      hideEnclosingDebugHooks: true,
    );
    if (frame == null) {
      throw LuaError(
        "bad argument #1 to 'debug.getlocal' (level out of range)",
      );
    }
    return frame;
  }

  CallFrame _resolveVisibleFrame(
    Interpreter runtime,
    int level, {
    required String functionName,
    required int argNumber,
  }) {
    final originalFrame = runtime.getVisibleFrameAtLevel(
      level + 1,
      hideEnclosingDebugHooks: true,
    );
    var frame = originalFrame;
    if (frame == null) {
      throw LuaError(
        "bad argument #$argNumber to '$functionName' (level out of range)",
      );
    }
    if (frame.callable == null && frame.env != null) {
      final lexicalFrame = runtime.getVisibleFrameAtLevel(
        level + 2,
        hideEnclosingDebugHooks: true,
      );
      if (lexicalFrame != null &&
          lexicalFrame.callable?.functionBody != null &&
          _frameSourceKey(lexicalFrame) == _frameSourceKey(frame)) {
        frame = lexicalFrame;
      }
    }
    if (frame.callable?.functionBody != null) {
      final wrapperFrame =
          originalFrame != null &&
              originalFrame.callable == null &&
              _frameSourceKey(originalFrame) == _frameSourceKey(frame)
          ? originalFrame
          : runtime.getVisibleFrameAtLevel(
              level,
              hideEnclosingDebugHooks: true,
            );
      if (wrapperFrame != null &&
          wrapperFrame.callable == null &&
          _frameSourceKey(wrapperFrame) == _frameSourceKey(frame) &&
          wrapperFrame.currentLine > 0 &&
          wrapperFrame.currentLine > frame.currentLine) {
        frame.currentLine = wrapperFrame.currentLine;
      }
    }
    return frame;
  }

  List<MapEntry<String, Value>> _enumerateFrameLocals(CallFrame frame) {
    if (_frameHasStrippedDebugInfo(frame)) {
      final locals = <MapEntry<String, Value>>[];
      final envs = _activeLocalEnvironments(frame);
      final preferred = <String>{};
      Value? visibleLocalValue(String name) {
        for (final env in envs) {
          final box = env.values[name];
          if (box == null || !box.isLocal) {
            continue;
          }
          if (_isInheritedClosureBinding(frame, env, name, box)) {
            continue;
          }
          final rawValue = box.value;
          return rawValue is Value ? rawValue : Value(rawValue);
        }
        return null;
      }

      bool envHasVisibleLocal(String name) {
        return envs.any((env) {
          final box = env.values[name];
          return box != null &&
              box.isLocal &&
              !_isInheritedClosureBinding(frame, env, name, box);
        });
      }

      if (frame.callable?.functionBody?.isVararg == true &&
          envs.any((env) => env.values.containsKey('...'))) {
        locals.add(MapEntry('(vararg table)', Value(null)));
      }
      for (final entry in frame.debugLocals) {
        locals.add(
          MapEntry('(temporary)', visibleLocalValue(entry.key) ?? entry.value),
        );
        preferred.add(entry.key);
      }
      for (final env in envs) {
        for (final entry in env.values.entries) {
          final box = entry.value;
          if (!box.isLocal) continue;
          if (_isInheritedClosureBinding(frame, env, entry.key, box)) {
            continue;
          }
          if (entry.key == '...' ||
              entry.key == '_ENV' ||
              entry.key == '_G' ||
              entry.key == '_SCRIPT_PATH' ||
              preferred.contains(entry.key)) {
            continue;
          }
          final rawValue = box.value;
          final value = rawValue is Value ? rawValue : Value(rawValue);
          locals.add(MapEntry('(temporary)', value));
        }
      }
      for (final entry in _staticFrameLocals(frame)) {
        if (entry.key != '(temporary)' &&
            (preferred.contains(entry.key) || envHasVisibleLocal(entry.key))) {
          continue;
        }
        locals.add(MapEntry('(temporary)', entry.value));
      }
      if (frame.ntransfer > 0) {
        for (var i = 0; i < frame.ntransfer; i++) {
          locals.add(MapEntry('(temporary)', frame.transferValues[i]));
        }
      }
      return locals;
    }

    final locals = <MapEntry<String, Value>>[];
    final envs = _activeLocalEnvironments(frame);
    final preferred = <String>{};
    final exposesVarargTable =
        frame.callable?.functionBody?.isVararg == true &&
        envs.any((env) => env.values.containsKey('...'));
    bool envHasVisibleLocal(String name) {
      return envs.any((env) {
        final box = env.values[name];
        return box != null &&
            box.isLocal &&
            !_isInheritedClosureBinding(frame, env, name, box);
      });
    }

    if (exposesVarargTable) {
      locals.add(MapEntry('(vararg table)', Value(null)));
    }
    for (final entry in frame.debugLocals) {
      locals.add(entry);
      preferred.add(entry.key);
    }
    for (final env in envs) {
      for (final entry in env.values.entries) {
        if (!entry.value.isLocal) continue;
        if (_isInheritedClosureBinding(frame, env, entry.key, entry.value)) {
          continue;
        }
        if (entry.key == '...') continue;
        if (entry.key == '_ENV' ||
            entry.key == '_G' ||
            entry.key == '_SCRIPT_PATH') {
          continue;
        }
        if (preferred.contains(entry.key)) continue;
        final rawValue = entry.value.value;
        final value = rawValue is Value ? rawValue : Value(rawValue);
        locals.add(MapEntry(entry.key, value));
      }
    }
    for (final entry in _staticFrameLocals(frame)) {
      if (entry.key != '(temporary)' &&
          (preferred.contains(entry.key) || envHasVisibleLocal(entry.key))) {
        continue;
      }
      locals.add(entry);
    }
    return locals;
  }

  List<Object?>? _frameVarargs(CallFrame frame) {
    final rawValue = _findFrameVarargValue(frame);
    if (rawValue is Value && rawValue.isMulti && rawValue.raw is List) {
      return List<Object?>.from(rawValue.raw as List);
    }
    return null;
  }

  Value? _functionLocalName(Value functionValue, int index) {
    if (index <= 0) {
      return null;
    }
    final functionBody =
        functionValue.functionBody ??
        switch (functionValue.raw) {
          final FunctionDef def => def.body,
          final FunctionLiteral literal => literal.funcBody,
          final FunctionBody body => body,
          _ => null,
        };
    final parameters = functionBody?.parameters;
    if (parameters == null || index > parameters.length) {
      return null;
    }
    return Value(parameters[index - 1].name);
  }

  Value _transferLocalName(CallFrame frame) {
    final isLuaFrame = frame.callable?.functionBody != null;
    return Value(isLuaFrame ? '(temporary)' : '(C temporary)');
  }

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError(
        "debug.getlocal requires thread/function and level arguments",
      );
    }
    final runtime = _resolveDebugInterpreter(interpreter);
    if (runtime == null) {
      return Value.multi([Value(null), Value(null)]);
    }

    Value threadArg;
    Value targetArg;
    Value indexArg;
    final hasThread = args.length >= 3;
    if (hasThread) {
      threadArg = args[0] as Value;
      targetArg = args[1] as Value;
      indexArg = args[2] as Value;
    } else {
      threadArg = Value(null);
      targetArg = args[0] as Value;
      indexArg = args[1] as Value;
    }

    final index = _requireInt(indexArg, 'number');

    if (!hasThread && targetArg.raw is num) {
      final level = _requireInt(targetArg, 'number');
      if (level == 0) {
        if (index <= 0 || index > args.length) {
          return Value.multi([Value(null), Value(null)]);
        }
        return Value.multi([Value("(C temporary)"), args[index - 1] as Value]);
      }
      final frame = _resolveVisibleFrame(
        runtime,
        level,
        functionName: 'debug.getlocal',
        argNumber: 1,
      );
      if (index < 0) {
        final varargs = _frameVarargs(frame);
        final varargIndex = -index;
        if (varargs == null || varargIndex > varargs.length) {
          return Value.multi([Value(null), Value(null)]);
        }
        final value = varargs[varargIndex - 1];
        return Value.multi([
          Value('(vararg)'),
          value is Value ? value : Value(value),
        ]);
      }
      if (frame.ntransfer > 0 &&
          index >= frame.ftransfer &&
          index < frame.ftransfer + frame.ntransfer) {
        final transferValue = frame.transferValues[index - frame.ftransfer];
        return Value.multi([_transferLocalName(frame), transferValue]);
      }
      final locals = _enumerateFrameLocals(frame);
      if (index <= 0 || index > locals.length) {
        return Value.multi([Value(null), Value(null)]);
      }
      final entry = locals[index - 1];
      return Value.multi([Value(entry.key), entry.value]);
    }

    if (hasThread && threadArg.raw is Coroutine && targetArg.raw is num) {
      final level = _requireInt(targetArg, 'number');
      if (level <= 0) {
        throw LuaError(
          "bad argument #2 to 'debug.getlocal' (level out of range)",
        );
      }
      final frame = _resolveDebugCoroutineFrame(
        threadArg.raw as Coroutine,
        level,
      );
      if (frame == null) {
        throw LuaError(
          "bad argument #2 to 'debug.getlocal' (level out of range)",
        );
      }
      if (index > 0 &&
          frame.ntransfer > 0 &&
          index >= frame.ftransfer &&
          index < frame.ftransfer + frame.ntransfer) {
        final transferValue = frame.transferValues[index - frame.ftransfer];
        return Value.multi([_transferLocalName(frame), transferValue]);
      }
      if (index < 0) {
        final varargs = _frameVarargs(frame);
        final varargIndex = -index;
        if (varargs == null || varargIndex > varargs.length) {
          return Value.multi([Value(null), Value(null)]);
        }
        final value = varargs[varargIndex - 1];
        return Value.multi([
          Value('(vararg)'),
          value is Value ? value : Value(value),
        ]);
      }
      final locals = _enumerateFrameLocals(frame);
      if (index <= 0 || index > locals.length) {
        return Value.multi([Value(null), Value(null)]);
      }
      final entry = locals[index - 1];
      return Value.multi([Value(entry.key), entry.value]);
    }

    final functionValue = hasThread ? targetArg : targetArg;
    final name = _functionLocalName(functionValue, index);
    if (name == null) {
      return Value.multi([Value(null), Value(null)]);
    }
    return Value.multi([name, Value(null)]);
  }
}

class _GetMetatable extends BuiltinFunction {
  _GetMetatable() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) throw LuaError("debug.getmetatable requires a value");
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

class _GetRegistry extends BuiltinFunction {
  _GetRegistry(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    return interpreter?.debugRegistry ?? Value({});
  }
}

class _GetUpvalue extends BuiltinFunction {
  _GetUpvalue(LuaRuntime super.i);

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.getupvalue requires function and index arguments");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value.multi([Value(null), Value(null)]);
    }

    final index = (indexArg.raw as num).toInt();

    if (functionArg.raw case final LuaBytecodeClosure closure) {
      if (index < 1 || index > closure.upvalueCount) {
        return Value.multi([Value(null), Value(null)]);
      }
      return Value.multi([
        Value(
          functionArg.strippedDebugInfo
              ? '(no name)'
              : closure.upvalueName(index - 1),
        ),
        closure.readUpvalue(index - 1),
      ]);
    }

    // Check if the function has explicit upvalues first
    if (functionArg.upvalues != null &&
        index > 0 &&
        index <= functionArg.upvalues!.length) {
      final upvalue = functionArg.upvalues![index - 1];
      final name = upvalue.name;
      final rawValue = upvalue.getValue();
      final value = rawValue is Value ? rawValue : Value(rawValue);
      return Value.multi([
        Value(functionArg.strippedDebugInfo ? '(no name)' : (name ?? '')),
        value,
      ]);
    }

    // For AST-based interpreter, expose the implicit `_ENV` capture in the
    // first upvalue slot when the function does not already surface explicit
    // captures. This matches the upstream 5.5 tests for loaded chunks and
    // plain Lua closures.
    if (index == 1 &&
        functionArg.closureEnvironment != null &&
        (functionArg.upvalues == null || functionArg.upvalues!.isEmpty)) {
      final envValue =
          functionArg.closureEnvironment?.get('_ENV') ??
          functionArg.closureEnvironment?.get('_G') ??
          interpreter?.getCurrentEnv().get('_ENV') ??
          interpreter?.getCurrentEnv().get('_G') ??
          Value(functionArg.closureEnvironment);
      return Value.multi([
        Value(functionArg.strippedDebugInfo ? '(no name)' : '_ENV'),
        envValue,
      ]);
    }

    // For functions without upvalues, return null
    return Value.multi([Value(null), Value(null)]);
  }
}

class _GetUserValue extends BuiltinFunction {
  _GetUserValue() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError(
        "debug.getuservalue requires userdata and index arguments",
      );
    }
    // Return nth user value
    return Value(null);
  }
}

class _SetHook extends BuiltinFunction {
  _SetHook(super.interpreter);

  @override
  Object? call(List<Object?> args) {
    final runtime = _resolveDebugInterpreter(interpreter);
    if (runtime == null) {
      return Value(null);
    }
    Coroutine? thread;
    var index = 0;

    if (args.isNotEmpty &&
        args[0] is Value &&
        (args[0] as Value).raw is Coroutine) {
      thread = (args[0] as Value).raw as Coroutine;
      index = 1;
    } else {
      final current = runtime.getCurrentCoroutine();
      final main = runtime.getMainThread();
      if (current != null && !identical(current, main)) {
        thread = current;
      }
    }

    final targetHook = index < args.length ? args[index] : null;
    if (targetHook == null ||
        (targetHook is Value && (targetHook.isNil || targetHook.raw == null))) {
      if (thread != null) {
        thread.debugHookFunction = null;
        thread.debugHookMask = '';
        thread.debugHookCount = 0;
        thread.debugHookCountRemaining = 0;
      } else {
        runtime.debugHookFunction = null;
        runtime.debugHookMask = '';
        runtime.debugHookCount = 0;
        runtime.debugHookCountRemaining = 0;
        runtime.rememberDebugHookLine(-1);
      }
      return Value(null);
    }

    if (targetHook is! Value || !targetHook.isCallable()) {
      throw LuaError("debug.sethook requires a hook function");
    }

    final hook = targetHook;
    final mask = switch (args.length > index + 1 ? args[index + 1] : null) {
      final Value value when value.raw != null => value.raw.toString(),
      null => '',
      _ => throw LuaError("debug.sethook mask must be a string"),
    };
    final count = switch (args.length > index + 2 ? args[index + 2] : null) {
      final Value value when value.raw is num => (value.raw as num).toInt(),
      null => 0,
      _ => throw LuaError("debug.sethook count must be a number"),
    };

    if (thread != null) {
      thread.debugHookFunction = hook;
      thread.debugHookMask = mask;
      thread.debugHookCount = count;
      thread.resetDebugHookCounter();
    } else {
      runtime.debugHookFunction = hook;
      runtime.debugHookMask = mask;
      runtime.debugHookCount = count;
      runtime.resetDebugHookCounter();
      if (runtime.callStack.getFrameAtLevel(2) case final CallFrame frame?) {
        frame.lastDebugHookLine = frame.currentLine;
        runtime.rememberDebugHookLine(
          frame.currentLine,
          source: frame.scriptPath ?? runtime.currentScriptPath,
        );
      }
    }
    return Value(null);
  }
}

class _SetLocal extends BuiltinFunction {
  _SetLocal(LuaRuntime super.interpreter);

  int _requireInt(Value value) {
    if (value.raw is! num) {
      throw LuaError("bad argument to 'debug.setlocal' (number expected)");
    }
    return (value.raw as num).toInt();
  }

  CallFrame _requireFrame(Interpreter runtime, int level, {int argNumber = 1}) {
    final frame = runtime.getVisibleFrameAtLevel(
      level + 1,
      hideEnclosingDebugHooks: true,
    );
    if (frame == null) {
      throw LuaError(
        "bad argument #$argNumber to 'debug.setlocal' (level out of range)",
      );
    }
    return frame;
  }

  CallFrame _resolveVisibleFrame(Interpreter runtime, int level) {
    final frame = runtime.getVisibleFrameAtLevel(
      level + 1,
      hideEnclosingDebugHooks: true,
    );
    if (frame == null) {
      throw LuaError(
        "bad argument #1 to 'debug.setlocal' (level out of range)",
      );
    }
    return frame;
  }

  List<MapEntry<String, Value>> _enumerateFrameLocals(CallFrame frame) {
    final locals = <MapEntry<String, Value>>[];
    final envs = _activeLocalEnvironments(frame);
    final preferred = <String>{};
    bool envHasVisibleLocal(String name) {
      return envs.any((env) {
        final box = env.values[name];
        return box != null &&
            box.isLocal &&
            !_isInheritedClosureBinding(frame, env, name, box);
      });
    }

    if (frame.callable?.functionBody?.isVararg == true &&
        envs.any((env) => env.values.containsKey('...'))) {
      locals.add(MapEntry('(vararg table)', Value(null)));
    }
    for (final entry in frame.debugLocals) {
      locals.add(entry);
      preferred.add(entry.key);
    }
    for (final env in envs) {
      for (final entry in env.values.entries) {
        if (!entry.value.isLocal) continue;
        if (_isInheritedClosureBinding(frame, env, entry.key, entry.value)) {
          continue;
        }
        if (entry.key == '...') continue;
        if (entry.key == '_ENV' ||
            entry.key == '_G' ||
            entry.key == '_SCRIPT_PATH') {
          continue;
        }
        if (preferred.contains(entry.key)) continue;
        final rawValue = entry.value.value;
        final value = rawValue is Value ? rawValue : Value(rawValue);
        locals.add(MapEntry(entry.key, value));
      }
    }
    for (final entry in _staticFrameLocals(frame)) {
      if (entry.key != '(temporary)' &&
          (preferred.contains(entry.key) || envHasVisibleLocal(entry.key))) {
        continue;
      }
      locals.add(entry);
    }
    return locals;
  }

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw LuaError(
        "debug.setlocal requires thread/function, index and value",
      );
    }
    final runtime = _resolveDebugInterpreter(interpreter);
    if (runtime == null) {
      return Value(null);
    }

    Value targetArg;
    Value indexArg;
    Value valueArg;
    CallFrame? frame;

    if (args.length >= 4 && (args[0] as Value).raw is Coroutine) {
      final thread = args[0] as Value;
      targetArg = args[1] as Value;
      indexArg = args[2] as Value;
      valueArg = args[3] as Value;
      if (targetArg.raw is! num) {
        return Value(null);
      }
      final level = _requireInt(targetArg);
      if (level <= 0) {
        throw LuaError(
          "bad argument #2 to 'debug.setlocal' (level out of range)",
        );
      }
      frame = _resolveDebugCoroutineFrame(thread.raw as Coroutine, level);
      if (frame == null) {
        throw LuaError(
          "bad argument #2 to 'debug.setlocal' (level out of range)",
        );
      }
    } else {
      targetArg = args[0] as Value;
      indexArg = args[1] as Value;
      valueArg = args[2] as Value;
      if (targetArg.raw is! num) {
        return Value(null);
      }
      final level = _requireInt(targetArg);
      if (level <= 0) {
        throw LuaError(
          "bad argument #1 to 'debug.setlocal' (level out of range)",
        );
      }
      frame = _resolveVisibleFrame(runtime, level);
    }

    final index = _requireInt(indexArg);
    if (index < 0) {
      final rawVarargs = _findFrameVarargValue(frame);
      if (rawVarargs is! Value ||
          !rawVarargs.isMulti ||
          rawVarargs.raw is! List) {
        return Value(null);
      }
      final list = List<Object?>.from(rawVarargs.raw as List);
      final varargIndex = -index;
      if (varargIndex <= 0 || varargIndex > list.length) {
        return Value(null);
      }
      list[varargIndex - 1] = valueArg;
      rawVarargs.raw = list;
      return Value('(vararg)');
    }

    final locals = _enumerateFrameLocals(frame);
    if (index <= 0 || index > locals.length) {
      return Value(null);
    }
    final entry = locals[index - 1];
    final envBox = frame.env?.values[entry.key];
    if (envBox != null) {
      envBox.value = valueArg;
      for (var i = 0; i < frame.debugLocals.length; i++) {
        if (frame.debugLocals[i].key == entry.key) {
          frame.debugLocals[i] = MapEntry(entry.key, valueArg);
        }
      }
      return Value(entry.key);
    }

    for (var i = 0; i < frame.debugLocals.length; i++) {
      final local = frame.debugLocals[i];
      if (local.key == entry.key && identical(local.value, entry.value)) {
        local.value.raw = valueArg.raw;
        local.value.metatable = valueArg.metatable;
        local.value.metatableRef = valueArg.metatableRef;
        local.value.upvalues = valueArg.upvalues;
        local.value.interpreter = valueArg.interpreter;
        local.value.functionBody = valueArg.functionBody;
        local.value.closureEnvironment = valueArg.closureEnvironment;
        local.value.functionName = valueArg.functionName;
        local.value.debugLineDefined = valueArg.debugLineDefined;
        frame.debugLocals[i] = MapEntry(entry.key, valueArg);
        return Value(entry.key);
      }
    }

    return Value(null);
  }
}

List<MapEntry<String, Value>> _staticFrameLocals(CallFrame frame) {
  final functionBody = frame.callable?.functionBody;
  final currentLine = frame.currentLine;
  if (functionBody == null || currentLine <= 0) {
    return const <MapEntry<String, Value>>[];
  }

  final locals = <MapEntry<String, Value>>[];

  void collect(List<AstNode> statements) {
    for (final statement in statements) {
      final startLine = statement.span?.start.line == null
          ? null
          : statement.span!.start.line + 1;
      final span = statement.span;
      final endLine = switch (span) {
        null => null,
        _ when span.end.column == 0 && span.end.line > span.start.line =>
          span.end.line,
        _ => span.end.line + 1,
      };
      if (startLine != null && startLine > currentLine) {
        continue;
      }

      switch (statement) {
        case LocalDeclaration(names: final names, exprs: final exprs):
          for (var i = 0; i < names.length; i++) {
            final name = names[i];
            final expr = i < exprs.length ? exprs[i] : null;
            if (expr is FunctionLiteral &&
                endLine != null &&
                currentLine < endLine) {
              locals.add(MapEntry('(temporary)', Value(null)));
            } else {
              locals.add(MapEntry(name.name, Value(null)));
            }
          }
        case LocalFunctionDef(name: final name):
          if (endLine != null && currentLine < endLine) {
            locals.add(MapEntry('(temporary)', Value(null)));
          } else {
            locals.add(MapEntry(name.name, Value(null)));
          }
        default:
          break;
      }
    }
  }

  collect(functionBody.body);
  return locals;
}

List<Environment> _activeLocalEnvironments(CallFrame frame) {
  final currentEnv = frame.env;
  if (currentEnv == null) {
    return const <Environment>[];
  }

  final closureEnv = frame.callable?.closureEnvironment;
  final chain = <Environment>[];
  Environment? env = currentEnv;
  while (env != null) {
    final isClosureBoundary = identical(env, closureEnv);
    if (isClosureBoundary && chain.isNotEmpty) {
      break;
    }
    chain.add(env);
    if (isClosureBoundary || identical(env.parent, closureEnv)) {
      break;
    }
    env = env.parent;
  }

  return chain.reversed.toList(growable: false);
}

dynamic _findFrameVarargValue(CallFrame frame) {
  for (final env in _activeLocalEnvironments(frame).reversed) {
    final value = env.values['...']?.value;
    if (value != null) {
      return value;
    }
  }
  return null;
}

class _SetMetatable extends BuiltinFunction {
  _SetMetatable() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.setmetatable requires value and metatable");
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
    throw LuaError("metatable must be a table or nil");
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

class _SetUpvalue extends BuiltinFunction {
  _SetUpvalue() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 3) {
      throw LuaError("debug.setupvalue requires function, index and value");
    }

    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;
    final newValue = args[2] as Value;

    // Validate that index is a number
    if (indexArg.raw is! num) {
      return Value(null);
    }

    final index = (indexArg.raw as num).toInt();

    if (functionArg.raw case final LuaBytecodeClosure closure) {
      if (index < 1 || index > closure.upvalueCount) {
        return Value(null);
      }
      final oldName = closure.upvalueName(index - 1);
      closure.writeUpvalue(index - 1, newValue);
      return Value(functionArg.strippedDebugInfo ? '(no name)' : oldName);
    }

    // Check if the function has explicit upvalues
    if (functionArg.upvalues != null &&
        index > 0 &&
        index <= functionArg.upvalues!.length) {
      final upvalue = functionArg.upvalues![index - 1];
      Logger.debugLazy(
        () =>
            'debug.setupvalue explicit: name=${upvalue.name} value=${newValue.raw} open=${upvalue.isOpen}',
        category: 'DebugLib',
      );
      final oldName = upvalue.name ?? '';
      upvalue.setValue(newValue.raw);
      return Value(functionArg.strippedDebugInfo ? '(no name)' : oldName);
    }

    // For AST-based interpreter, only modify existing upvalues
    if (functionArg.raw is Function) {
      // Check if upvalues exist and if the index is valid
      if (functionArg.upvalues != null &&
          index > 0 &&
          index <= functionArg.upvalues!.length) {
        final upvalue = functionArg.upvalues![index - 1];
        Logger.debugLazy(
          () =>
              'debug.setupvalue raw: name=${upvalue.name} value=${newValue.raw} open=${upvalue.isOpen}',
          category: 'DebugLib',
        );
        final oldName = upvalue.name ?? '';
        upvalue.setValue(newValue.raw);
        return Value(functionArg.strippedDebugInfo ? '(no name)' : oldName);
      }
    }

    return Value(null);
  }
}

class _SetUserValue extends BuiltinFunction {
  _SetUserValue() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.setuservalue requires userdata and value");
    }

    final target = args[0];
    final userValue = args[1];
    final index = switch (args.length > 2 ? args[2] : null) {
      final Value value when value.raw is num => (value.raw as num).toInt(),
      final num value => value.toInt(),
      null => 1,
      _ => throw LuaError("debug.setuservalue index must be a number"),
    };

    if (target is! Value) {
      throw LuaError(
        "bad argument #1 to 'setuservalue' (userdata expected, got no value)",
      );
    }

    if (target.raw is LuaFile) {
      return Value(null);
    }

    if (!_isFullUserdata(target)) {
      throw LuaError(
        "bad argument #1 to 'setuservalue' "
        "(userdata expected, got ${getLuaType(target)})",
      );
    }

    if (index < 1) {
      return Value(null);
    }

    if (target.raw is Map) {
      final rawMap = target.raw as Map<dynamic, dynamic>;
      rawMap['__uservalue$index'] = userValue is Value
          ? userValue
          : Value(userValue);
    }
    return target;
  }

  bool _isFullUserdata(Value value) {
    final raw = value.raw;
    if (raw == null ||
        raw is bool ||
        raw is num ||
        raw is BigInt ||
        raw is String ||
        raw is LuaString ||
        raw is Map ||
        raw is List ||
        raw is LuaFile ||
        raw is Coroutine ||
        raw is Function ||
        raw is BuiltinFunction ||
        raw is LuaCallableArtifact) {
      return false;
    }
    return getLuaType(value) != 'light userdata';
  }
}

class _Traceback extends BuiltinFunction {
  _Traceback(super.interpreter);

  int _intArg(Value value, int fallback) {
    final raw = value.raw;
    if (raw == null) {
      return fallback;
    }
    if (raw is! num) {
      throw LuaError("bad argument to 'debug.traceback' (number expected)");
    }
    return raw.toInt();
  }

  Iterable<CallFrame> _currentFrames(
    Interpreter runtime,
    int startLevel,
  ) sync* {
    for (var level = startLevel; ; level++) {
      final frame = runtime.getVisibleFrameAtLevel(level);
      if (frame == null) {
        return;
      }
      yield frame;
    }
  }

  Iterable<CallFrame> _coroutineFrames(
    Coroutine coroutine,
    int startLevel,
  ) sync* {
    for (var level = startLevel; ; level++) {
      final frame = _resolveDebugCoroutineFrame(coroutine, level);
      if (frame == null) {
        return;
      }
      yield frame;
    }
  }

  static const int _tracebackHeadLevels = 10;
  static const int _tracebackTailLevels = 11;

  void _appendTracebackFrames(StringBuffer trace, List<CallFrame> frames) {
    final visibleFrames = frames
        .where(_includeTracebackFrame)
        .toList(growable: false);

    if (visibleFrames.length <= _tracebackHeadLevels + _tracebackTailLevels) {
      for (final frame in visibleFrames) {
        trace.writeln("\t${_formatFrame(frame)}");
      }
      return;
    }

    for (final frame in visibleFrames.take(_tracebackHeadLevels)) {
      trace.writeln("\t${_formatFrame(frame)}");
    }

    final skipped =
        visibleFrames.length - _tracebackHeadLevels - _tracebackTailLevels;
    trace.writeln("\t...\t(skipping $skipped levels)");

    for (final frame in visibleFrames.skip(
      visibleFrames.length - _tracebackTailLevels,
    )) {
      trace.writeln("\t${_formatFrame(frame)}");
    }
  }

  bool _includeTracebackFrame(CallFrame frame) {
    final callable = frame.callable;
    final rawCallable = callable?.raw;
    final hasOpaqueName =
        frame.functionName.isEmpty ||
        frame.functionName == 'function' ||
        frame.functionName == 'unknown';
    final hasDebugName =
        (frame.debugName?.isNotEmpty ?? false) ||
        frame.debugNameWhat.isNotEmpty;
    final looksSyntheticWrapper =
        !hasDebugName && hasOpaqueName && frame.currentLine > 0;

    // Hide synthetic Dart wrapper closures such as the coroutine.wrap thunk.
    // These are implementation details in lualike and should not surface in
    // Lua-visible tracebacks.
    if (rawCallable is Function &&
        callable?.functionBody == null &&
        looksSyntheticWrapper) {
      return false;
    }

    // Some internal wrapper transitions do not retain a callable at all but
    // still materialize as a source-bearing "?" frame in tracebacks.
    if (callable == null && looksSyntheticWrapper && frame.callNode == null) {
      return false;
    }

    return true;
  }

  String _tracebackStringChunk(String raw) {
    final decoded = Uri.decodeFull(raw).replaceAll('\n', ' ');
    final compact = decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = compact.length > 60
        ? '${compact.substring(0, 57)}...'
        : compact;
    return '[string "$preview"]';
  }

  String _tracebackShortSource(String? rawSource) {
    if (rawSource == null || rawSource.isEmpty) {
      return '[C]';
    }

    final source = _formatSourceForLua(rawSource);
    if (source == '=[C]') {
      return '[C]';
    }
    if (source.startsWith('=')) {
      final raw = source.substring(1);
      if (raw.contains('\n') ||
          raw.length > 120 ||
          raw.contains('%0A') ||
          raw.contains('%20')) {
        return _tracebackStringChunk(raw);
      }
      return raw;
    }
    if (source.startsWith('@')) {
      final raw = source.substring(1);
      if (raw.contains('\n') ||
          raw.length > 120 ||
          raw.contains('%0A') ||
          raw.contains('%20')) {
        return _tracebackStringChunk(raw);
      }
      return raw.split('/').last;
    }
    if (source.startsWith('[string')) {
      return source;
    }
    if (source.contains('\n') || source.length > 120) {
      return _tracebackStringChunk(source);
    }
    return source;
  }

  String _formatFrame(CallFrame frame) {
    final source = _tracebackShortSource(
      frame.scriptPath ??
          frame.callNode?.span?.sourceUrl?.toString() ??
          frame.callable?.functionBody?.span?.sourceUrl?.toString(),
    );
    final line = frame.currentLine > 0
        ? frame.currentLine
        : (frame.callNode?.span?.start.line ?? -1) + 1;
    final info = _inferFrameNameInfo(frame);
    final candidateName = switch (info.name) {
      null ||
      '' ||
      'unknown' ||
      'function' ||
      'anonymous' => frame.functionName,
      final name => name,
    };
    final displayName = switch (candidateName) {
      '' || 'unknown' || 'function' || 'anonymous' => '?',
      final name => name,
    };
    final functionBody = frame.callable?.functionBody;
    final functionLine = switch (frame.callable?.debugLineDefined) {
      final int line when line > 0 => line,
      _ when functionBody?.span != null => functionBody!.span!.start.line + 1,
      _ => line,
    };

    final buffer = StringBuffer();
    if (source == '[C]' || line <= 0) {
      buffer.write(source);
    } else {
      buffer.write('$source:$line');
    }
    buffer.write(': in ');
    if (displayName == '?' ||
        frame.functionName == '_MAIN_CHUNK' ||
        frame.functionName == 'main' ||
        frame.functionName == 'main_chunk') {
      if (frame.functionName == '_MAIN_CHUNK' ||
          frame.functionName == 'main' ||
          frame.functionName == 'main_chunk') {
        buffer.write('main chunk');
      } else if (functionBody != null && functionLine > 0) {
        buffer.write('function <$source:$functionLine>');
      } else {
        buffer.write('?');
      }
    } else {
      buffer.write("function '$displayName'");
    }
    return buffer.toString();
  }

  @override
  Object? call(List<Object?> args) {
    Coroutine? thread;
    Value? messageArg;
    var level = 1;

    if (args.isNotEmpty && (args[0] as Value).raw is Coroutine) {
      thread = (args[0] as Value).raw as Coroutine;
      messageArg = args.length > 1 ? args[1] as Value : null;
      level = args.length > 2 ? _intArg(args[2] as Value, 0) : 0;
    } else {
      messageArg = args.isNotEmpty ? args[0] as Value : null;
      level = args.length > 1 ? _intArg(args[1] as Value, 1) : 1;
    }

    if (messageArg != null &&
        messageArg.raw != null &&
        messageArg.raw is! String &&
        messageArg.raw is! LuaString) {
      return messageArg;
    }

    final message = messageArg?.raw?.toString() ?? "";
    final trace = StringBuffer();
    if (message.isNotEmpty) {
      trace.writeln(message);
    }
    trace.writeln("stack traceback:");

    if (thread case final Coroutine coroutine) {
      final coroutineError = coroutine.error;
      if (coroutine.status == CoroutineStatus.dead &&
          level <= 0 &&
          coroutine.rawDebugFrameAtLevel(1) == null &&
          coroutineError is LuaError &&
          coroutineError.luaStackTrace != null) {
        final formatted = coroutineError.luaStackTrace!.format();
        if (message.isEmpty) {
          return Value(formatted);
        }
        return Value('$message\n$formatted');
      }
      final rawTopFrame = coroutine.rawDebugFrameAtLevel(1);
      final rawTopIsYield =
          rawTopFrame != null &&
          rawTopFrame.callable?.functionBody == null &&
          (rawTopFrame.functionName == 'yield' ||
              rawTopFrame.callable?.functionName == 'yield');
      final rawTopIsError =
          rawTopFrame != null &&
          rawTopFrame.callable?.functionBody == null &&
          (rawTopFrame.functionName == 'error' ||
              rawTopFrame.callable?.functionName == 'error');
      if (coroutine.status == CoroutineStatus.suspended &&
          rawTopFrame != null &&
          level <= 0) {
        trace.writeln("\t[C]: in function 'yield'");
      }
      if (coroutine.status == CoroutineStatus.dead &&
          rawTopFrame != null &&
          level <= 0 &&
          rawTopIsError) {
        trace.writeln("\t${_formatFrame(rawTopFrame)}");
      }
      final startLevel = level <= 1 ? 1 : level;
      _appendTracebackFrames(
        trace,
        _coroutineFrames(coroutine, startLevel).toList(growable: false),
      );
      return Value(trace.toString().trimRight());
    }

    final runtime = _resolveDebugInterpreter(interpreter);
    if (runtime == null) {
      return Value(trace.toString().trimRight());
    }
    final currentCoroutine = runtime.getCurrentCoroutine();
    final mainCoroutine = runtime.getMainThread();
    if (thread == null &&
        currentCoroutine != null &&
        !identical(currentCoroutine, mainCoroutine)) {
      thread = currentCoroutine;
    }
    if (thread case final Coroutine coroutine) {
      final startLevel = level <= 1 ? 1 : level;
      _appendTracebackFrames(
        trace,
        _coroutineFrames(coroutine, startLevel).toList(growable: false),
      );
      return Value(trace.toString().trimRight());
    }
    final startLevel = (level < 0 ? 0 : level) + 1;
    _appendTracebackFrames(
      trace,
      _currentFrames(runtime, startLevel).toList(growable: false),
    );
    return Value(trace.toString().trimRight());
  }
}

class _UpvalueId extends BuiltinFunction {
  _UpvalueId() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError("debug.upvalueid requires function and index");
    }
    final functionArg = args[0] as Value;
    final indexArg = args[1] as Value;

    if (indexArg.raw is! num) {
      throw LuaError("debug.upvalueid index must be a number");
    }

    final index = (indexArg.raw as num).toInt();
    if (index < 1) {
      return Value(null);
    }

    if (functionArg.raw case final LuaBytecodeClosure closure) {
      if (index > closure.upvalueCount) {
        return Value(null);
      }
      return Value(closure.upvalueIdentity(index - 1));
    }

    final upvalues = functionArg.upvalues;
    if (upvalues == null || index > upvalues.length) {
      return Value(null);
    }

    final Upvalue upvalue = upvalues[index - 1];
    return Value(upvalue.canonicalBox);
  }
}

class _UpvalueJoin extends BuiltinFunction {
  _UpvalueJoin() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.length < 4) {
      throw LuaError("debug.upvaluejoin requires f1,n1,f2,n2 arguments");
    }

    final f1Arg = args[0] as Value;
    final n1Arg = args[1] as Value;
    final f2Arg = args[2] as Value;
    final n2Arg = args[3] as Value;

    // Validate that indices are numbers
    if (n1Arg.raw is! num || n2Arg.raw is! num) {
      throw LuaError("debug.upvaluejoin indices must be numbers");
    }

    final n1 = (n1Arg.raw as num).toInt();
    final n2 = (n2Arg.raw as num).toInt();

    if (f1Arg.raw case final LuaBytecodeClosure f1Closure) {
      if (f2Arg.raw is! LuaBytecodeClosure) {
        throw LuaError(
          "debug.upvaluejoin: functions must both be bytecode closures",
        );
      }
      final f2Closure = f2Arg.raw as LuaBytecodeClosure;
      if (n1 < 1 || n1 > f1Closure.upvalueCount) {
        throw LuaError("debug.upvaluejoin: f1 upvalue index $n1 out of bounds");
      }
      if (n2 < 1 || n2 > f2Closure.upvalueCount) {
        throw LuaError("debug.upvaluejoin: f2 upvalue index $n2 out of bounds");
      }
      f1Closure.joinUpvalueWith(n1 - 1, f2Closure, n2 - 1);
      return Value(null);
    }

    // Validate that both functions have upvalues
    if (f1Arg.upvalues == null || f2Arg.upvalues == null) {
      throw LuaError("debug.upvaluejoin: functions must have upvalues");
    }

    // Validate indices are within bounds
    if (n1 < 1 || n1 > f1Arg.upvalues!.length) {
      throw LuaError("debug.upvaluejoin: f1 upvalue index $n1 out of bounds");
    }
    if (n2 < 1 || n2 > f2Arg.upvalues!.length) {
      throw LuaError("debug.upvaluejoin: f2 upvalue index $n2 out of bounds");
    }

    // Join the upvalues by making f1's upvalue point to the same value box as f2's upvalue
    final f1Upvalue = f1Arg.upvalues![n1 - 1];
    final f2Upvalue = f2Arg.upvalues![n2 - 1];

    // Use the new joinWith method to join the upvalues
    f1Upvalue.joinWith(f2Upvalue);

    Logger.debugLazy(
      () => 'UpvalueJoin: Joined f1 upvalue $n1 with f2 upvalue $n2',
      category: 'Debug',
    );

    return Value(null);
  }
}

/// Implementation of debug.getinfo that correctly reports line numbers
class _GetInfoImpl extends BuiltinFunction {
  _GetInfoImpl(super.interpreter);

  String? _frameSourceKey(CallFrame frame) {
    return _debugFrameSourceKey(frame);
  }

  CallFrame? _resolveVisibleFrame(Interpreter runtime, int level) {
    final originalFrame = runtime.getVisibleFrameAtLevel(
      level + 1,
      hideEnclosingDebugHooks: true,
    );
    var frame = originalFrame;
    if (frame == null) {
      return null;
    }
    if (frame.callable == null && frame.env != null) {
      final lexicalFrame = runtime.getVisibleFrameAtLevel(
        level + 2,
        hideEnclosingDebugHooks: true,
      );
      if (lexicalFrame != null &&
          lexicalFrame.callable?.functionBody != null &&
          _frameSourceKey(lexicalFrame) == _frameSourceKey(frame)) {
        frame = lexicalFrame;
      }
    }
    if (frame.callable?.functionBody != null) {
      final wrapperFrame =
          originalFrame != null &&
              originalFrame.callable == null &&
              _frameSourceKey(originalFrame) == _frameSourceKey(frame)
          ? originalFrame
          : runtime.getVisibleFrameAtLevel(
              level,
              hideEnclosingDebugHooks: true,
            );
      if (wrapperFrame != null &&
          wrapperFrame.callable == null &&
          _frameSourceKey(wrapperFrame) == _frameSourceKey(frame) &&
          wrapperFrame.currentLine > 0 &&
          wrapperFrame.currentLine > frame.currentLine) {
        frame.currentLine = wrapperFrame.currentLine;
      }
    }
    return frame;
  }

  CallFrame? _resolveCoroutineFrame(Coroutine coroutine, int level) {
    return _resolveDebugCoroutineFrame(coroutine, level);
  }

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw ArgumentError('debug.getinfo requires at least one argument');
    }

    var argIndex = 0;
    Coroutine? thread;
    final firstValue = args[0] is Value ? args[0] as Value : Value(args[0]);
    if (firstValue.raw is Coroutine) {
      thread = firstValue.raw as Coroutine;
      argIndex = 1;
      if (args.length <= argIndex) {
        throw ArgumentError('debug.getinfo requires a level or function');
      }
    }

    final firstArg = args[argIndex] as Value;
    String? what = args.length > argIndex + 1
        ? (args[argIndex + 1] as Value).raw.toString()
        : "flnSrtu";

    final optionError = _validateGetInfoOptions(what);
    if (optionError != null) {
      throw LuaError(optionError);
    }

    // Log that debug.getinfo was called to help with troubleshooting
    Logger.debugLazy(
      () =>
          'debug.getinfo called with args: $firstArg, what: $what, interpreter: ${interpreter != null}',
      category: 'DebugLib',
    );

    // If we don't have an interpreter instance, try to get one
    final debugInterpreter = _resolveDebugInterpreter(interpreter);
    final interpreterInstance = debugInterpreter ?? interpreter;
    if (interpreterInstance == null) {
      Logger.warning(
        'No interpreter instance available for debug.getinfo',
        category: 'DebugLib',
      );
    }

    // Handle level-based lookup (when first arg is a number)
    if (firstArg.raw is num) {
      final level = (firstArg.raw as num).toInt();
      if (level < 0) {
        return Value(null);
      }
      final actualLevel = thread != null ? level : level + 1;

      if (interpreterInstance != null) {
        // Get the frame from the call stack; invalid levels return nil.
        final frame = switch (thread) {
          final Coroutine coroutine => _resolveCoroutineFrame(
            coroutine,
            actualLevel,
          ),
          null when debugInterpreter != null => _resolveVisibleFrame(
            debugInterpreter,
            level,
          ),
          _ when interpreterInstance is Interpreter => _resolveVisibleFrame(
            interpreterInstance,
            level,
          ),
          _ => interpreterInstance.callStack.getFrameAtLevel(actualLevel),
        };

        if (frame != null) {
          Logger.debugLazy(
            () =>
                'Found frame for level $level: name=${frame.functionName}, line=${frame.currentLine}',
            category: 'DebugLib',
          );

          final debugInfo = <String, Value>{};
          final frameNameInfo = _inferFrameNameInfo(frame);
          final currentFunction = interpreterInstance is Interpreter
              ? interpreterInstance.getCurrentFunction()
              : null;
          final coroutineCallable =
              thread != null &&
                  actualLevel == 1 &&
                  (frame.callable == null ||
                      frame.callable?.functionBody == null)
              ? Value(
                  () => null,
                  closureEnvironment: thread.closureEnvironment,
                  functionBody: thread.functionBody,
                  functionName: thread.functionValue.functionName,
                  strippedDebugInfo: thread.functionValue.strippedDebugInfo,
                )
              : null;
          final isMainChunkFrame =
              thread == null &&
              frame.env != null &&
              (frame.callable == null ||
                  frame.functionName == '_MAIN_CHUNK' ||
                  frame.functionName == 'main' ||
                  frame.functionName == 'main_chunk');
          final syntheticMainCallable = isMainChunkFrame && frame.env != null
              ? Value(
                  () => null,
                  closureEnvironment: frame.env,
                  functionName: '_MAIN_CHUNK',
                )
              : null;
          final callableValue =
              coroutineCallable ??
              ((isMainChunkFrame && currentFunction != null)
                  ? currentFunction
                  : (frame.callable ?? syntheticMainCallable));
          final metadata = callableValue == null
              ? null
              : interpreterInstance.debugInfoForFunction(callableValue);

          if (what.contains('n')) {
            debugInfo['name'] = Value(frameNameInfo.name);
            debugInfo['namewhat'] = Value(frameNameInfo.namewhat);
          }
          if (what.contains('S')) {
            debugInfo['what'] = Value(
              isMainChunkFrame ? 'main' : (metadata?.what ?? 'Lua'),
            );

            // Check if we can get source from current function first
            String sourceValue = "=[C]";
            String shortSrc = "[C]";

            if (_frameHasStrippedDebugInfo(frame)) {
              sourceValue = "=?";
              shortSrc = "?";
            } else {
              // First, check script path for explicit chunk names (string chunks)
              final scriptPath =
                  frame.scriptPath ?? interpreterInstance.callStack.scriptPath;
              Logger.debugLazy(
                () =>
                    'debug.getinfo: frame.scriptPath=${frame.scriptPath}, callStack.scriptPath=${interpreterInstance.callStack.scriptPath}',
                category: 'DebugLib',
              );

              if (scriptPath != null) {
                // For string chunks, use script path directly
                if (scriptPath.startsWith('@') ||
                    scriptPath.startsWith('=') ||
                    scriptPath.startsWith('[')) {
                  sourceValue = scriptPath;
                  shortSrc = scriptPath.startsWith('@')
                      ? scriptPath.substring(1)
                      : scriptPath;
                  Logger.debugLazy(
                    () => 'debug.getinfo: using scriptPath as-is: $sourceValue',
                    category: 'DebugLib',
                  );
                } else {
                  // For unprefixed script paths, check whether the active
                  // function came from a loaded chunk-like artifact.
                  Value? currentFunction;
                  if (interpreterInstance is Interpreter) {
                    currentFunction = interpreterInstance.getCurrentFunction();
                  }
                  bool isBinaryChunk = false;

                  if (currentFunction != null &&
                      currentFunction.functionBody != null) {
                    final span = currentFunction.functionBody!.span;
                    Logger.debugLazy(
                      () =>
                          'debug.getinfo: currentFunction has functionBody, span=$span, sourceUrl=${span?.sourceUrl}',
                      category: 'DebugLib',
                    );

                    if (span != null && span.sourceUrl != null) {
                      final rawSource = span.sourceUrl!.toString();
                      sourceValue = _formatSourceForLua(rawSource);
                      shortSrc = sourceValue.startsWith('@')
                          ? sourceValue.substring(1)
                          : sourceValue;
                      isBinaryChunk = true;
                      Logger.debugLazy(
                        () =>
                            'debug.getinfo: using current function source: $sourceValue',
                        category: 'DebugLib',
                      );
                    } else {
                      String? childSource = _extractSourceFromChildren(
                        currentFunction.functionBody!,
                      );
                      if (childSource != null) {
                        sourceValue = _formatSourceForLua(childSource);
                        shortSrc = sourceValue.startsWith('@')
                            ? sourceValue.substring(1)
                            : sourceValue;
                        isBinaryChunk = true;
                        Logger.debugLazy(
                          () =>
                              'debug.getinfo: using source from child nodes: $sourceValue',
                          category: 'DebugLib',
                        );
                      }
                    }
                  }

                  if (!isBinaryChunk) {
                    sourceValue = _formatSourceForLua(scriptPath);
                    shortSrc = scriptPath;
                    isBinaryChunk = true;
                    Logger.debugLazy(
                      () =>
                          'debug.getinfo: using script path as string chunk: $sourceValue',
                      category: 'DebugLib',
                    );
                  }
                }
              }
            }

            debugInfo['source'] = Value(sourceValue);
            debugInfo['short_src'] = Value(shortSrc);
            final strippedLineDefined = metadata?.lineDefined ?? 1;
            final strippedLastLineDefined =
                metadata?.lastLineDefined ?? metadata?.lineDefined ?? 1;
            debugInfo['linedefined'] = Value(
              isMainChunkFrame
                  ? 0
                  : (_frameHasStrippedDebugInfo(frame)
                        ? (strippedLineDefined > 0 ? strippedLineDefined : 1)
                        : (metadata?.lineDefined ?? -1)),
            );
            debugInfo['lastlinedefined'] = Value(
              isMainChunkFrame
                  ? 0
                  : (_frameHasStrippedDebugInfo(frame)
                        ? (strippedLastLineDefined > 0
                              ? strippedLastLineDefined
                              : 1)
                        : (metadata?.lastLineDefined ?? -1)),
            );
          }
          if (what.contains('l')) {
            final line = _frameHasStrippedDebugInfo(frame)
                ? -1
                : switch (frame.currentLine) {
                    > 0 => frame.currentLine,
                    _ when frame.callNode?.span != null =>
                      frame.callNode!.span!.start.line + 1,
                    _ => -1,
                  };
            debugInfo['currentline'] = Value(line);
          }
          if (what.contains('t')) {
            debugInfo['istailcall'] = Value(frame.isTailCall);
            debugInfo['extraargs'] = Value(frame.extraArgs);
          }
          if (what.contains('u')) {
            debugInfo['nups'] = Value(metadata?.nups ?? 0);
            debugInfo['nparams'] = Value(metadata?.nparams ?? 0);
            debugInfo['isvararg'] = Value(metadata?.isVararg ?? true);
          }
          if (what.contains('r')) {
            debugInfo['ftransfer'] = Value(frame.ftransfer);
            debugInfo['ntransfer'] = Value(frame.ntransfer);
          }
          if (what.contains('f')) {
            debugInfo['func'] = callableValue ?? Value(null);
          }
          if (what.contains('L')) {
            final activeLines =
                callableValue == null || _frameHasStrippedDebugInfo(frame)
                ? Value(null)
                : _collectActiveLines(callableValue);
            final whatKind = isMainChunkFrame
                ? 'main'
                : (metadata?.what ?? 'Lua');
            if (activeLines.raw == null && whatKind != 'C') {
              debugInfo['activelines'] = Value(<Object?, Object?>{});
            } else {
              debugInfo['activelines'] = activeLines;
            }
          }

          return Value(debugInfo);
        }
      }

      return Value(null);
    }

    // Function-based lookup
    if (firstArg.isCallable()) {
      final metadata = interpreterInstance?.debugInfoForFunction(firstArg);
      String src = metadata?.source ?? "=[C]";
      String whatKind = metadata?.what ?? "C";

      final debugInfo = <String, Value>{};
      if (what.contains('n')) {
        debugInfo['name'] = Value(null);
        debugInfo['namewhat'] = Value("");
      }
      if (what.contains('S')) {
        debugInfo['what'] = Value(whatKind);
        debugInfo['source'] = Value(src);
        debugInfo['short_src'] = Value(
          metadata?.shortSource ??
              (src.split('/').isNotEmpty ? src.split('/').last : src),
        );
        debugInfo['linedefined'] = Value(metadata?.lineDefined ?? -1);
        debugInfo['lastlinedefined'] = Value(metadata?.lastLineDefined ?? -1);
      }
      if (what.contains('l')) {
        debugInfo['currentline'] = Value(-1);
      }
      if (what.contains('u')) {
        debugInfo['nups'] = Value(metadata?.nups ?? 0);
        debugInfo['nparams'] = Value(metadata?.nparams ?? 0);
        debugInfo['isvararg'] = Value(metadata?.isVararg ?? true);
      }
      if (what.contains('r')) {
        debugInfo['ftransfer'] = Value(0);
        debugInfo['ntransfer'] = Value(0);
      }
      if (what.contains('t')) {
        debugInfo['istailcall'] = Value(false);
        debugInfo['extraargs'] = Value(0);
      }
      if (what.contains('f')) {
        debugInfo['func'] = firstArg;
      }
      if (what.contains('L')) {
        final activeLines = firstArg.strippedDebugInfo
            ? Value(<Object?, Object?>{})
            : _collectActiveLines(firstArg);
        if (activeLines.raw == null && (whatKind != 'C')) {
          debugInfo['activelines'] = Value(<Object?, Object?>{});
        } else {
          debugInfo['activelines'] = activeLines;
        }
      }
      return Value(debugInfo);
    }

    // Fallback: unknown type
    return Value({
      'name': Value(null),
      'namewhat': Value(""),
      'what': Value("C"),
      'source': Value("=[C]"),
      'short_src': Value("[C]"),
      'currentline': Value(-1),
      'linedefined': Value(-1),
      'lastlinedefined': Value(-1),
      'nups': Value(0),
      'nparams': Value(0),
      'isvararg': Value(false),
      'istailcall': Value(false),
    });
  }
}

String? _validateGetInfoOptions(String what) {
  if (what.startsWith('>')) {
    return "bad argument #2 to 'debug.getinfo' (invalid option '>')";
  }

  const allowed = 'flnSrtuL';
  for (final codeUnit in what.codeUnits) {
    final option = String.fromCharCode(codeUnit);
    if (!allowed.contains(option)) {
      return "bad argument #2 to 'debug.getinfo' (invalid option)";
    }
  }
  return null;
}

Value _collectActiveLines(Value function) {
  if (function.strippedDebugInfo) {
    return Value(<Object?, Object?>{});
  }
  final body = function.functionBody;
  if (body == null) {
    return Value(null);
  }

  final lines = <int>{};
  var hasDebugInfo = false;

  void markLine(int? line) {
    if (line == null || line <= 0) {
      return;
    }
    hasDebugInfo = true;
    lines.add(line);
  }

  void markSpanStart(AstNode? node) {
    final span = node?.span;
    if (span == null) {
      return;
    }
    markLine(span.start.line + 1);
  }

  void visitExpression(AstNode? node) {
    if (node == null) {
      return;
    }

    markSpanStart(node);

    switch (node) {
      case GroupedExpression(:final expr):
        visitExpression(expr);
      case BinaryExpression(
        :final left,
        :final right,
        :final int? operatorLine,
      ):
        if (operatorLine != null) {
          markLine(operatorLine + 1);
        }
        visitExpression(left);
        visitExpression(right);
      case UnaryExpression(:final expr):
        visitExpression(expr);
      case TableFieldAccess(:final table):
        visitExpression(table);
      case TableIndexAccess(:final table, :final index):
        visitExpression(table);
        visitExpression(index);
      case TableAccessExpr(:final table, :final index):
        visitExpression(table);
        visitExpression(index);
      case FunctionCall(:final name, :final args):
        visitExpression(name);
        for (final arg in args) {
          visitExpression(arg);
        }
      case MethodCall(:final prefix, :final args):
        visitExpression(prefix);
        for (final arg in args) {
          visitExpression(arg);
        }
      case TableConstructor(:final entries):
        for (final entry in entries) {
          visitExpression(entry);
        }
      case KeyedTableEntry(:final key, :final value):
        visitExpression(key);
        visitExpression(value);
      case IndexedTableEntry(:final key, :final value):
        visitExpression(key);
        visitExpression(value);
      case TableEntryLiteral(:final expr):
        visitExpression(expr);
      case FunctionLiteral():
        // Nested function bodies have their own active-line tables.
        return;
      default:
        return;
    }
  }

  void visitStatement(AstNode statement) {
    markSpanStart(statement);

    switch (statement) {
      case Assignment(:final targets, :final exprs):
        for (final target in targets) {
          visitExpression(target);
        }
        for (final expr in exprs) {
          visitExpression(expr);
        }
      case LocalDeclaration(:final exprs):
        for (final expr in exprs) {
          visitExpression(expr);
        }
      case GlobalDeclaration(:final exprs):
        for (final expr in exprs) {
          visitExpression(expr);
        }
      case IfStatement(
        :final cond,
        :final thenBlock,
        :final elseIfs,
        :final elseBlock,
      ):
        visitExpression(cond);
        for (final branchStatement in thenBlock) {
          visitStatement(branchStatement);
        }
        for (final elseIf in elseIfs) {
          markSpanStart(elseIf);
          visitExpression(elseIf.cond);
          for (final branchStatement in elseIf.thenBlock) {
            visitStatement(branchStatement);
          }
        }
        for (final branchStatement in elseBlock) {
          visitStatement(branchStatement);
        }
      case WhileStatement(:final cond, :final body):
        visitExpression(cond);
        for (final bodyStatement in body) {
          visitStatement(bodyStatement);
        }
      case ForLoop(:final start, :final endExpr, :final stepExpr, :final body):
        visitExpression(start);
        visitExpression(endExpr);
        visitExpression(stepExpr);
        for (final bodyStatement in body) {
          visitStatement(bodyStatement);
        }
      case ForInLoop(:final iterators, :final body):
        for (final iterator in iterators) {
          visitExpression(iterator);
        }
        for (final bodyStatement in body) {
          visitStatement(bodyStatement);
        }
      case RepeatUntilLoop(:final body, :final cond):
        for (final bodyStatement in body) {
          visitStatement(bodyStatement);
        }
        visitExpression(cond);
      case FunctionDef():
        // Nested function bodies have their own active-line tables.
        return;
      case LocalFunctionDef():
        return;
      case ReturnStatement(:final expr):
        for (final returnExpr in expr) {
          visitExpression(returnExpr);
        }
      case YieldStatement(:final expr):
        for (final yieldedExpr in expr) {
          visitExpression(yieldedExpr);
        }
      case ExpressionStatement(:final expr):
        visitExpression(expr);
      case DoBlock(:final body):
        for (final bodyStatement in body) {
          visitStatement(bodyStatement);
        }
      default:
        return;
    }
  }

  for (final statement in body.body) {
    visitStatement(statement);
  }

  if (body.span != null) {
    markLine(body.span!.end.line + 1);
  }

  if (!hasDebugInfo) {
    return Value(<Object?, Object?>{});
  }

  final activeLines = <Object?, Object?>{};
  for (final line in lines.toList()..sort()) {
    activeLines[line] = Value(true);
  }
  return Value(activeLines);
}

/// Helper method to extract source URL from child AST nodes
String? _extractSourceFromChildren(dynamic node) {
  Logger.debugLazy(
    () =>
        'AST: _extractSourceFromChildren called with node type: ${node.runtimeType}',
    category: 'DebugLib',
  );

  if (node == null) return null;

  // If this node has a span, return its source URL
  if (node is AstNode && node.span?.sourceUrl != null) {
    final sourceUrl = node.span!.sourceUrl!.toString();
    Logger.debugLazy(
      () => 'AST: Found span with sourceUrl: $sourceUrl',
      category: 'DebugLib',
    );
    return sourceUrl;
  }

  // Recursively search child nodes
  if (node is FunctionBody) {
    Logger.debugLazy(
      () =>
          'AST: Searching FunctionBody with ${node.parameters?.length ?? 0} params and ${node.body.length} body statements',
      category: 'DebugLib',
    );

    // Check parameters
    if (node.parameters != null) {
      for (final param in node.parameters!) {
        final source = _extractSourceFromChildren(param);
        if (source != null) return source;
      }
    }

    // Check body statements
    for (final stmt in node.body) {
      final source = _extractSourceFromChildren(stmt);
      if (source != null) return source;
    }
  } else if (node is List) {
    Logger.debugLazy(
      () => 'AST: Searching List with ${node.length} items',
      category: 'DebugLib',
    );
    for (final item in node) {
      final source = _extractSourceFromChildren(item);
      if (source != null) return source;
    }
  }

  Logger.debugLazy(
    () => 'AST: No source found in node type: ${node.runtimeType}',
    category: 'DebugLib',
  );
  return null;
}

/// Formats source URL to match Lua's format
String _formatSourceForLua(String rawSource) {
  // Handle command line sources
  if (rawSource.contains('command') || rawSource.contains('line')) {
    return '=(command line)';
  }

  // Handle file URLs
  if (rawSource.startsWith('file:///')) {
    final uri = Uri.parse(rawSource);
    final fileName = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : rawSource;
    return '@$fileName';
  }

  // Handle already prefixed sources
  if (rawSource.startsWith('@') ||
      rawSource.startsWith('=') ||
      rawSource.startsWith('[')) {
    return rawSource;
  }

  // Default: add @ prefix for file-like sources
  return '@$rawSource';
}

/// Function to create a debug.getinfo function that correctly reports line numbers
/// (kept for backwards compatibility)
BuiltinFunction createGetInfoFunction(LuaRuntime? vm) {
  return _GetInfoImpl(vm);
}

/// Creates debug library functions with the given interpreter instance
Map<String, BuiltinFunction> createDebugLib(LuaRuntime? astVm) {
  // Ensure we have a valid VM instance for debug functions
  if (astVm == null) {
    Logger.warning(
      "No VM instance provided to debug library, line tracking might not work correctly",
      category: "Debug",
    );

    // Note: Cannot access Environment.current anymore
    // Interpreter should be passed directly to debug functions
    Logger.info(
      "Cannot access Environment.current for debug library (deprecated)",
      category: "Debug",
    );
  }

  // Create debug functions with interpreter reference
  return {
    'debug': _DebugInteractive(),
    'gethook': _GetHook(astVm),
    'getinfo': createGetInfoFunction(astVm), // Use new optimized implementation
    'getlocal': _GetLocal(astVm!),
    'getmetatable': _GetMetatable(),
    'getregistry': _GetRegistry(astVm),
    'getupvalue': _GetUpvalue(astVm),
    'getuservalue': _GetUserValue(),
    'sethook': _SetHook(astVm),
    'setlocal': _SetLocal(astVm),
    'setmetatable': _SetMetatable(),
    'setupvalue': _SetUpvalue(),
    'setuservalue': _SetUserValue(),
    'traceback': _Traceback(astVm),
    'upvalueid': _UpvalueId(),
    'upvaluejoin': _UpvalueJoin(),

    // Memory debugging functions
    'memtrace': _MemTrace(),
    'memtree': _MemTree(),
    'memclear': _MemClear(),
  };
}

/// Initialize the debug library with the interpreter instance
///
/// This ensures the debug.getinfo function can access line information
/// [env] - The environment to define the debug table in
/// [vm] - The runtime instance to use for call stack access
void defineDebugLibrary({required Environment env, LuaRuntime? vm}) {
  // Store interpreter reference in environment for later access
  if (vm != null) {
    env.interpreter = vm;
    Logger.debugLazy(
      () => 'Setting interpreter reference in environment for debug library',
      category: 'Debug',
    );
  }

  // Create and define the debug table
  DebugLib.functions = createDebugLib(vm);
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
      Logger.debugLazy(
        () => 'Debug table stored in package.loaded for require() equality',
        category: 'Debug',
      );
    }
  }

  Logger.debugLazy(
    () => 'Debug library initialized with interpreter: ${vm != null}',
    category: 'Debug',
  );
}

({String? name, String namewhat}) _inferFrameNameInfo(CallFrame frame) {
  if (frame.isDebugHook) {
    return (name: 'hook', namewhat: 'hook');
  }

  if ((frame.debugName?.isNotEmpty ?? false) ||
      frame.debugNameWhat.isNotEmpty) {
    return (name: frame.debugName, namewhat: frame.debugNameWhat);
  }

  final callNode = frame.callNode;
  final env = frame.env;

  if (callNode case MethodCall(methodName: final Identifier methodName)) {
    return (name: methodName.name, namewhat: 'method');
  }

  if (callNode case FunctionCall(name: final AstNode callee)) {
    if (callee case Identifier(name: final name)) {
      return (name: name, namewhat: _inferIdentifierNameWhat(env, name));
    }
    if (callee case TableFieldAccess(fieldName: final Identifier fieldName)) {
      return (name: fieldName.name, namewhat: 'field');
    }
  }

  final fallbackName = switch (frame.functionName ??
      frame.callable?.functionName) {
    'unknown' || 'function' => null,
    final name => name,
  };
  return (
    name: fallbackName,
    namewhat: fallbackName != null
        ? _inferIdentifierNameWhat(env, fallbackName)
        : '',
  );
}

String _inferIdentifierNameWhat(Environment? env, String name) {
  Environment? current = env;
  while (current != null) {
    if (current.values.containsKey(name)) {
      final box = current.values[name]!;
      if (!box.isLocal) {
        return 'global';
      }
      // For active call-site naming, Lua reports identifiers resolved through
      // enclosing lexical blocks as "local" too; they are still called by a
      // local name, even if that binding lives in a parent environment frame.
      return 'local';
    }
    if (current.declaredGlobals.containsKey(name)) {
      return 'global';
    }
    current = current.parent;
  }
  return 'global';
}

/// Enable/disable memory allocation stack trace tracking
class _MemTrace extends BuiltinFunction {
  _MemTrace() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      return Value(MemoryCredits.enableStackTraces);
    }

    final enable = args[0];
    if (enable is Value) {
      MemoryCredits.enableStackTraces = enable.raw == true;
    } else {
      MemoryCredits.enableStackTraces = enable == true;
    }

    return Value(null);
  }
}

/// Print memory allocation tree
class _MemTree extends BuiltinFunction {
  _MemTree() : super();

  @override
  Object? call(List<Object?> args) {
    MemoryCredits.instance.printAllocationTree();
    return Value(null);
  }
}

/// Clear tracked objects list for debugging specific allocations
class _MemClear extends BuiltinFunction {
  _MemClear() : super();

  @override
  Object? call(List<Object?> args) {
    MemoryCredits.instance.clearTrackedObjects();
    return Value(null);
  }
}
