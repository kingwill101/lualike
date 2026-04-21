part of '../love_api_bindings.dart';

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

Map<dynamic, dynamic>? _loveTable(LuaRuntime runtime) {
  return _tableRaw(runtime.globals.get('love'));
}

Object? _loveTableField(LuaRuntime runtime, String name) {
  final love = _loveTable(runtime);
  if (love == null || !love.containsKey(name)) {
    return null;
  }

  return love[name];
}

Value? _userLoveCallback(LuaRuntime runtime, String name) {
  final callback = _functionValue(_loveTableField(runtime, name));
  if (callback == null || callback.raw is BuiltinFunction) {
    return null;
  }

  return callback;
}

Value? _functionValue(Object? value) {
  if (value == null) {
    return null;
  }

  return value is Value ? value : Value(value);
}

Map<dynamic, dynamic>? _tableRaw(Object? value) {
  final raw = value is Value ? value.raw : value;
  if (raw is! Map<dynamic, dynamic>) {
    return null;
  }

  return raw;
}
