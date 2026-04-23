/// Runtime helpers for executing LOVE scripts inside LuaLike.
library;

import 'dart:collection';
import 'dart:convert' as convert;

import 'package:lualike/lualike.dart';

import '../install_love2d.dart';
import 'filesystem/love_filesystem_bindings.dart'
    show wrapLoveFilesystemDroppedFileForRuntime;
import 'filesystem/love_filesystem_runtime.dart';
import 'love_api_bindings.dart' show wrapLoveJoystickForRuntime;
import 'love_runtime.dart';

part 'input/love_joystick_callback_support.dart';

/// Whether runtime tracing is enabled for touch-leak debugging.
const bool _loveTraceRuntimeLeak = bool.fromEnvironment(
  'LOVE2D_TRACE_TOUCH_LEAK',
  defaultValue: true,
);

/// Emits a runtime trace message for [stage] when tracing is enabled.
void _loveTraceRuntime(
  String stage, {
  Map<String, Object?> details = const {},
}) {
  if (!_loveTraceRuntimeLeak) {
    return;
  }

  final message = details.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  if (message.isEmpty) {
    // print('[love2d-runtime] $stage');
    return;
  }
  // print('[love2d-runtime] $stage $message');
}

/// Returns whether callback signal [name] should be included in tracing.
bool _loveShouldTraceRuntimeSignal(String name) {
  return switch (name) {
    'touchpressed' || 'touchreleased' || 'touchmoved' || 'update' => true,
    _ => false,
  };
}

/// Returns a trace-friendly description of callback [args].
String _loveDescribeRuntimeArgs(List<Object?> args) {
  if (args.isEmpty) {
    return '[]';
  }

  return '[${args.map(_loveDescribeRuntimeValue).join(', ')}]';
}

/// Returns a trace-friendly description of one runtime [value].
String _loveDescribeRuntimeValue(Object? value) {
  final raw = value is Value ? value.raw : value;
  return '${value.runtimeType}(${raw.runtimeType}:$raw)';
}

/// Small runtime wrapper for executing LOVE-style scripts from Dart.
///
/// This installs the generated `love` surface into a fresh or caller-provided
/// LuaLike runtime and provides helpers for invoking user-defined `love.load`
/// and `love.update` callbacks without accidentally calling the generated stub
/// callbacks that exist before the script overrides them.
class LoveScriptRuntime {
  static const String _bootstrapConfGlobalName = '__love_bootstrap_conf';

  /// Creates a LOVE script runtime and installs the LOVE API surface.
  ///
  /// Automatic Lualike GC safe points are disabled unless [automaticGc] is
  /// true.
  LoveScriptRuntime({
    LuaRuntime? runtime,
    EngineMode? engineMode,
    LoveHost? host,
    LoveFilesystemAdapter? filesystemAdapter,
    bool automaticGc = false,
  }) : this._(
         lua: runtime == null
             ? LuaLike(engineMode: engineMode)
             : LuaLike(runtime: runtime, engineMode: engineMode),
         host: host,
         filesystemAdapter: filesystemAdapter,
         automaticGc: automaticGc,
       );

  LoveScriptRuntime._({
    required LuaLike lua,
    LoveHost? host,
    LoveFilesystemAdapter? filesystemAdapter,
    required bool automaticGc,
  }) : runtime = lua.vm,
       _lua = lua {
    installLove2d(
      runtime: runtime,
      host: host,
      filesystemAdapter: filesystemAdapter,
      engineMode: lua.engineMode,
      automaticGc: automaticGc,
    );
  }

  /// The underlying Lua runtime.
  final LuaRuntime runtime;
  final LuaLike _lua;

  /// The LuaLike facade used to execute source text.
  LuaLike get lua => _lua;

  /// The attached LOVE runtime context for [runtime].
  LoveRuntimeContext get context => LoveRuntimeContext.of(runtime);

  /// Executes [code] inside this runtime.
  Future<Object?> execute(String code, {String? scriptPath}) {
    return _lua.execute(code, scriptPath: scriptPath);
  }

