part of '../love_runtime.dart';

/// Describes the screen-space area used for on-screen text input.
class LoveTextInputArea {
  /// Creates a text input area rectangle.
  const LoveTextInputArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// The left edge of the text input area.
  final double x;

  /// The top edge of the text input area.
  final double y;

  /// The width of the text input area.
  final double width;

  /// The height of the text input area.
  final double height;
}

/// Represents either a system cursor type or an image-backed cursor.
class LoveMouseCursor {
  /// Creates a system cursor with the host-provided [type].
  LoveMouseCursor.system(String type)
    : systemType = type,
      imageData = null,
      source = null,
      hotspotX = 0,
      hotspotY = 0;

  /// Creates an image cursor with optional pixel data and hotspot metadata.
  LoveMouseCursor.image({
    this.imageData,
    this.source,
    this.hotspotX = 0,
    this.hotspotY = 0,
  }) : systemType = null;

  /// The system cursor type when this cursor is host-defined.
  final String? systemType;

  /// The image data backing this cursor when it is custom.
  final LoveImageData? imageData;

  /// The source path or identifier for the cursor image, when known.
  final String? source;

  /// The hotspot x offset in cursor pixels.
  final int hotspotX;

  /// The hotspot y offset in cursor pixels.
  final int hotspotY;

  /// Whether this cursor references a host system cursor.
  bool get isSystemCursor => systemType != null;

  /// Returns LOVE's cursor type string for this cursor.
  String getType() => systemType ?? 'image';
}

/// Tracks keyboard state, scancode mappings, and text-input settings.
class LoveKeyboardState extends ChangeNotifier {
  /// Creates keyboard state with optional repeat and text-input defaults.
  LoveKeyboardState({
    this.keyRepeat = false,
    this.textInputEnabled = true,
    this.screenKeyboardSupported = false,
  });

  /// Whether key repeat is enabled.
  bool keyRepeat;

  /// Whether text input is currently enabled.
  bool textInputEnabled;

  /// Whether the host reports support for an on-screen keyboard.
  bool screenKeyboardSupported;

  /// The active screen-space text input area, when one is provided.
  LoveTextInputArea? textInputArea;

  /// The currently pressed scancodes.
  final Set<String> _pressedScancodes = <String>{};

  /// The pressed scancodes as an unmodifiable view.
  Set<String> get pressedScancodes =>
      UnmodifiableSetView<String>(_pressedScancodes);

  /// Returns whether any key in [keys] is currently pressed.
  bool isDown(Iterable<String> keys) {
    for (final key in keys) {
      if (_pressedScancodes.contains(getScancodeFromKey(key))) {
        return true;
      }
    }

    return false;
  }

  /// Returns whether any scancode in [scancodes] is currently pressed.
  bool isScancodeDown(Iterable<String> scancodes) {
    for (final scancode in scancodes) {
      if (_pressedScancodes.contains(scancode)) {
        return true;
      }
    }

    return false;
  }

  /// Returns LOVE's key constant for [scancode].
  String getKeyFromScancode(String scancode) {
    return _loveKeyboardScancodeToKeyOverrides[scancode] ??
        (_loveKeyboardKeyConstants.contains(scancode) ? scancode : 'unknown');
  }

  /// Returns LOVE's scancode constant for [key].
  String getScancodeFromKey(String key) {
    return _loveKeyboardKeyToScancodeOverrides[key] ??
        (_loveKeyboardScancodeConstants.contains(key) ? key : 'unknown');
  }

  /// Enables or disables text input and optionally updates the input [area].
  void setTextInput(bool enable, {LoveTextInputArea? area}) {
    final nextArea = area ?? textInputArea;
    if (textInputEnabled == enable && textInputArea == nextArea) {
      return;
    }

    textInputEnabled = enable;
    if (area != null) {
      textInputArea = area;
    }
    notifyListeners();
  }

  /// Marks [key] as pressed or released.
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

  /// Marks [scancode] as pressed or released.
  void setScancodeDown(String scancode, {required bool down}) {
    if (down) {
      _pressedScancodes.add(scancode);
    } else {
      _pressedScancodes.remove(scancode);
    }
  }
}

/// Tracks mouse position, buttons, cursor state, and relative-mode flags.
class LoveMouseState extends ChangeNotifier {
  /// Creates mouse state with optional initial position and visibility.
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

  /// The current x position in LOVE coordinates.
  double _x;

  /// The current y position in LOVE coordinates.
  double _y;

  /// Whether the host supports visible cursor customization.
  bool cursorSupported;

  /// Whether the mouse is currently grabbed by the window.
  bool grabbed;

  /// Whether relative mouse mode is currently enabled.
  bool relativeMode;

  /// Whether the cursor is logically visible when relative mode is off.
  bool _visible;

  /// The currently selected cursor, if one is active.
  LoveMouseCursor? _cursor;

  /// Whether the last position update came from programmatic movement.
  bool _programmaticPositionActive = false;

