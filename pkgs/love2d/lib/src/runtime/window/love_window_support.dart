part of '../love_runtime.dart';

const Set<String> loveWindowDisplayOrientationConstants = <String>{
  'unknown',
  'landscape',
  'landscapeflipped',
  'portrait',
  'portraitflipped',
};

const Set<String> loveWindowFullscreenTypeConstants = <String>{
  'desktop',
  'exclusive',
  'normal',
};

const Set<String> loveWindowMessageBoxTypeConstants = <String>{
  'info',
  'warning',
  'error',
};

typedef LoveWindowMessageBoxHandler =
    FutureOr<LoveWindowMessageBoxResponse> Function(
      LoveWindowMessageBoxData data,
    );

String loveNormalizeWindowDisplayOrientation(String orientation) {
  final key = orientation.trim().toLowerCase();
  return switch (key) {
    'unknown' => 'unknown',
    'landscape' => 'landscape',
    'landscapeflipped' => 'landscapeflipped',
    'portrait' => 'portrait',
    'portraitflipped' => 'portraitflipped',
    _ => 'unknown',
  };
}

class LoveWindowMessageBoxData {
  LoveWindowMessageBoxData({
    required this.title,
    required this.message,
    this.type = 'info',
    this.attachToWindow = true,
    this.buttons = const <String>['OK'],
    int? enterButtonIndex,
    int? escapeButtonIndex,
  }) : enterButtonIndex = enterButtonIndex ?? 1,
       escapeButtonIndex =
           escapeButtonIndex ?? (buttons.isEmpty ? 0 : buttons.length);

  final String title;
  final String message;
  final String type;
  final bool attachToWindow;
  final List<String> buttons;
  final int enterButtonIndex;
  final int escapeButtonIndex;
}

class LoveWindowMessageBoxResponse {
  const LoveWindowMessageBoxResponse({
    this.success = true,
    this.pressedButtonIndex = 1,
  });

  final bool success;
  final int pressedButtonIndex;
}
