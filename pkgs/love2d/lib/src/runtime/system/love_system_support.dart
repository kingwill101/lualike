part of '../love_runtime.dart';

const Set<String> loveSystemPowerStateConstants = <String>{
  'unknown',
  'battery',
  'nobattery',
  'charging',
  'charged',
};

typedef LoveSystemClipboardReadHandler = FutureOr<String> Function();
typedef LoveSystemClipboardWriteHandler = FutureOr<void> Function(String text);
typedef LoveSystemOpenUrlHandler = FutureOr<bool> Function(String url);
typedef LoveSystemVibrateHandler = FutureOr<void> Function(double seconds);

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

class LoveSystemPowerInfo {
  const LoveSystemPowerInfo({
    this.state = 'unknown',
    this.percent,
    this.seconds,
  });

  final String state;
  final int? percent;
  final int? seconds;

  LoveSystemPowerInfo copyWith({String? state, int? percent, int? seconds}) {
    return LoveSystemPowerInfo(
      state: state ?? this.state,
      percent: percent ?? this.percent,
      seconds: seconds ?? this.seconds,
    );
  }
}

class LoveSystemState {
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

  String os;
  int processorCount;
  LoveSystemPowerInfo powerInfo;
  bool backgroundMusic;
  String clipboardText;
  final LoveSystemClipboardReadHandler? clipboardReadHandler;
  final LoveSystemClipboardWriteHandler? clipboardWriteHandler;
  final LoveSystemOpenUrlHandler? openUrlHandler;
  final LoveSystemVibrateHandler? vibrateHandler;

  Future<String> getClipboardText() async {
    final reader = clipboardReadHandler;
    if (reader == null) {
      return clipboardText;
    }

    final text = await reader();
    clipboardText = text;
    return text;
  }

  Future<void> setClipboardText(String text) async {
    clipboardText = text;

    final writer = clipboardWriteHandler;
    if (writer != null) {
      await writer(text);
    }
  }

  Future<bool> openUrl(String url) async {
    final handler = openUrlHandler;
    if (handler == null) {
      return false;
    }

    return await handler(url);
  }

  Future<void> vibrate(double seconds) async {
    final handler = vibrateHandler;
    if (handler != null) {
      await handler(seconds);
    }
  }
}
