part of '../love_runtime.dart';

/// The normalized window display-orientation strings exposed through LOVE.
const Set<String> loveWindowDisplayOrientationConstants = <String>{
  'unknown',
  'landscape',
  'landscapeflipped',
  'portrait',
  'portraitflipped',
};

/// The supported fullscreen type strings exposed through LOVE.
const Set<String> loveWindowFullscreenTypeConstants = <String>{
  'desktop',
  'exclusive',
  'normal',
};

/// The supported message-box type strings exposed through LOVE.
const Set<String> loveWindowMessageBoxTypeConstants = <String>{
  'info',
  'warning',
  'error',
};

/// Shows a window message box through the host integration layer.
typedef LoveWindowMessageBoxHandler =
    FutureOr<LoveWindowMessageBoxResponse> Function(
      LoveWindowMessageBoxData data,
    );

/// Normalizes a display-orientation string to a supported LOVE constant.
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

/// The payload used when LOVE requests a host message box.
class LoveWindowMessageBoxData {
  /// Creates message-box data for a host window prompt.
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

  /// The dialog title.
  final String title;

  /// The dialog body text.
  final String message;

  /// The message-box type, such as `info`, `warning`, or `error`.
  final String type;

  /// Whether the dialog should be attached to the game window when possible.
  final bool attachToWindow;

  /// The button labels shown in the dialog.
  final List<String> buttons;

  /// The 1-based button index activated by the Enter key.
  final int enterButtonIndex;

  /// The 1-based button index activated by the Escape key.
  final int escapeButtonIndex;
}

/// The host response returned from a LOVE message-box request.
class LoveWindowMessageBoxResponse {
  /// Creates a message-box response.
  const LoveWindowMessageBoxResponse({
    this.success = true,
    this.pressedButtonIndex = 1,
  });

  /// Whether the host showed the message box successfully.
  final bool success;

  /// The 1-based index of the button pressed by the user.
  final int pressedButtonIndex;
}
