part of '../love_runtime.dart';

/// The normalized power-state strings exposed through `love.system`.
const Set<String> loveSystemPowerStateConstants = <String>{
  'unknown',
  'battery',
  'nobattery',
  'charging',
  'charged',
};

/// Reads the current clipboard text from the host system.
typedef LoveSystemClipboardReadHandler = FutureOr<String> Function();

/// Writes [text] to the host system clipboard.
typedef LoveSystemClipboardWriteHandler = FutureOr<void> Function(String text);

/// Opens [url] through the host system.
typedef LoveSystemOpenUrlHandler = FutureOr<bool> Function(String url);

/// Triggers host vibration for [seconds], when supported.
typedef LoveSystemVibrateHandler = FutureOr<void> Function(double seconds);

/// Normalizes a power-state string to a supported LOVE constant.
String loveNormalizeSystemPowerState(String state) {
  final key = state.trim().toLowerCase();
  return switch (key) {
    'unknown' => 'unknown',
    'battery' => 'battery',
    'nobattery' => 'nobattery',
    'charging' => 'charging',
    'charged' => 'charged',
    _ => 'unknown',
  };
}

/// Battery and power information reported through `love.system`.
class LoveSystemPowerInfo {
  /// Creates a power information snapshot.
  const LoveSystemPowerInfo({
    this.state = 'unknown',
    this.percent,
    this.seconds,
  });

  /// The normalized power source state.
  final String state;

  /// The remaining battery percentage, if one is known.
  final int? percent;

  /// The estimated remaining battery life in seconds, if one is known.
  final int? seconds;

  /// Returns a copy of this power information with selected fields replaced.
  LoveSystemPowerInfo copyWith({String? state, int? percent, int? seconds}) {
    return LoveSystemPowerInfo(
      state: state ?? this.state,
      percent: percent ?? this.percent,
      seconds: seconds ?? this.seconds,
    );
  }
}

/// The mutable LOVE system state exposed to scripts and host integrations.
class LoveSystemState {
  /// Creates a system state backed by optional host capability handlers.
  LoveSystemState({
    this.os = 'Unknown',
    this.processorCount = 1,
    LoveSystemPowerInfo? powerInfo,
    this.backgroundMusic = false,
    this.clipboardText = '',
    this.clipboardReadHandler,
    this.clipboardWriteHandler,
    this.openUrlHandler,
    this.vibrateHandler,
  }) : powerInfo = powerInfo ?? const LoveSystemPowerInfo();

  /// The operating system name reported to LOVE.
  String os;

  /// The number of processors reported to LOVE.
  int processorCount;

  /// The current power information snapshot.
  LoveSystemPowerInfo powerInfo;

  /// Whether background music playback should be treated as active.
  bool backgroundMusic;

  /// The last clipboard text cached by this system state.
  String clipboardText;

  /// The optional host callback used to read clipboard text.
  final LoveSystemClipboardReadHandler? clipboardReadHandler;

  /// The optional host callback used to write clipboard text.
  final LoveSystemClipboardWriteHandler? clipboardWriteHandler;

  /// The optional host callback used to open URLs.
  final LoveSystemOpenUrlHandler? openUrlHandler;

  /// The optional host callback used to trigger device vibration.
  final LoveSystemVibrateHandler? vibrateHandler;

  /// Returns the current clipboard text.
  ///
  /// When a host clipboard reader is available, this refreshes [clipboardText]
  /// from that source before returning it.
  Future<String> getClipboardText() async {
    final reader = clipboardReadHandler;
    if (reader == null) {
      return clipboardText;
    }

    final text = await reader();
    clipboardText = text;
    return text;
  }

  /// Updates the clipboard text to [text].
  ///
  /// This always updates the cached [clipboardText] and then delegates to the
  /// host clipboard writer when one is available.
  Future<void> setClipboardText(String text) async {
    clipboardText = text;

    final writer = clipboardWriteHandler;
    if (writer != null) {
      await writer(text);
    }
  }

  /// Requests that the host open [url].
  Future<bool> openUrl(String url) async {
    final handler = openUrlHandler;
    if (handler == null) {
      return false;
    }

    return await handler(url);
  }

  /// Requests device vibration for [seconds], when the host supports it.
  Future<void> vibrate(double seconds) async {
    final handler = vibrateHandler;
    if (handler != null) {
      await handler(seconds);
    }
  }
}