  /// The currently pressed mouse buttons.
  final Set<int> _buttonsDown = <int>{};

  /// Cached host system cursors keyed by LOVE cursor type.
  final Map<String, LoveMouseCursor> _systemCursorCache =
      <String, LoveMouseCursor>{};

  /// The current x position in LOVE coordinates.
  double get x => _x;

  /// The current y position in LOVE coordinates.
  double get y => _y;

  /// Whether the cursor is currently visible to the user.
  bool get visible => _visible && !relativeMode;

  /// The currently active cursor, if any.
  LoveMouseCursor? get cursor => _cursor;

  /// Whether the current position was set programmatically.
  bool get programmaticPositionActive => _programmaticPositionActive;

  /// The currently pressed mouse buttons as an unmodifiable view.
  Set<int> get buttonsDown => UnmodifiableSetView<int>(_buttonsDown);

  /// Updates the x position and tracks whether it came from the system.
  void setX(double x, {bool fromSystemEvent = false}) {
    final nextX = x.floorToDouble();
    final nextProgrammaticPositionActive = !fromSystemEvent;
    if (_x == nextX &&
        _programmaticPositionActive == nextProgrammaticPositionActive) {
      return;
    }

    _x = nextX;
    _programmaticPositionActive = nextProgrammaticPositionActive;
    notifyListeners();
  }

  /// Updates the y position and tracks whether it came from the system.
  void setY(double y, {bool fromSystemEvent = false}) {
    final nextY = y.floorToDouble();
    final nextProgrammaticPositionActive = !fromSystemEvent;
    if (_y == nextY &&
        _programmaticPositionActive == nextProgrammaticPositionActive) {
      return;
    }

    _y = nextY;
    _programmaticPositionActive = nextProgrammaticPositionActive;
    notifyListeners();
  }

  /// Updates both mouse coordinates at once.
  void setPosition(double x, double y, {bool fromSystemEvent = false}) {
    final nextX = x.floorToDouble();
    final nextY = y.floorToDouble();
    final nextProgrammaticPositionActive = !fromSystemEvent;
    if (_x == nextX &&
        _y == nextY &&
        _programmaticPositionActive == nextProgrammaticPositionActive) {
      return;
    }

    _x = nextX;
    _y = nextY;
    _programmaticPositionActive = nextProgrammaticPositionActive;
    notifyListeners();
  }

  /// Returns whether any button in [buttons] is currently pressed.
  bool isDown(Iterable<int> buttons) {
    for (final button in buttons) {
      if (_buttonsDown.contains(button)) {
        return true;
      }
    }

    return false;
  }

  /// Marks [button] as pressed or released.
  void setButtonDown(int button, {required bool down}) {
    if (down) {
      _buttonsDown.add(button);
    } else {
      _buttonsDown.remove(button);
    }
  }

  /// Updates whether the mouse cursor should be visible.
  void setVisible(bool visible) {
    if (_visible == visible) {
      return;
    }

    _visible = visible;
    notifyListeners();
  }

  /// Enables or disables relative mouse mode.
  bool setRelativeMode(bool enabled) {
    if (relativeMode == enabled) {
      return true;
    }

    relativeMode = enabled;
    notifyListeners();
    return true;
  }

  /// Sets the active cursor, or clears it when omitted.
  void setCursor([LoveMouseCursor? cursor]) {
    if (_cursor == cursor) {
      return;
    }

    _cursor = cursor;
    notifyListeners();
  }

  /// Returns a cached system cursor for [type].
  LoveMouseCursor getSystemCursor(String type) {
    return _systemCursorCache.putIfAbsent(
      type,
      () => LoveMouseCursor.system(type),
    );
  }

  /// Creates a new custom image cursor.
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

/// Returns whether [key] is a recognized LOVE key constant.
bool loveIsValidKeyConstant(String key) =>
    _loveKeyboardKeyConstants.contains(key);

/// Returns whether [scancode] is a recognized LOVE scancode constant.
bool loveIsValidScancode(String scancode) =>
    _loveKeyboardScancodeConstants.contains(scancode);

/// Returns whether [cursorType] is a recognized LOVE system cursor type.
bool loveIsValidCursorType(String cursorType) =>
    _loveMouseSystemCursorTypes.contains(cursorType);

/// Overrides that map LOVE key constants to distinct scancode constants.
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

/// Reverse overrides that map distinct scancodes back to LOVE key constants.
final Map<String, String> _loveKeyboardScancodeToKeyOverrides =
    <String, String>{
      for (final entry in _loveKeyboardKeyToScancodeOverrides.entries)
        if (!_loveKeyboardKeyConstants.contains(entry.value))
          entry.value: entry.key,
    };

/// The system cursor types supported by the LOVE mouse API.
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

/// The normalized LOVE keyboard key constants accepted by this runtime.
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

/// The normalized LOVE keyboard scancode constants accepted by this runtime.
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
