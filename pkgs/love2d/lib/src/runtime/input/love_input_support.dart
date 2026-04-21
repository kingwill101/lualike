part of '../love_runtime.dart';

class LoveTextInputArea {
  const LoveTextInputArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class LoveMouseCursor {
  LoveMouseCursor.system(String type)
    : systemType = type,
      imageData = null,
      source = null,
      hotspotX = 0,
      hotspotY = 0;

  LoveMouseCursor.image({
    this.imageData,
    this.source,
    this.hotspotX = 0,
    this.hotspotY = 0,
  }) : systemType = null;

  final String? systemType;
  final LoveImageData? imageData;
  final String? source;
  final int hotspotX;
  final int hotspotY;

  bool get isSystemCursor => systemType != null;

  String getType() => systemType ?? 'image';
}

class LoveKeyboardState {
  LoveKeyboardState({
    this.keyRepeat = false,
    this.textInputEnabled = true,
    this.screenKeyboardSupported = false,
  });

  bool keyRepeat;
  bool textInputEnabled;
  bool screenKeyboardSupported;
  LoveTextInputArea? textInputArea;

  final Set<String> _pressedScancodes = <String>{};

  Set<String> get pressedScancodes =>
      UnmodifiableSetView<String>(_pressedScancodes);

  bool isDown(Iterable<String> keys) {
    for (final key in keys) {
      if (_pressedScancodes.contains(getScancodeFromKey(key))) {
        return true;
      }
    }

    return false;
  }

  bool isScancodeDown(Iterable<String> scancodes) {
    for (final scancode in scancodes) {
      if (_pressedScancodes.contains(scancode)) {
        return true;
      }
    }

    return false;
  }

  String getKeyFromScancode(String scancode) {
    return _loveKeyboardScancodeToKeyOverrides[scancode] ??
        (_loveKeyboardKeyConstants.contains(scancode) ? scancode : 'unknown');
  }

  String getScancodeFromKey(String key) {
    return _loveKeyboardKeyToScancodeOverrides[key] ??
        (_loveKeyboardScancodeConstants.contains(key) ? key : 'unknown');
  }

  void setTextInput(bool enable, {LoveTextInputArea? area}) {
    textInputEnabled = enable;
    if (area != null) {
      textInputArea = area;
    }
  }

  void setKeyDown(String key, {String? scancode, required bool down}) {
    final resolvedScancode = scancode ?? getScancodeFromKey(key);
    if (resolvedScancode == 'unknown') {
      return;
    }

    if (down) {
      _pressedScancodes.add(resolvedScancode);
    } else {
      _pressedScancodes.remove(resolvedScancode);
    }
  }

  void setScancodeDown(String scancode, {required bool down}) {
    if (down) {
      _pressedScancodes.add(scancode);
    } else {
      _pressedScancodes.remove(scancode);
    }
  }
}

class LoveMouseState {
  LoveMouseState({
    double x = 0.0,
    double y = 0.0,
    this.cursorSupported = true,
    this.grabbed = false,
    this.relativeMode = false,
    bool visible = true,
  }) : _x = x.floorToDouble(),
       _y = y.floorToDouble(),
       _visible = visible;

  double _x;
  double _y;
  bool cursorSupported;
  bool grabbed;
  bool relativeMode;
  bool _visible;
  LoveMouseCursor? _cursor;
  bool _programmaticPositionActive = false;

  final Set<int> _buttonsDown = <int>{};
  final Map<String, LoveMouseCursor> _systemCursorCache =
      <String, LoveMouseCursor>{};

  double get x => _x;

  double get y => _y;

  bool get visible => _visible && !relativeMode;

  LoveMouseCursor? get cursor => _cursor;

  bool get programmaticPositionActive => _programmaticPositionActive;

  Set<int> get buttonsDown => UnmodifiableSetView<int>(_buttonsDown);

  void setX(double x, {bool fromSystemEvent = false}) {
    _x = x.floorToDouble();
    _programmaticPositionActive = !fromSystemEvent;
  }

  void setY(double y, {bool fromSystemEvent = false}) {
    _y = y.floorToDouble();
    _programmaticPositionActive = !fromSystemEvent;
  }

  void setPosition(double x, double y, {bool fromSystemEvent = false}) {
    _x = x.floorToDouble();
    _y = y.floorToDouble();
    _programmaticPositionActive = !fromSystemEvent;
  }

  bool isDown(Iterable<int> buttons) {
    for (final button in buttons) {
      if (_buttonsDown.contains(button)) {
        return true;
      }
    }

    return false;
  }

