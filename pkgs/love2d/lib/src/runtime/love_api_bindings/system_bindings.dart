part of '../love_api_bindings.dart';

/// Binds `love.system.getClipboardText`.
LoveApiImplementation _bindSystemGetClipboardText(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async => runtime.system.getClipboardText();
}

/// Binds `love.system.getOS`.
LoveApiImplementation _bindSystemGetOs(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.system.os;
}

/// Binds `love.system.getPowerInfo`.
///
/// The returned values match LOVE's `(state, percent, seconds)` tuple shape.
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

/// Binds `love.system.getProcessorCount`.
///
/// LOVE expects this call to report at least one processor even when the host
/// cannot determine the count.
LoveApiImplementation _bindSystemGetProcessorCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => math.max(runtime.system.processorCount, 1);
}

/// Binds `love.system.hasBackgroundMusic`.
LoveApiImplementation _bindSystemHasBackgroundMusic(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.system.backgroundMusic;
}

/// Binds `love.system.openURL`.
LoveApiImplementation _bindSystemOpenUrl(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final url = _requireString(args, 0, 'love.system.openURL');
    return runtime.system.openUrl(url);
  };
}

/// Binds `love.system.setClipboardText`.
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

/// Binds `love.system.vibrate`.
///
/// When Lua omits the duration, LOVE defaults the vibration request to
/// half a second.
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