  /// Loads and applies `conf.lua` if it is present in the mounted source.
  ///
  /// Returns `true` when a configuration file was found and applied.
  Future<bool> loadConfIfPresent({String confPath = 'conf.lua'}) async {
    final filesystem = LoveFilesystemState.of(runtime);
    final confData = await filesystem.readFileData(
      confPath,
      filename: confPath,
    );
    if (confData == null) {
      return false;
    }

    _removeConfStub();

    await execute(
      convert.utf8.decode(confData.bytes),
      scriptPath: confData.filename,
    );

    final config = _defaultLoveConfigTable();
    runtime.globals.define(_bootstrapConfGlobalName, Value(config));
    try {
      await execute('''
if love and love.conf then
  love.conf($_bootstrapConfGlobalName)
end
''', scriptPath: '=[love.conf bootstrap]');
    } finally {
      runtime.globals.define(_bootstrapConfGlobalName, Value(null));
    }
    _applyLoveConfig(_tableValue(config) ?? _defaultLoveConfigTable());
    return true;
  }

  /// Returns the user-defined LOVE callback named [name], if one exists.
  Value? userLoveCallback(String name) {
    return loveCallback(name);
  }

  /// Returns the LOVE callback named [name].
  ///
  /// When [includeBuiltin] is `false`, generated builtin stubs are filtered out
  /// so only user-provided callbacks are returned.
  Value? loveCallback(String name, {bool includeBuiltin = false}) {
    final callback = _loveField(name);
    if (callback == null) {
      return null;
    }

    if (!includeBuiltin && _isGeneratedLoveCallbackStub(callback)) {
      return null;
    }

    return callback;
  }

  /// Calls the LOVE callback named [name] if the user defined it.
  Future<Object?> callLoveCallbackIfDefined(
    String name, [
    List<Object?> args = const <Object?>[],
  ]) async {
    final callback = userLoveCallback(name);
    if (callback == null) {
      return null;
    }

    final shouldTrace = _loveShouldTraceRuntimeSignal(name);
    if (shouldTrace) {
      _loveTraceRuntime(
        'callback.begin',
        details: <String, Object?>{
          'name': name,
          'args': _loveDescribeRuntimeArgs(args),
          'touches': context.touch.getTouches(),
          'scancodes': context.keyboard.pressedScancodes.toList(
            growable: false,
          ),
        },
      );
    }

    try {
      final result = await runtime.callFunction(
        callback,
        args,
        debugName: 'love.$name',
        debugNameWhat: 'callback',
      );
      if (shouldTrace) {
        _loveTraceRuntime(
          'callback.end',
          details: <String, Object?>{
            'name': name,
            'result': _loveDescribeRuntimeValue(result),
            'touches': context.touch.getTouches(),
            'scancodes': context.keyboard.pressedScancodes.toList(
              growable: false,
            ),
          },
        );
      }
      return result;
    } catch (error) {
      if (shouldTrace) {
        _loveTraceRuntime(
          'callback.error',
          details: <String, Object?>{
            'name': name,
            'error': error,
            'touches': context.touch.getTouches(),
            'scancodes': context.keyboard.pressedScancodes.toList(
              growable: false,
            ),
          },
        );
      }
      rethrow;
    }
  }

  /// Creates the loop returned by `love.errorhandler`, if one is available.
  Future<Value?> createErrorHandlerLoop(String message) async {
    final callback =
        loveCallback('errorhandler', includeBuiltin: true) ??
        loveCallback('errhand', includeBuiltin: true);
    if (callback == null) {
      return null;
    }

    final result = await runtime.callFunction(
      callback,
      <Object?>[message],
      debugName: callback == _loveField('errorhandler')
          ? 'love.errorhandler'
          : 'love.errhand',
      debugNameWhat: 'callback',
    );
    final wrapped = _value(result);
    return wrapped != null && wrapped.isCallable() ? wrapped : null;
  }

  /// Calls a previously created `love.errorhandler` main loop.
  Future<Object?> callErrorHandlerLoop(Value loop) {
    return runtime.callFunction(
      loop,
      const <Object?>[],
      debugName: 'love.errorhandler.mainLoop',
      debugNameWhat: 'callback',
    );
  }

  /// Calls `love.load` if the script defined it.
  Future<Object?> callLoadIfDefined() => callLoveCallbackIfDefined('load');