  void setButtonDown(int button, {required bool down}) {
    if (down) {
      _buttonsDown.add(button);
    } else {
      _buttonsDown.remove(button);
    }
  }

  void setVisible(bool visible) {
    _visible = visible;
  }

  bool setRelativeMode(bool enabled) {
    relativeMode = enabled;
    return true;
  }

  void setCursor([LoveMouseCursor? cursor]) {
    _cursor = cursor;
  }

  LoveMouseCursor getSystemCursor(String type) {
    return _systemCursorCache.putIfAbsent(
      type,
      () => LoveMouseCursor.system(type),
    );
  }

  LoveMouseCursor newCursor({
    LoveImageData? imageData,
    String? source,
    int hotspotX = 0,
    int hotspotY = 0,
  }) {
    return LoveMouseCursor.image(
      imageData: imageData,
      source: source,
      hotspotX: hotspotX,
      hotspotY: hotspotY,
    );
  }
}

bool loveIsValidKeyConstant(String key) =>
    _loveKeyboardKeyConstants.contains(key);

bool loveIsValidScancode(String scancode) =>
    _loveKeyboardScancodeConstants.contains(scancode);

bool loveIsValidCursorType(String cursorType) =>
    _loveMouseSystemCursorTypes.contains(cursorType);

const Map<String, String> _loveKeyboardKeyToScancodeOverrides =
    <String, String>{
      '!': '1',
      '"': '\'',
      '#': '3',
      '%': '5',
      r'$': '4',
      '&': '7',
      '\'': '\'',
      '(': '9',
      ')': '0',
      '*': '8',
      '+': '=',
      ':': ';',
      '<': ',',
      '@': '2',
      '>': '.',
      '?': '/',
      '^': '6',
      '_': '-',
      'appsearch': 'acsearch',
      'apphome': 'achome',
      'appback': 'acback',
      'appforward': 'acforward',
      'appstop': 'acstop',
      'apprefresh': 'acrefresh',
      'appbookmarks': 'acbookmarks',
    };

final Map<String, String> _loveKeyboardScancodeToKeyOverrides =
    <String, String>{
      for (final entry in _loveKeyboardKeyToScancodeOverrides.entries)
        if (!_loveKeyboardKeyConstants.contains(entry.value))
          entry.value: entry.key,
    };

const Set<String> _loveMouseSystemCursorTypes = <String>{
  'arrow',
  'ibeam',
  'wait',
  'crosshair',
  'waitarrow',
  'sizenwse',
  'sizenesw',
  'sizewe',
  'sizens',
  'sizeall',
  'no',
  'hand',
};

final Set<String> _loveKeyboardKeyConstants = <String>{
  'unknown',
  'return',
  'escape',
  'backspace',
  'tab',
  'space',
  '!',
  '"',
  '#',
  '%',
  r'$',
  '&',
  '\'',
  '(',
  ')',
  '*',
  '+',
  ',',
  '-',
  '.',
  '/',
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  ':',
  ';',
  '<',
  '=',
  '>',
  '?',
  '@',
  '[',
  '\\',
  ']',
  '^',
  '_',
  '`',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
  'x',
  'y',
  'z',
  'capslock',
  'f1',
  'f2',
  'f3',
  'f4',
  'f5',
  'f6',
  'f7',
  'f8',
  'f9',
  'f10',
  'f11',
  'f12',
  'printscreen',
  'scrolllock',
  'pause',
  'insert',
  'home',
  'pageup',
  'delete',
  'end',
  'pagedown',
  'right',
  'left',
  'down',
  'up',
  'numlock',
  'kp/',
  'kp*',
  'kp-',
  'kp+',
  'kpenter',
  'kp0',
  'kp1',
  'kp2',
  'kp3',
  'kp4',
  'kp5',
  'kp6',
  'kp7',
  'kp8',
  'kp9',
  'kp.',
  'kp,',
  'kp=',
  'application',
  'power',
  'f13',
  'f14',
  'f15',
  'f16',
  'f17',
  'f18',
  'f19',
  'f20',
  'f21',
  'f22',
  'f23',
  'f24',
  'execute',
  'help',
  'menu',
  'select',
  'stop',
  'again',
  'undo',
  'cut',
  'copy',
  'paste',
  'find',
  'mute',
  'volumeup',
  'volumedown',
  'alterase',
  'sysreq',
  'cancel',
  'clear',
  'prior',
  'return2',
  'separator',
  'out',
  'oper',
  'clearagain',
  'thsousandsseparator',
  'decimalseparator',
  'currencyunit',
  'currencysubunit',
  'lctrl',
  'lshift',
  'lalt',
  'lgui',
  'rctrl',
  'rshift',
  'ralt',
  'rgui',
  'mode',
  'audionext',
  'audioprev',
  'audiostop',
  'audioplay',
  'audiomute',
  'mediaselect',
  'www',
  'mail',
  'calculator',
  'computer',
  'appsearch',
  'apphome',
  'appback',
  'appforward',
  'appstop',
  'apprefresh',
  'appbookmarks',
  'brightnessdown',
  'brightnessup',
  'displayswitch',
  'kbdillumtoggle',
  'kbdillumdown',
  'kbdillumup',
  'eject',
  'sleep',
};

final Set<String> _loveKeyboardScancodeConstants = <String>{
  'unknown',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
  'x',
  'y',
  'z',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '0',
  'return',
  'escape',
  'backspace',
  'tab',
  'space',
  '-',
  '=',
  '[',
  ']',
  '\\',
  'nonus#',
  ';',
  '\'',
  '`',
  ',',
  '.',
  '/',
  'capslock',
  'f1',
  'f2',
  'f3',
  'f4',
  'f5',
  'f6',
  'f7',
  'f8',
  'f9',
  'f10',
  'f11',
  'f12',
  'printscreen',
  'scrolllock',
  'pause',
  'insert',
  'home',
  'pageup',
  'delete',
  'end',
  'pagedown',
  'right',
  'left',
  'down',
  'up',
  'numlock',
  'kp/',
  'kp*',
  'kp-',
  'kp+',
  'kpenter',
  'kp1',
  'kp2',
  'kp3',
  'kp4',
  'kp5',
  'kp6',
  'kp7',
  'kp8',
  'kp9',
  'kp0',
  'kp.',
  'nonusbackslash',
  'application',
  'power',
  'kp=',
  'f13',
  'f14',
  'f15',
  'f16',
  'f17',
  'f18',
  'f19',
  'f20',
  'f21',
  'f22',
  'f23',
  'f24',
  'execute',
  'help',
  'menu',
  'select',
  'stop',
  'again',
  'undo',
  'cut',
  'copy',
  'paste',
  'find',
  'mute',
  'volumeup',
  'volumedown',
  'kp,',
  'kp=400',
  'international1',
  'international2',
  'international3',
  'international4',
  'international5',
  'international6',
  'international7',
  'international8',
  'international9',
  'lang1',
  'lang2',
  'lang3',
  'lang4',
  'lang5',
  'lang6',
  'lang7',
  'lang8',
  'lang9',
  'alterase',
  'sysreq',
  'cancel',
  'clear',
  'prior',
  'return2',
  'separator',
  'out',
  'oper',
  'clearagain',
  'crsel',
  'exsel',
  'kp00',
  'kp000',
  'thsousandsseparator',
  'decimalseparator',
  'currencyunit',
  'currencysubunit',
  'kp(',
  'kp)',
  'kp{',
  'kp}',
  'kptab',
  'kpbackspace',
  'kpa',
  'kpb',
  'kpc',
  'kpd',
  'kpe',
  'kpf',
  'kpxor',
  'kpower',
  'kp%',
  'kp<',
  'kp>',
  'kp&',
  'kp&&',
  'kp|',
  'kp||',
  'kp:',
  'kp#',
  'kp ',
  'kp@',
  'kp!',
  'kpmemstore',
  'kpmemrecall',
  'kpmemclear',
  'kpmem+',
  'kpmem-',
  'kpmem*',
  'kpmem/',
  'kp+-',
  'kpclear',
  'kpclearentry',
  'kpbinary',
  'kpoctal',
  'kpdecimal',
  'kphex',
  'lctrl',
  'lshift',
  'lalt',
  'lgui',
  'rctrl',
  'rshift',
  'ralt',
  'rgui',
  'mode',
  'audionext',
  'audioprev',
  'audiostop',
  'audioplay',
  'audiomute',
  'mediaselect',
  'www',
  'mail',
  'calculator',
  'computer',
  'acsearch',
  'achome',
  'acback',
  'acforward',
  'acstop',
  'acrefresh',
  'acbookmarks',
  'brightnessdown',
  'brightnessup',
  'displayswitch',
  'kbdillumtoggle',
  'kbdillumdown',
  'kbdillumup',
  'eject',
  'sleep',
  'app1',
  'app2',
};
