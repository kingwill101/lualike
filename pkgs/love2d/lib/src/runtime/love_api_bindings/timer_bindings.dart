part of '../love_api_bindings.dart';

/// Binds `love.timer.getTime`.
LoveApiImplementation _bindTimerGetTime(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.time;
}

/// Binds `love.timer.step`.
LoveApiImplementation _bindTimerStep(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.step();
}

/// Binds `love.timer.getDelta`.
LoveApiImplementation _bindTimerGetDelta(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.delta;
}

/// Binds `love.timer.getAverageDelta`.
LoveApiImplementation _bindTimerGetAverageDelta(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.averageDelta;
}

/// Binds `love.timer.getFPS`.
LoveApiImplementation _bindTimerGetFps(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.fps;
}

/// Binds `love.timer.sleep`.
LoveApiImplementation _bindTimerSleep(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final seconds = _requireNumber(args, 0, 'love.timer.sleep');
    await runtime.sleep(seconds);
    return null;
  };
}
