part of '../love_api_bindings.dart';

/// Binds `love.run`.
///
/// The returned closure mirrors the default LÖVE main loop by dispatching
/// events, stepping timers, invoking `love.update`, and issuing a draw pass.
LoveApiImplementation _bindLoveRun(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for LOVE bindings');
  }

  final builder = BuiltinFunctionBuilder(context);
  return (args) async {
    await _invokeLoveRunLoadIfDefined(interpreter);
    if (_loveTableField(interpreter, 'timer') != null) {
      runtime.step();
    }

    final frameHandler = builder.create((args) async {
      if (_loveTableField(interpreter, 'event') != null) {
        final quitResult = await _runLoveMainLoopEvents(interpreter, runtime);
        if (quitResult != null) {
          return quitResult;
        }
      }

      var dt = 0.0;
      if (_loveTableField(interpreter, 'timer') != null) {
        dt = runtime.step();
      }

      await _callLoveCallbackIfDefined(interpreter, 'update', <Object?>[dt]);

      if (_loveTableField(interpreter, 'graphics') != null) {
        runtime.beginDrawFrame();
        runtime.graphics.origin();
        await _callLoveCallbackIfDefined(interpreter, 'draw');
      }

      if (_loveTableField(interpreter, 'timer') != null &&
          !runtime.host.usesExternalFrameLoop) {
        await runtime.sleep(0.001);
      }

      return null;
    });

    return Value(frameHandler, functionName: 'run_i');
  };
}

/// Invokes `love.load` with parsed and raw command line arguments when present.
Future<void> _invokeLoveRunLoadIfDefined(LuaRuntime runtime) async {
  final rawArg = _rawValue(runtime.globals.get('arg'));
  final loadArgs = <Object?>[];
  final parsedArgs = await _parseLoveRunArguments(runtime, rawArg);
  if (parsedArgs != null || rawArg != null) {
    loadArgs
      ..add(parsedArgs)
      ..add(rawArg);
  }

  await _callLoveCallbackIfDefined(runtime, 'load', loadArgs);
}

/// Parses game arguments via `love.arg.parseGameArguments` when available.
Future<Object?> _parseLoveRunArguments(
  LuaRuntime runtime,
  Object? rawArg,
) async {
  final argModule = _tableRaw(_loveTableField(runtime, 'arg'));
  final parser = _functionValue(argModule?['parseGameArguments']);
  if (parser == null) {
    return null;
  }

  final parsed = await runtime.callFunction(
    parser,
    <Object?>[rawArg],
    debugName: 'love.arg.parseGameArguments',
    debugNameWhat: 'function',
  );
  return _rawValue(parsed);
}

/// Pumps queued events and dispatches them to their corresponding callbacks.
///
/// Returns a quit code when the event loop requests termination.
Future<Object?> _runLoveMainLoopEvents(
  LuaRuntime runtime,
  LoveRuntimeContext context,
) async {
  context.events.pump();
  while (true) {
    final message = context.events.poll();
    if (message == null) {
      return null;
    }

    if (message.name == 'quit' || message.name == 'q') {
      final abortQuit = _luaTruthy(
        await _callLoveCallbackIfDefined(runtime, 'quit'),
      );
      if (!abortQuit) {
        return message.arguments.isEmpty ? 0 : message.arguments.first;
      }
      continue;
    }

    final callbackName = _loveRunCallbackName(message.name);
    if (callbackName == null) {
      throw LuaError('Unknown event: ${message.name}');
    }

    await _callLoveCallbackIfDefined(runtime, callbackName, message.arguments);
    if (callbackName == 'lowmemory') {
      await _invokeCollectGarbage(runtime);
      await _invokeCollectGarbage(runtime);
    }
  }
}

/// Maps event queue names to the callback names used on the `love` table.
String? _loveRunCallbackName(String name) {
  return switch (name) {
    'focus' => 'focus',
    'joystickpressed' => 'joystickpressed',
    'joystickreleased' => 'joystickreleased',
    'keypressed' => 'keypressed',
    'keyreleased' => 'keyreleased',
    'mousepressed' => 'mousepressed',
    'mousereleased' => 'mousereleased',
    'resize' => 'resize',
    'visible' => 'visible',
    'mousefocus' => 'mousefocus',
    'threaderror' => 'threaderror',
    'joystickadded' => 'joystickadded',
    'joystickremoved' => 'joystickremoved',
    'joystickaxis' => 'joystickaxis',
    'joystickhat' => 'joystickhat',
    'gamepadpressed' => 'gamepadpressed',
    'gamepadreleased' => 'gamepadreleased',
    'gamepadaxis' => 'gamepadaxis',
    'textinput' => 'textinput',
    'mousemoved' => 'mousemoved',
    'lowmemory' => 'lowmemory',
    'textedited' => 'textedited',
    'wheelmoved' => 'wheelmoved',
    'touchpressed' => 'touchpressed',
    'touchreleased' => 'touchreleased',
    'touchmoved' => 'touchmoved',
    'directorydropped' => 'directorydropped',
    'filedropped' => 'filedropped',
    'displayrotated' => 'displayrotated',
    _ => null,
  };
}

/// Calls `love.[name]` if the user defined that callback.
Future<Object?> _callLoveCallbackIfDefined(
  LuaRuntime runtime,
  String name, [
  List<Object?> args = const <Object?>[],
]) async {
  final callback = _userLoveCallback(runtime, name);
  if (callback == null) {
    return null;
  }

  return runtime.callFunction(
    callback,
    args,
    debugName: 'love.$name',
    debugNameWhat: 'callback',
  );
}

/// Invokes the global `collectgarbage` function when available.
Future<void> _invokeCollectGarbage(LuaRuntime runtime) async {
  final collectGarbage = _functionValue(runtime.globals.get('collectgarbage'));
  if (collectGarbage == null) {
    return;
  }

  await runtime.callFunction(
    collectGarbage,
    const <Object?>[],
    debugName: 'collectgarbage',
    debugNameWhat: 'function',
  );
}

/// Returns the raw `love` table from [runtime], if available.
Map<dynamic, dynamic>? _loveTable(LuaRuntime runtime) {
  return _tableRaw(runtime.globals.get('love'));
}

/// Returns the raw field named [name] from the `love` table, if present.
Object? _loveTableField(LuaRuntime runtime, String name) {
  final love = _loveTable(runtime);
  if (love == null || !love.containsKey(name)) {
    return null;
  }

  return love[name];
}

/// Returns a user-defined `love.[name]` callback, excluding builtins.
Value? _userLoveCallback(LuaRuntime runtime, String name) {
  final callback = _functionValue(_loveTableField(runtime, name));
  if (callback == null || _isGeneratedLoveCallbackStub(callback)) {
    return null;
  }

  return callback;
}

bool _isGeneratedLoveCallbackStub(Value callback) {
  final raw = callback.raw;
  return raw is BuiltinFunction && raw is! LuaCallableArtifact;
}

/// Normalizes a Lua value to a callable [Value].
Value? _functionValue(Object? value) {
  if (value == null) {
    return null;
  }

  return value is Value ? value : Value(value);
}

/// Returns the raw backing map when [value] is a Lua table.
Map<dynamic, dynamic>? _tableRaw(Object? value) {
  final raw = value is Value ? value.raw : value;
  if (raw is! Map<dynamic, dynamic>) {
    return null;
  }

  return raw;
}
