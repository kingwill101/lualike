part of 'love_flame_input.dart';

/// Debug-name overrides that map Flutter logical keys to LOVE key constants.
const Map<String, String> _logicalDebugNameToLoveKey = <String, String>{
  'enter': 'return',
  'escape': 'escape',
  'backspace': 'backspace',
  'tab': 'tab',
  'space': 'space',
  'caps lock': 'capslock',
  'print screen': 'printscreen',
  'scroll lock': 'scrolllock',
  'pause': 'pause',
  'insert': 'insert',
  'home': 'home',
  'page up': 'pageup',
  'delete': 'delete',
  'end': 'end',
  'page down': 'pagedown',
  'arrow right': 'right',
  'arrow left': 'left',
  'arrow down': 'down',
  'arrow up': 'up',
  'num lock': 'numlock',
  'context menu': 'application',
  'power': 'power',
  'audio volume up': 'volumeup',
  'audio volume down': 'volumedown',
  'audio volume mute': 'mute',
  'media play pause': 'audioplay',
  'media stop': 'audiostop',
  'media track next': 'audionext',
  'media track previous': 'audioprev',
  'browser search': 'appsearch',
  'browser home': 'apphome',
  'browser back': 'appback',
  'browser forward': 'appforward',
  'browser stop': 'appstop',
  'browser refresh': 'apprefresh',
  'browser favorites': 'appbookmarks',
};

/// Debug-name overrides that map Flutter physical keys to LOVE scancodes.
const Map<String, String> _physicalDebugNameToLoveScancode = <String, String>{
  'enter': 'return',
  'escape': 'escape',
  'backspace': 'backspace',
  'tab': 'tab',
  'space': 'space',
  'minus': '-',
  'equal': '=',
  'bracket left': '[',
  'bracket right': ']',
  'backslash': '\\',
  'semicolon': ';',
  'quote': '\'',
  'backquote': '`',
  'comma': ',',
  'period': '.',
  'slash': '/',
  'caps lock': 'capslock',
  'print screen': 'printscreen',
  'scroll lock': 'scrolllock',
  'pause': 'pause',
  'insert': 'insert',
  'home': 'home',
  'page up': 'pageup',
  'delete': 'delete',
  'end': 'end',
  'page down': 'pagedown',
  'arrow right': 'right',
  'arrow left': 'left',
  'arrow down': 'down',
  'arrow up': 'up',
  'num lock': 'numlock',
  'numpad divide': 'kp/',
  'numpad multiply': 'kp*',
  'numpad subtract': 'kp-',
  'numpad add': 'kp+',
  'numpad enter': 'kpenter',
  'numpad decimal': 'kp.',
  'numpad comma': 'kp,',
  'numpad equal': 'kp=',
  'context menu': 'application',
  'power': 'power',
  'control left': 'lctrl',
  'shift left': 'lshift',
  'alt left': 'lalt',
  'meta left': 'lgui',
  'control right': 'rctrl',
  'shift right': 'rshift',
  'alt right': 'ralt',
  'meta right': 'rgui',
  'audio volume up': 'volumeup',
  'audio volume down': 'volumedown',
  'audio volume mute': 'mute',
  'media play pause': 'audioplay',
  'media stop': 'audiostop',
  'media track next': 'audionext',
  'media track previous': 'audioprev',
  'browser search': 'acsearch',
  'browser home': 'achome',
  'browser back': 'acback',
  'browser forward': 'acforward',
  'browser stop': 'acstop',
  'browser refresh': 'acrefresh',
  'browser favorites': 'acbookmarks',
};

/// Returns the LOVE key constant corresponding to a Flutter [event].
///
/// This prefers printable labels and characters, then falls back to debug-name
/// mappings and finally to the provided [scancode] when available.
String loveKeyFromFlutterKeyEvent(KeyEvent event, {String? scancode}) {
  final logicalLabel = event.logicalKey.keyLabel;
  if (logicalLabel.length == 1) {
    final lowerLabel = logicalLabel.toLowerCase();
    if (loveIsValidKeyConstant(lowerLabel) &&
        RegExp(r'^[a-z]$').hasMatch(lowerLabel)) {
      return lowerLabel;
    }
  }

  final character = event.character;
  if (character != null && character.isNotEmpty) {
    if (loveIsValidKeyConstant(character)) {
      return character;
    }

    final lowerCharacter = character.toLowerCase();
    if (loveIsValidKeyConstant(lowerCharacter) &&
        RegExp(r'^[a-z]$').hasMatch(lowerCharacter)) {
      return lowerCharacter;
    }
  }

  if (logicalLabel.isNotEmpty) {
    final normalized = logicalLabel.toLowerCase();
    if (loveIsValidKeyConstant(normalized)) {
      return normalized;
    }
  }

  final debugName = event.logicalKey.debugName?.toLowerCase();
  if (debugName != null) {
    final mapped = _logicalDebugNameToLoveKey[debugName];
    if (mapped != null) {
      return mapped;
    }

    final functionMatch = RegExp(r'^f(\d+)$').firstMatch(debugName);
    if (functionMatch != null) {
      final candidate = 'f${functionMatch.group(1)}';
      if (loveIsValidKeyConstant(candidate)) {
        return candidate;
      }
    }
  }

  if (scancode != null && scancode != 'unknown') {
    final fallback = LoveKeyboardState().getKeyFromScancode(scancode);
    if (fallback != 'unknown') {
      return fallback;
    }
  }

  return 'unknown';
}

/// Returns the LOVE scancode corresponding to [physicalKey].
String loveScancodeFromFlutterPhysicalKey(PhysicalKeyboardKey physicalKey) {
  final debugName = physicalKey.debugName?.toLowerCase();
  if (debugName == null || debugName.isEmpty) {
    return 'unknown';
  }

  final mapped = _physicalDebugNameToLoveScancode[debugName];
  if (mapped != null) {
    return mapped;
  }

  final keyMatch = RegExp(r'^key ([a-z])$').firstMatch(debugName);
  if (keyMatch != null) {
    return keyMatch.group(1)!;
  }

  final digitMatch = RegExp(r'^digit ([0-9])$').firstMatch(debugName);
  if (digitMatch != null) {
    return digitMatch.group(1)!;
  }

  final numpadMatch = RegExp(r'^numpad ([0-9])$').firstMatch(debugName);
  if (numpadMatch != null) {
    return 'kp${numpadMatch.group(1)}';
  }

  final functionMatch = RegExp(r'^f(\d+)$').firstMatch(debugName);
  if (functionMatch != null) {
    final candidate = 'f${functionMatch.group(1)}';
    if (loveIsValidScancode(candidate)) {
      return candidate;
    }
  }

  return 'unknown';
}
