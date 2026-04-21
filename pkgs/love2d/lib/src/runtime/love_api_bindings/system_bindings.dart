part of '../love_api_bindings.dart';

LoveApiImplementation _bindSystemGetClipboardText(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async => runtime.system.getClipboardText();
}

LoveApiImplementation _bindSystemGetOs(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.system.os;
}

LoveApiImplementation _bindSystemGetPowerInfo(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final powerInfo = runtime.system.powerInfo;
    return Value.multi(<Object?>[
      loveNormalizeSystemPowerState(powerInfo.state),
      powerInfo.percent,
      powerInfo.seconds,
    ]);
  };
}

LoveApiImplementation _bindSystemGetProcessorCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => math.max(runtime.system.processorCount, 1);
}

LoveApiImplementation _bindSystemHasBackgroundMusic(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.system.backgroundMusic;
}

LoveApiImplementation _bindSystemOpenUrl(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final url = _requireString(args, 0, 'love.system.openURL');
    return runtime.system.openUrl(url);
  };
}

LoveApiImplementation _bindSystemSetClipboardText(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final text = _requireString(args, 0, 'love.system.setClipboardText');
    await runtime.system.setClipboardText(text);
    return null;
  };
}

LoveApiImplementation _bindSystemVibrate(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final seconds = args.isEmpty
        ? 0.5
        : _requireNumber(args, 0, 'love.system.vibrate');
    await runtime.system.vibrate(seconds);
    return null;
  };
}