  /// Drains queued LOVE events until the event queue becomes empty.
  ///
  /// Returns a non-`null` exit status when a quit event should terminate the
  /// current main loop.
  Future<Object?> processMainLoopEvents() async {
    context.events.pump();
    while (true) {
      final message = context.events.poll();
      if (message == null) {
        return null;
      }

      if (message.name == 'quit' || message.name == 'q') {
        final abortQuit = await callQuitIfDefined();
        if (!abortQuit) {
          return message.arguments.isEmpty ? 0 : message.arguments.first;
        }
        continue;
      }

      final callbackName = _mainLoopCallbackName(message.name);
      if (callbackName == null) {
        throw LuaError('Unknown event: ${message.name}');
      }

      if (_loveShouldTraceRuntimeSignal(callbackName)) {
        _loveTraceRuntime(
          'event.poll',
          details: <String, Object?>{
            'event': message.name,
            'callback': callbackName,
            'args': _loveDescribeRuntimeArgs(message.arguments),
            'touches': context.touch.getTouches(),
            'scancodes': context.keyboard.pressedScancodes.toList(
              growable: false,
            ),
          },
        );
      }

      await callLoveCallbackIfDefined(callbackName, message.arguments);
      if (callbackName == 'lowmemory') {
        await _invokeCollectGarbageIfAvailable();
        await _invokeCollectGarbageIfAvailable();
      }
    }
  }

  /// Calls `love.update` with [dt] if it was defined.
  Future<Object?> callUpdateIfDefined(double dt) {
    return callLoveCallbackIfDefined('update', <Object?>[dt]);
  }

  /// Calls `love.draw` if it was defined.
  Future<Object?> callDrawIfDefined() => callLoveCallbackIfDefined('draw');

  /// Calls `love.quit` if it was defined.
  ///
  /// Returns whether the callback aborted shutdown.
  Future<bool> callQuitIfDefined() async {
    final callback = userLoveCallback('quit');
    if (callback == null) {
      return false;
    }

    final result = await runtime.callFunction(
      callback,
      const <Object?>[],
      debugName: 'love.quit',
      debugNameWhat: 'callback',
    );
    final raw = _unwrapValue(result);
    return raw != null && raw != false;
  }

  Future<Object?> callResizeIfDefined(int width, int height) {
    return callLoveCallbackIfDefined('resize', <Object?>[width, height]);
  }

  Future<Object?> callFocusIfDefined(bool focused) {
    return callLoveCallbackIfDefined('focus', <Object?>[focused]);
  }

  Future<Object?> callDirectoryDroppedIfDefined(String path) {
    return callLoveCallbackIfDefined('directorydropped', <Object?>[path]);
  }

  Future<Object?> callDisplayRotatedIfDefined(int index, String orientation) {
    return callLoveCallbackIfDefined('displayrotated', <Object?>[
      index,
      orientation,
    ]);
  }

  Future<Object?> callFileDroppedIfDefined(String path) async {
    if (userLoveCallback('filedropped') == null) {
      return null;
    }

    final wrapped = await _wrapDroppedFile(path);
    return callLoveCallbackIfDefined('filedropped', <Object?>[wrapped]);
  }

  Future<Object?> callLowMemoryIfDefined() {
    return callLoveCallbackIfDefined('lowmemory');
  }

  Future<Object?> callMouseFocusIfDefined(bool focused) {
    return callLoveCallbackIfDefined('mousefocus', <Object?>[focused]);
  }

  Future<Object?> callVisibleIfDefined(bool visible) {
    return callLoveCallbackIfDefined('visible', <Object?>[visible]);
  }

  Future<Object?> callTextInputIfDefined(String text) {
    return callLoveCallbackIfDefined('textinput', <Object?>[text]);
  }

  Future<Object?> callTextEditedIfDefined(String text, int start, int length) {
    return callLoveCallbackIfDefined('textedited', <Object?>[
      text,
      start,
      length,
    ]);
  }

  Future<Object?> callThreadErrorIfDefined(Object? thread, String error) {
    return callLoveCallbackIfDefined('threaderror', <Object?>[thread, error]);
  }

  Future<Object?> callKeyPressedIfDefined(
    String key, {
    String? scancode,
    bool isRepeat = false,
  }) {
    return callLoveCallbackIfDefined('keypressed', <Object?>[
      key,
      scancode,
      isRepeat,
    ]);
  }

  Future<Object?> callKeyReleasedIfDefined(String key, {String? scancode}) {
    return callLoveCallbackIfDefined('keyreleased', <Object?>[key, scancode]);
  }

  Future<Object?> callMouseMovedIfDefined(
    double x,
    double y,
    double dx,
    double dy, {
    bool isTouch = false,
  }) {
    return callLoveCallbackIfDefined('mousemoved', <Object?>[
      x,
      y,
      dx,
      dy,
      isTouch,
    ]);
  }

