part of '../love_api_bindings.dart';

LoveApiImplementation _bindTimerGetTime(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.time;
}

LoveApiImplementation _bindTimerStep(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.step();
}

LoveApiImplementation _bindTimerGetDelta(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.delta;
}

LoveApiImplementation _bindTimerGetAverageDelta(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.averageDelta;
}

LoveApiImplementation _bindTimerGetFps(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.fps;
}

LoveApiImplementation _bindTimerSleep(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final seconds = _requireNumber(args, 0, 'love.timer.sleep');
    await runtime.sleep(seconds);
    return null;
  };
}