  Future<Object?> callMousePressedIfDefined(
    double x,
    double y,
    int button, {
    bool isTouch = false,
    int presses = 1,
  }) {
    return callLoveCallbackIfDefined('mousepressed', <Object?>[
      x,
      y,
      button,
      isTouch,
      presses,
    ]);
  }

  Future<Object?> callMouseReleasedIfDefined(
    double x,
    double y,
    int button, {
    bool isTouch = false,
    int presses = 1,
  }) {
    return callLoveCallbackIfDefined('mousereleased', <Object?>[
      x,
      y,
      button,
      isTouch,
      presses,
    ]);
  }

  Future<Object?> callTouchPressedIfDefined(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return callLoveCallbackIfDefined('touchpressed', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> callTouchReleasedIfDefined(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return callLoveCallbackIfDefined('touchreleased', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> callTouchMovedIfDefined(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return callLoveCallbackIfDefined('touchmoved', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> callWheelMovedIfDefined(double x, double y) {
    return callLoveCallbackIfDefined('wheelmoved', <Object?>[x, y]);
  }

  Future<Object?> dispatchResize(int width, int height) {
    return _dispatchLoveEventAndCallbackIfDefined('resize', <Object?>[
      width,
      height,
    ]);
  }

  Future<Object?> queueResize(int width, int height) {
    return _queueLoveEvent('resize', <Object?>[width, height]);
  }

  Future<Object?> dispatchFocus(bool focused) {
    return _dispatchLoveEventAndCallbackIfDefined('focus', <Object?>[focused]);
  }

  Future<Object?> queueFocus(bool focused) {
    return _queueLoveEvent('focus', <Object?>[focused]);
  }

  Future<Object?> dispatchKeyPressed(
    String key, {
    String? scancode,
    bool isRepeat = false,
  }) {
    return _dispatchLoveEventAndCallbackIfDefined('keypressed', <Object?>[
      key,
      scancode,
      isRepeat,
    ]);
  }

  Future<Object?> queueKeyPressed(
    String key, {
    String? scancode,
    bool isRepeat = false,
  }) {
    return _queueLoveEvent('keypressed', <Object?>[key, scancode, isRepeat]);
  }

  Future<Object?> dispatchKeyReleased(String key, {String? scancode}) {
    return _dispatchLoveEventAndCallbackIfDefined('keyreleased', <Object?>[
      key,
      scancode,
    ]);
  }

  Future<Object?> queueKeyReleased(String key, {String? scancode}) {
    return _queueLoveEvent('keyreleased', <Object?>[key, scancode]);
  }

  Future<Object?> dispatchMouseMoved(
    double x,
    double y,
    double dx,
    double dy, {
    bool isTouch = false,
  }) {
    return _dispatchLoveEventAndCallbackIfDefined('mousemoved', <Object?>[
      x,
      y,
      dx,
      dy,
      isTouch,
    ]);
  }

  Future<Object?> queueMouseMoved(
    double x,
    double y,
    double dx,
    double dy, {
    bool isTouch = false,
  }) {
    return _queueLoveEvent('mousemoved', <Object?>[x, y, dx, dy, isTouch]);
  }

  Future<Object?> dispatchMousePressed(
    double x,
    double y,
    int button, {
    bool isTouch = false,
    int presses = 1,
  }) {
    return _dispatchLoveEventAndCallbackIfDefined('mousepressed', <Object?>[
      x,
      y,
      button,
      isTouch,
      presses,
    ]);
  }

  Future<Object?> queueMousePressed(
    double x,
    double y,
    int button, {
    bool isTouch = false,
    int presses = 1,
  }) {
    return _queueLoveEvent('mousepressed', <Object?>[
      x,
      y,
      button,
      isTouch,
      presses,
    ]);
  }

  Future<Object?> dispatchMouseReleased(
    double x,
    double y,
    int button, {
    bool isTouch = false,
    int presses = 1,
  }) {
    return _dispatchLoveEventAndCallbackIfDefined('mousereleased', <Object?>[
      x,
      y,
      button,
      isTouch,
      presses,
    ]);
  }

  Future<Object?> queueMouseReleased(
    double x,
    double y,
    int button, {
    bool isTouch = false,
    int presses = 1,
  }) {
    return _queueLoveEvent('mousereleased', <Object?>[
      x,
      y,
      button,
      isTouch,
      presses,
    ]);
  }

  Future<Object?> dispatchMouseFocus(bool focused) {
    return _dispatchLoveEventAndCallbackIfDefined('mousefocus', <Object?>[
      focused,
    ]);
  }

  Future<Object?> queueMouseFocus(bool focused) {
    return _queueLoveEvent('mousefocus', <Object?>[focused]);
  }

  Future<Object?> dispatchDirectoryDropped(String path) {
    return _dispatchLoveEventAndCallbackIfDefined('directorydropped', <Object?>[
      path,
    ]);
  }

  Future<Object?> dispatchDisplayRotated(int index, String orientation) {
    return _dispatchLoveEventAndCallbackIfDefined('displayrotated', <Object?>[
      index,
      orientation,
    ]);
  }

  Future<Object?> dispatchFileDropped(String path) async {
    final wrapped = await _wrapDroppedFile(path);
    return _dispatchLoveEventAndCallbackIfDefined('filedropped', <Object?>[
      wrapped,
    ]);
  }

  Future<Object?> dispatchLowMemory() {
    return _dispatchLoveEventAndCallbackIfDefined('lowmemory');
  }

  Future<Object?> queueLowMemory() {
    return _queueLoveEvent('lowmemory');
  }

  Future<Object?> dispatchTextInput(String text) {
    return _dispatchLoveEventAndCallbackIfDefined('textinput', <Object?>[text]);
  }

  Future<Object?> queueTextInput(String text) {
    return _queueLoveEvent('textinput', <Object?>[text]);
  }

  Future<Object?> dispatchTextEdited(String text, int start, int length) {
    return _dispatchLoveEventAndCallbackIfDefined('textedited', <Object?>[
      text,
      start,
      length,
    ]);
  }

  Future<Object?> queueTextEdited(String text, int start, int length) {
    return _queueLoveEvent('textedited', <Object?>[text, start, length]);
  }

  Future<Object?> dispatchThreadError(Object? thread, String error) {
    return _dispatchLoveEventAndCallbackIfDefined('threaderror', <Object?>[
      thread,
      error,
    ]);
  }

  Future<Object?> dispatchTouchPressed(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined('touchpressed', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> queueTouchPressed(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return _queueLoveEvent('touchpressed', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> dispatchTouchReleased(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined('touchreleased', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> queueTouchReleased(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return _queueLoveEvent('touchreleased', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> dispatchTouchMoved(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return _dispatchLoveEventAndCallbackIfDefined('touchmoved', <Object?>[
      id,
      x,
      y,
      dx,
      dy,
      pressure,
    ]);
  }

  Future<Object?> queueTouchMoved(
    int id,
    double x,
    double y,
    double dx,
    double dy,
    double pressure,
  ) {
    return _queueLoveEvent('touchmoved', <Object?>[id, x, y, dx, dy, pressure]);
  }

  Future<Object?> dispatchWheelMoved(double x, double y) {
    return _dispatchLoveEventAndCallbackIfDefined('wheelmoved', <Object?>[
      x,
      y,
    ]);
  }

  Future<Object?> queueWheelMoved(double x, double y) {
    return _queueLoveEvent('wheelmoved', <Object?>[x, y]);
  }

  Future<Object?> dispatchVisible(bool visible) {
    return _dispatchLoveEventAndCallbackIfDefined('visible', <Object?>[
      visible,
    ]);
  }

  Future<Object?> queueVisible(bool visible) {
    return _queueLoveEvent('visible', <Object?>[visible]);
  }

  Object? unwrapGlobal(String name) =>
      _value(runtime.globals.get(name))?.unwrap();

  Map<String, Object?>? unwrapGlobalTable(String name) {
    final global = unwrapGlobal(name);
    if (global is! Map) {
      return null;
    }

    return global.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  }

  Value? _loveField(String name) {
    final love = _value(runtime.globals.get('love'));
    final loveTable = love?.raw;
    if (loveTable is! Map) {
      return null;
    }

    return _value(loveTable[name]);
  }

  void _removeConfStub() {
    final love = _value(runtime.globals.get('love'));
    final loveTable = love?.raw;
    if (loveTable is! Map<dynamic, dynamic>) {
      return;
    }

    final conf = loveTable['conf'];
    final wrapped = _value(conf);
    if (wrapped?.raw is BuiltinFunction) {
      loveTable.remove('conf');
    }
  }

  Value? _value(Object? candidate) {
    if (candidate == null) {
      return null;
    }

    return candidate is Value ? candidate : Value(candidate);
  }

  Future<Object?> _dispatchLoveEventAndCallbackIfDefined(
    String name, [
    List<Object?> args = const <Object?>[],
  ]) async {
    if (_loveShouldTraceRuntimeSignal(name)) {
      _loveTraceRuntime(
        'event.dispatch',
        details: <String, Object?>{
          'event': name,
          'args': _loveDescribeRuntimeArgs(args),
          'touches': context.touch.getTouches(),
          'scancodes': context.keyboard.pressedScancodes.toList(
            growable: false,
          ),
        },
      );
    }
    context.events.pushMessage(name, args);
    return callLoveCallbackIfDefined(name, args);
  }

  Future<Object?> _queueLoveEvent(
    String name, [
    List<Object?> args = const <Object?>[],
  ]) {
    if (_loveShouldTraceRuntimeSignal(name)) {
      _loveTraceRuntime(
        'event.queue',
        details: <String, Object?>{
          'event': name,
          'args': _loveDescribeRuntimeArgs(args),
          'touches': context.touch.getTouches(),
          'scancodes': context.keyboard.pressedScancodes.toList(
            growable: false,
          ),
        },
      );
    }
    context.events.pushMessage(name, args);
    return Future<Object?>.value(null);
  }

  String? _mainLoopCallbackName(String name) {
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

  Future<void> _invokeCollectGarbageIfAvailable() async {
    final collectGarbage = _value(runtime.globals.get('collectgarbage'));
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

  Future<Value> _wrapDroppedFile(String path) {
    final file = LoveFilesystemDroppedFile(
      state: LoveFilesystemState.attach(runtime),
      filename: path,
    );
    return wrapLoveFilesystemDroppedFileForRuntime(runtime, file);
  }

  _LoveConfTable _defaultLoveConfigTable() {
    return _LoveConfTable(<Object?, Object?>{
      'identity': null,
      'appendidentity': false,
      'version': loveVersionString,
      'console': false,
      'gammacorrect': false,
      'accelerometerjoystick': true,
      'externalstorage': false,
      'audio': _LoveConfTable(<Object?, Object?>{
        'mic': false,
        'mixwithsystem': false,
      }),
      'window': _LoveConfTable(<Object?, Object?>{
        'title': context.windowMetrics.title,
        'icon': null,
        'width': context.windowMetrics.width,
        'height': context.windowMetrics.height,
        'x': null,
        'y': null,
        'fullscreen': context.windowMetrics.fullscreen,
        'fullscreentype': context.windowMetrics.fullscreenType,
        'vsync': context.windowMetrics.vsync,
        'msaa': context.windowMetrics.msaa,
        'resizable': context.windowMetrics.resizable,
        'borderless': context.windowMetrics.borderless,
        'centered': context.windowMetrics.centered,
        'display': context.windowMetrics.display,
        'minwidth': context.windowMetrics.minWidth,
        'minheight': context.windowMetrics.minHeight,
        'highdpi': context.windowMetrics.highDpi,
        'refreshrate': context.windowMetrics.refreshRate,
      }),
      'modules': _LoveConfTable(<Object?, Object?>{
        'audio': true,
        'data': true,
        'event': true,
        'font': true,
        'graphics': true,
        'image': true,
        'joystick': true,
        'keyboard': true,
        'math': true,
        'mouse': true,
        'physics': true,
        'sound': true,
        'system': true,
        'thread': true,
        'timer': true,
        'touch': true,
        'video': true,
        'window': true,
      }),
    });
  }

  void _applyLoveConfig(Map<Object?, Object?> config) {
    final filesystem = LoveFilesystemState.of(runtime);
    final audio = _tableValue(config['audio']);
    final window = _tableValue(config['window']);
    final modules = _tableValue(config['modules']);

    final identity = _stringValue(config['identity']);
    if (identity != null && identity.isNotEmpty) {
      filesystem.setIdentity(
        identity,
        appendToPath: _boolValue(config['appendidentity']) ?? false,
      );
    }

    if (audio != null) {
      context.audio.mixWithSystem =
          _boolValue(audio['mixwithsystem']) ?? context.audio.mixWithSystem;
    }

    if (window != null) {
      context.host.windowMetrics = context.windowMetrics.copyWith(
        title: _stringValue(window['title']) ?? context.windowMetrics.title,
        width: _intValue(window['width']) ?? context.windowMetrics.width,
        height: _intValue(window['height']) ?? context.windowMetrics.height,
        x: _intValue(window['x']) ?? context.windowMetrics.x,
        y: _intValue(window['y']) ?? context.windowMetrics.y,
        fullscreen:
            _boolValue(window['fullscreen']) ??
            context.windowMetrics.fullscreen,
        fullscreenType:
            _stringValue(window['fullscreentype']) ??
            context.windowMetrics.fullscreenType,
        vsync: _intValue(window['vsync']) ?? context.windowMetrics.vsync,
        msaa: _intValue(window['msaa']) ?? context.windowMetrics.msaa,
        resizable:
            _boolValue(window['resizable']) ?? context.windowMetrics.resizable,
        borderless:
            _boolValue(window['borderless']) ??
            context.windowMetrics.borderless,
        centered:
            _boolValue(window['centered']) ?? context.windowMetrics.centered,
        display: _intValue(window['display']) ?? context.windowMetrics.display,
        minWidth:
            _intValue(window['minwidth']) ?? context.windowMetrics.minWidth,
        minHeight:
            _intValue(window['minheight']) ?? context.windowMetrics.minHeight,
        highDpi: _boolValue(window['highdpi']) ?? context.windowMetrics.highDpi,
        refreshRate:
            _intValue(window['refreshrate']) ??
            context.windowMetrics.refreshRate,
      );
    }

    if (modules != null) {
      _applyModuleToggles(modules);
    }
  }

  void _applyModuleToggles(Map<Object?, Object?> modules) {
    final loveValue = _value(runtime.globals.get('love'));
    final loveTable = switch (loveValue?.raw) {
      final Map<dynamic, dynamic> map => map,
      _ => null,
    };
    if (loveTable == null) {
      return;
    }

    for (final entry in modules.entries) {
      final moduleName = _stringValue(entry.key);
      final enabled = _boolValue(entry.value);
      if (moduleName == null || enabled != false) {
        continue;
      }

      if (moduleName == 'love' || moduleName == 'filesystem') {
        continue;
      }

      loveTable.remove(moduleName);
      if (moduleName == 'window') {
        loveTable.remove('graphics');
      }
    }
  }

  Map<Object?, Object?>? _tableValue(Object? value) {
    return switch (_unwrapValue(value)) {
      final Map<dynamic, dynamic> table => table.map(
        (key, value) => MapEntry(key, value),
      ),
      _ => null,
    };
  }

  String? _stringValue(Object? value) {
    return switch (_unwrapValue(value)) {
      final String text => text,
      final LuaString text => text.toString(),
      _ => null,
    };
  }

  bool? _boolValue(Object? value) {
    return switch (_unwrapValue(value)) {
      final bool flag => flag,
      _ => null,
    };
  }

  int? _intValue(Object? value) {
    return switch (_unwrapValue(value)) {
      final num number => number.round(),
      _ => null,
    };
  }

  Object? _unwrapValue(Object? value) => value is Value ? value.raw : value;
}

bool _isGeneratedLoveCallbackStub(Value callback) {
  final raw = callback.raw;
  return raw is BuiltinFunction && raw is! LuaCallableArtifact;
}

/// A Lua table wrapper used to stage `conf.lua` bootstrap values.
class _LoveConfTable extends MapBase<dynamic, dynamic>
    implements VirtualLuaTable {
  /// Creates a bootstrap configuration table from raw [values].
  _LoveConfTable(Map<Object?, Object?> values)
    : _values = <dynamic, dynamic>{
        for (final entry in values.entries) entry.key: _wrap(entry.value),
      };

  /// The wrapped Lua-visible values stored in this table.
  final Map<dynamic, dynamic> _values;

  /// Wraps nested values so Lua sees tables and primitives consistently.
  static dynamic _wrap(Object? value) {
    return switch (value) {
      final Value wrapped => wrapped,
      final _LoveConfTable table => Value(table),
      final Map<Object?, Object?> table => Value(_LoveConfTable(table)),
      _ => Value(value),
    };
  }

  @override
  dynamic operator [](Object? key) => _values[key];

  @override
  void operator []=(dynamic key, dynamic value) {
    _values[key] = _wrap(value);
  }

  @override
  void clear() => _values.clear();

  @override
  Iterable<dynamic> get keys => _values.keys;

  @override
  dynamic remove(Object? key) => _values.remove(key);
}
