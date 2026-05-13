part of '../love_runtime.dart';

/// The fallback GUID used when a joystick backend does not provide one.
const String _loveJoystickDefaultGuid = '00000000000000000000000000000000';

/// The normalized LOVE gamepad axis names.
const List<String> _loveJoystickGamepadAxisConstants = <String>[
  'leftx',
  'lefty',
  'rightx',
  'righty',
  'triggerleft',
  'triggerright',
];

/// The normalized LOVE gamepad button names.
const List<String> _loveJoystickGamepadButtonConstants = <String>[
  'a',
  'b',
  'x',
  'y',
  'back',
  'guide',
  'start',
  'leftstick',
  'rightstick',
  'leftshoulder',
  'rightshoulder',
  'dpup',
  'dpdown',
  'dpleft',
  'dpright',
];

/// The normalized LOVE hat-direction constants.
const List<String> _loveJoystickHatConstants = <String>[
  'c',
  'd',
  'l',
  'ld',
  'lu',
  'r',
  'rd',
  'ru',
  'u',
];

/// The supported joystick input binding types.
const List<String> _loveJoystickInputTypeConstants = <String>[
  'axis',
  'button',
  'hat',
];

/// The preferred serialization order for gamepad mapping inputs.
const List<String> _loveJoystickGamepadInputOrder = <String>[
  ..._loveJoystickGamepadAxisConstants,
  ..._loveJoystickGamepadButtonConstants,
];

/// Maps LOVE hat-direction constants to SDL hat bitfield values.
const Map<String, int> _loveJoystickHatToSdlValue = <String, int>{
  'c': 0,
  'u': 1,
  'r': 2,
  'ru': 3,
  'd': 4,
  'rd': 6,
  'l': 8,
  'lu': 9,
  'ld': 12,
};

/// Maps SDL hat bitfield values back to LOVE hat-direction constants.
final Map<int, String> _loveJoystickHatFromSdlValue = <int, String>{
  for (final entry in _loveJoystickHatToSdlValue.entries)
    entry.value: entry.key,
};

/// Returns whether [axis] is a valid LOVE gamepad axis constant.
bool loveIsValidGamepadAxis(String axis) =>
    _loveJoystickGamepadAxisConstants.contains(axis);

/// Returns whether [button] is a valid LOVE gamepad button constant.
bool loveIsValidGamepadButton(String button) =>
    _loveJoystickGamepadButtonConstants.contains(button);

/// Returns whether [input] is a valid LOVE gamepad input constant.
bool loveIsValidGamepadInput(String input) =>
    loveIsValidGamepadAxis(input) || loveIsValidGamepadButton(input);

/// Returns whether [direction] is a valid LOVE hat-direction constant.
bool loveIsValidJoystickHat(String direction) =>
    _loveJoystickHatConstants.contains(direction);

/// Returns whether [inputType] is a valid joystick input binding type.
bool loveIsValidJoystickInputType(String inputType) =>
    _loveJoystickInputTypeConstants.contains(inputType);

/// Clamps joystick axis values to LOVE's normalized range.
double _loveClampJoystickAxis(double value) {
  if (!value.isFinite) {
    return value;
  }

  return value.clamp(-1.0, 1.0).toDouble();
}

/// Clamps joystick vibration values to LOVE's normalized range.
double _loveClampJoystickVibration(double value) {
  if (!value.isFinite) {
    return value;
  }

  return value.clamp(0.0, 1.0).toDouble();
}

/// Describes one SDL-style gamepad mapping target.
class LoveJoystickInputBinding {
  /// Creates a joystick input binding for one axis, button, or hat direction.
  const LoveJoystickInputBinding({
    required this.type,
    required this.inputIndex,
    this.hatDirection,
  });

  /// The input type, such as `axis`, `button`, or `hat`.
  final String type;

  /// The 1-based input index.
  final int inputIndex;

  /// The hat direction used when [type] is `hat`.
  final String? hatDirection;

  /// Returns this binding encoded as an SDL mapping token.
  String toSdlToken() {
    final zeroBasedIndex = inputIndex - 1;
    return switch (type) {
      'axis' when zeroBasedIndex >= 0 => 'a$zeroBasedIndex',
      'button' when zeroBasedIndex >= 0 => 'b$zeroBasedIndex',
      'hat' when zeroBasedIndex >= 0 && hatDirection != null =>
        'h$zeroBasedIndex.${_loveJoystickHatToSdlValue[hatDirection] ?? 0}',
      _ => throw StateError('Invalid joystick binding: $type#$inputIndex'),
    };
  }

  /// Parses an SDL mapping token into a LOVE input binding.
  static LoveJoystickInputBinding? fromSdlToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.replaceFirst(RegExp(r'^[+\-~]+'), '');
    if (normalized.length < 2) {
      return null;
    }

    if (normalized.startsWith('a')) {
      final index = int.tryParse(normalized.substring(1));
      if (index == null || index < 0) {
        return null;
      }
      return LoveJoystickInputBinding(type: 'axis', inputIndex: index + 1);
    }

    if (normalized.startsWith('b')) {
      final index = int.tryParse(normalized.substring(1));
      if (index == null || index < 0) {
        return null;
      }
      return LoveJoystickInputBinding(type: 'button', inputIndex: index + 1);
    }

    if (normalized.startsWith('h')) {
      final dot = normalized.indexOf('.');
      if (dot <= 1 || dot >= normalized.length - 1) {
        return null;
      }

      final hatIndex = int.tryParse(normalized.substring(1, dot));
      final hatValue = int.tryParse(normalized.substring(dot + 1));
      final hatDirection = hatValue == null
          ? null
          : _loveJoystickHatFromSdlValue[hatValue];
      if (hatIndex == null ||
          hatIndex < 0 ||
          hatDirection == null ||
          !loveIsValidJoystickHat(hatDirection)) {
        return null;
      }

      return LoveJoystickInputBinding(
        type: 'hat',
        inputIndex: hatIndex + 1,
        hatDirection: hatDirection,
      );
    }

    return null;
  }

  /// Returns whether [other] describes the same joystick binding.
  @override
  bool operator ==(Object other) {
    return other is LoveJoystickInputBinding &&
        other.type == type &&
        other.inputIndex == inputIndex &&
        other.hatDirection == hatDirection;
  }

  /// The stable hash for this binding.
  @override
  int get hashCode => Object.hash(type, inputIndex, hatDirection);
}

/// Stores a parsed SDL gamepad mapping in LOVE-friendly form.
class LoveJoystickGamepadMapping {
  /// Creates a gamepad mapping with optional raw binding and metadata maps.
  LoveJoystickGamepadMapping({
    required this.guid,
    this.name = 'Controller',
    Map<String, String>? rawBindings,
    Map<String, String>? extras,
    this.platform,
  }) : _rawBindings = <String, String>{...?rawBindings},
       _extras = <String, String>{...?extras};

  /// The 32-character SDL gamepad GUID.
  final String guid;

  /// The human-readable mapping name.
  String name;

  /// The platform name this mapping applies to, when specified.
  String? platform;

  /// The raw SDL binding tokens keyed by LOVE input name.
  final Map<String, String> _rawBindings;

  /// Any nonstandard mapping entries preserved during parsing.
  final Map<String, String> _extras;

  /// The raw bindings as an unmodifiable view.
  Map<String, String> get rawBindings =>
      UnmodifiableMapView<String, String>(_rawBindings);

  /// The nonstandard mapping entries as an unmodifiable view.
  Map<String, String> get extras =>
      UnmodifiableMapView<String, String>(_extras);

  /// Returns the parsed binding for [input], if one exists.
  LoveJoystickInputBinding? getBinding(String input) {
    final token = _rawBindings[input];
    return token == null ? null : LoveJoystickInputBinding.fromSdlToken(token);
  }

  /// Stores [binding] as the raw mapping token for [input].
  void setBinding(String input, LoveJoystickInputBinding binding) {
    _rawBindings[input] = binding.toSdlToken();
  }

  /// Serializes this mapping to an SDL-compatible mapping string.
  String toMappingString({String? defaultPlatform}) {
    final parts = <String>[guid, name];

    for (final input in _loveJoystickGamepadInputOrder) {
      final token = _rawBindings[input];
      if (token == null || token.isEmpty) {
        continue;
      }
      parts.add('$input:$token');
    }

    final extraKeys =
        _rawBindings.keys
            .where((key) => !_loveJoystickGamepadInputOrder.contains(key))
            .toList()
          ..sort();
    for (final key in extraKeys) {
      final token = _rawBindings[key];
      if (token != null && token.isNotEmpty) {
        parts.add('$key:$token');
      }
    }

    final extras = _extras.keys.toList()..sort();
    for (final key in extras) {
      final value = _extras[key];
      if (value != null && value.isNotEmpty) {
        parts.add('$key:$value');
      }
    }

    final resolvedPlatform = platform ?? defaultPlatform;
    if (resolvedPlatform != null && resolvedPlatform.isNotEmpty) {
      parts.add('platform:$resolvedPlatform');
    }

    return '${parts.join(',')},';
  }

  /// Parses one SDL gamepad mapping line.
  static LoveJoystickGamepadMapping? tryParse(String mappingString) {
    final trimmed = mappingString.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      return null;
    }

    final parts = trimmed.split(',');
    if (parts.length < 2) {
      return null;
    }

    final guid = parts[0].trim();
    if (guid.length != 32) {
      return null;
    }

    final mapping = LoveJoystickGamepadMapping(
      guid: guid,
      name: parts[1].trim().isEmpty ? 'Controller' : parts[1].trim(),
    );

    for (final rawEntry in parts.skip(2)) {
      final entry = rawEntry.trim();
      if (entry.isEmpty) {
        continue;
      }

      final separator = entry.indexOf(':');
      if (separator <= 0 || separator >= entry.length - 1) {
        return null;
      }

      final key = entry.substring(0, separator).trim();
      final value = entry.substring(separator + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        return null;
      }

      if (key == 'platform') {
        mapping.platform = value;
      } else if (loveIsValidGamepadInput(key)) {
        mapping._rawBindings[key] = value;
      } else {
        mapping._extras[key] = value;
      }
    }

    return mapping;
  }
}

/// Represents one joystick or gamepad device tracked by the runtime.
class LoveJoystickDevice {
  /// Creates a joystick device with optional axes, buttons, hats, and mapping state.
  LoveJoystickDevice({
    required this.id,
    this.name = 'Joystick',
    this.connected = true,
    this.gamepad = true,
    int? instanceId,
    this.guid = _loveJoystickDefaultGuid,
    this.vendorId = 0,
    this.productId = 0,
    this.productVersion = 0,
    Iterable<double>? axes,
    int buttonCount = 0,
    Set<int>? buttonsDown,
    Iterable<String>? hats,
    Map<String, double>? gamepadAxes,
    Set<String>? gamepadButtons,
    this.vibrationSupported = false,
    double vibrationLeft = 0.0,
    double vibrationRight = 0.0,
  }) : instanceId = instanceId ?? id,
       _axes = <double>[...?axes].map(_loveClampJoystickAxis).toList(),
       _buttonCount = math.max(
         0,
         math.max(
           buttonCount,
           buttonsDown == null || buttonsDown.isEmpty
               ? 0
               : buttonsDown.reduce(math.max),
         ),
       ),
       _buttonsDown = <int>{...?buttonsDown},
       _hats = <String>[...?hats],
       _gamepadAxes = <String, double>{
         if (gamepadAxes != null)
           for (final entry in gamepadAxes.entries)
             entry.key: _loveClampJoystickAxis(entry.value),
       },
       _gamepadButtons = <String>{...?gamepadButtons},
       _vibrationLeft = _loveClampJoystickVibration(vibrationLeft),
       _vibrationRight = _loveClampJoystickVibration(vibrationRight);

  /// The stable LOVE joystick id.
  final int id;

  /// The device display name.
  String name;

  /// Whether the device is currently connected.
  bool connected;

  /// Whether the host recognized this device as a gamepad.
  bool gamepad;

  /// The backend-specific instance id, when available.
  int? instanceId;

  /// The SDL-style device GUID.
  String guid;

  /// The USB vendor id, when available.
  int vendorId;

  /// The USB product id, when available.
  int productId;

  /// The hardware product version, when available.
  int productVersion;

  /// Whether the device supports vibration.
  bool vibrationSupported;

  /// The current raw joystick axes.
  final List<double> _axes;

  /// The number of digital buttons the device exposes.
  int _buttonCount;

  /// The currently pressed button indices.
  final Set<int> _buttonsDown;

  /// The current hat directions.
  final List<String> _hats;

  /// The normalized gamepad axis values.
  final Map<String, double> _gamepadAxes;

  /// The currently pressed gamepad buttons.
  final Set<String> _gamepadButtons;

  /// The current left vibration intensity.
  double _vibrationLeft;

  /// The current right vibration intensity.
  double _vibrationRight;

  /// The manager tracking this device, when attached.
  LoveJoystickManager? _manager;

  /// The current joystick axes as an unmodifiable list.
  List<double> get axes =>
      List<double>.unmodifiable(connected ? _axes : const []);

  /// The number of available digital buttons.
  int get buttonCount => connected ? _buttonCount : 0;

  /// The currently pressed buttons as an unmodifiable set.
  Set<int> get buttonsDown => UnmodifiableSetView<int>(_buttonsDown);

  /// The current hat directions as an unmodifiable list.
  List<String> get hats =>
      List<String>.unmodifiable(connected ? _hats : const []);

  /// The current gamepad axes as an unmodifiable map.
  Map<String, double> get gamepadAxes =>
      UnmodifiableMapView<String, double>(connected ? _gamepadAxes : const {});

  /// The currently pressed gamepad buttons as an unmodifiable set.
  Set<String> get gamepadButtons =>
      UnmodifiableSetView<String>(connected ? _gamepadButtons : const {});

  /// The current left vibration intensity.
  double get vibrationLeft => _vibrationLeft;

  /// The current right vibration intensity.
  double get vibrationRight => _vibrationRight;

  /// The active gamepad mapping associated with this device's GUID.
  LoveJoystickGamepadMapping? get gamepadMapping =>
      _manager?.mappingForGuid(guid);

  /// Whether this device should be treated as a gamepad.
  bool get recognizedAsGamepad =>
      gamepad || (_manager?.hasGamepadMapping(guid) ?? false);

  /// Whether this device is currently connected.
  bool get isConnected => connected;

  /// Replaces the full axis list with [axes].
  void setAxes(Iterable<double> axes) {
    _axes
      ..clear()
      ..addAll(axes.map(_loveClampJoystickAxis));
  }

  /// Sets one 1-based joystick axis value.
  void setAxis(int axis, double value) {
    if (axis < 1) {
      return;
    }

    while (_axes.length < axis) {
      _axes.add(0.0);
    }
    _axes[axis - 1] = _loveClampJoystickAxis(value);
  }

  /// Returns the current value of a 1-based joystick axis.
  double getAxis(int axis) {
    if (!connected || axis < 1 || axis > _axes.length) {
      return 0.0;
    }

    return _axes[axis - 1];
  }

  /// Sets the number of digital buttons exposed by the device.
  void setButtonCount(int count) {
    _buttonCount = math.max(0, count);
  }

  /// Marks a 1-based joystick button as pressed or released.
  void setButtonDown(int button, {required bool down}) {
    if (button < 1) {
      return;
    }

    _buttonCount = math.max(_buttonCount, button);
    if (down) {
      _buttonsDown.add(button);
    } else {
      _buttonsDown.remove(button);
    }
  }

  /// Returns whether any 1-based button in [buttons] is currently pressed.
  bool isDown(Iterable<int> buttons) {
    if (!connected) {
      return false;
    }

    for (final button in buttons) {
      if (button >= 1 &&
          button <= _buttonCount &&
          _buttonsDown.contains(button)) {
        return true;
      }
    }

    return false;
  }

  /// Resizes the hat list to [count], filling new entries with center.
  void setHatCount(int count) {
    final normalizedCount = math.max(0, count);
    if (normalizedCount < _hats.length) {
      _hats.removeRange(normalizedCount, _hats.length);
      return;
    }

    while (_hats.length < normalizedCount) {
      _hats.add('c');
    }
  }

  /// Sets a 1-based hat direction.
  void setHat(int hat, String direction) {
    if (hat < 1 || !loveIsValidJoystickHat(direction)) {
      return;
    }

    setHatCount(hat);
    _hats[hat - 1] = direction;
  }

  /// Returns the direction of a 1-based hat.
  String getHat(int hat) {
    if (!connected || hat < 1 || hat > _hats.length) {
      return '';
    }

    return _hats[hat - 1];
  }

  /// Sets the normalized value of a named gamepad axis.
  void setGamepadAxis(String axis, double value) {
    if (!loveIsValidGamepadAxis(axis)) {
      return;
    }

    _gamepadAxes[axis] = _loveClampJoystickAxis(value);
  }

  /// Returns the normalized value of a named gamepad axis.
  double getGamepadAxis(String axis) {
    if (!connected || !recognizedAsGamepad || !loveIsValidGamepadAxis(axis)) {
      return 0.0;
    }

    return _gamepadAxes[axis] ?? 0.0;
  }

  /// Marks a named gamepad button as pressed or released.
  void setGamepadButton(String button, {required bool down}) {
    if (!loveIsValidGamepadButton(button)) {
      return;
    }

    if (down) {
      _gamepadButtons.add(button);
    } else {
      _gamepadButtons.remove(button);
    }
  }

  /// Returns whether any named gamepad button in [buttons] is pressed.
  bool isGamepadDown(Iterable<String> buttons) {
    if (!connected || !recognizedAsGamepad) {
      return false;
    }

    return buttons.any(_gamepadButtons.contains);
  }

  /// Returns the parsed gamepad mapping binding for [input], if any.
  LoveJoystickInputBinding? getGamepadMapping(String input) {
    if (!recognizedAsGamepad || !loveIsValidGamepadInput(input)) {
      return null;
    }

    return gamepadMapping?.getBinding(input);
  }

  /// Returns the serialized gamepad mapping string for this device, if any.
  String? getGamepadMappingString() {
    if (!recognizedAsGamepad) {
      return null;
    }

    return _manager?.getGamepadMappingString(guid);
  }

  /// Updates the current vibration intensities.
  bool setVibration({
    double left = 0.0,
    double? right,
    double duration = -1.0,
  }) {
    if (!vibrationSupported) {
      return false;
    }

    _vibrationLeft = _loveClampJoystickVibration(left);
    _vibrationRight = _loveClampJoystickVibration(right ?? left);
    final _ = duration;
    return true;
  }

  /// Stops all device vibration.
  bool stopVibration() => setVibration(left: 0.0, right: 0.0);
}

/// Tracks connected joystick devices and persisted gamepad mappings.
class LoveJoystickManager {
  /// Creates a joystick manager with optional devices, mappings, and platform.
  LoveJoystickManager({
    Iterable<LoveJoystickDevice>? devices,
    Iterable<LoveJoystickGamepadMapping>? mappings,
    String? platformName,
  }) : _platformName = platformName,
       _devices = <LoveJoystickDevice>[] {
    if (mappings != null) {
      for (final mapping in mappings) {
        _gamepadMappings[mapping.guid] = mapping;
      }
    }

    setDevices(devices ?? const <LoveJoystickDevice>[]);
  }

  /// The platform name used when reading and writing platform-specific mappings.
  String? _platformName;

  /// The devices currently known to the manager.
  final List<LoveJoystickDevice> _devices;

  /// The loaded gamepad mappings keyed by GUID.
  final Map<String, LoveJoystickGamepadMapping> _gamepadMappings =
      <String, LoveJoystickGamepadMapping>{};

  /// The GUIDs recently loaded or requested for serialization.
  final Set<String> _recentGamepadGuids = <String>{};

  /// The current platform name used for mapping filtering.
  String? get platformName => _platformName;

  /// Updates the current platform name used for mapping filtering.
  set platformName(String? value) {
    _platformName = value == null || value.isEmpty ? null : value;
  }

  /// All tracked devices as an unmodifiable list.
  List<LoveJoystickDevice> get devices =>
      List<LoveJoystickDevice>.unmodifiable(_devices);

  /// The currently connected devices.
  List<LoveJoystickDevice> get connectedDevices =>
      _devices.where((device) => device.connected).toList(growable: false);

  /// The number of currently connected devices.
  int get joystickCount => connectedDevices.length;

  /// The loaded gamepad mappings as an unmodifiable map.
  Map<String, LoveJoystickGamepadMapping> get gamepadMappings =>
      UnmodifiableMapView<String, LoveJoystickGamepadMapping>(_gamepadMappings);

  /// Replaces the tracked device list with [devices].
  void setDevices(Iterable<LoveJoystickDevice> devices) {
    for (final device in _devices) {
      if (device._manager == this) {
        device._manager = null;
      }
    }

    _devices
      ..clear()
      ..addAll(devices);

    for (final device in _devices) {
      device._manager = this;
    }
  }

  /// Adds [device] to the tracked device list.
  void addDevice(LoveJoystickDevice device) {
    device._manager = this;
    _devices.add(device);
  }

  /// Removes the device identified by [id].
  bool removeDevice(int id) {
    final before = _devices.length;
    _devices.removeWhere((device) {
      final matches = device.id == id;
      if (matches && device._manager == this) {
        device._manager = null;
      }
      return matches;
    });
    return _devices.length != before;
  }

  /// Returns whether a mapping exists for [guid].
  bool hasGamepadMapping(String guid) => _gamepadMappings.containsKey(guid);

  /// Returns the loaded mapping for [guid], if any.
  LoveJoystickGamepadMapping? mappingForGuid(String guid) =>
      _gamepadMappings[guid];

  /// Returns the serialized mapping string for [guid], if one exists.
  String? getGamepadMappingString(String guid) {
    final mapping = _gamepadMappings[guid];
    if (mapping == null) {
      return null;
    }

    _recentGamepadGuids.add(guid);
    return mapping.toMappingString(defaultPlatform: _platformName);
  }

  /// Adds or updates one gamepad mapping entry.
  bool setGamepadMapping(
    String guid,
    String input,
    String inputType,
    int inputIndex, {
    String? hatDirection,
  }) {
    if (guid.length != 32 ||
        !loveIsValidGamepadInput(input) ||
        !loveIsValidJoystickInputType(inputType) ||
        inputIndex < 1) {
      return false;
    }

    if (inputType == 'hat') {
      if (hatDirection == null || !loveIsValidJoystickHat(hatDirection)) {
        return false;
      }
    } else if (hatDirection != null) {
      return false;
    }

    final mapping = _gamepadMappings.putIfAbsent(
      guid,
      () => LoveJoystickGamepadMapping(guid: guid, name: _nameForGuid(guid)),
    );
    mapping.setBinding(
      input,
      LoveJoystickInputBinding(
        type: inputType,
        inputIndex: inputIndex,
        hatDirection: hatDirection,
      ),
    );
    _recentGamepadGuids.add(guid);
    return true;
  }

  /// Loads one or more SDL gamepad mappings from [mappings].
  void loadGamepadMappings(String mappings) {
    var success = false;

    for (final line in convert.LineSplitter.split(mappings)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final mapping = LoveJoystickGamepadMapping.tryParse(trimmed);
      if (mapping == null) {
        continue;
      }

      if (_platformName != null &&
          mapping.platform != null &&
          mapping.platform != _platformName) {
        success = true;
        continue;
      }

      _gamepadMappings[mapping.guid] = mapping;
      _recentGamepadGuids.add(mapping.guid);
      success = true;
    }

    if (!success && mappings.isNotEmpty) {
      throw const FormatException('Invalid gamepad mappings.');
    }
  }

  /// Serializes recently used gamepad mappings to SDL mapping lines.
  String saveGamepadMappings() {
    final buffer = StringBuffer();
    for (final guid in _recentGamepadGuids) {
      final mapping = _gamepadMappings[guid];
      if (mapping == null) {
        continue;
      }
      buffer.writeln(mapping.toMappingString(defaultPlatform: _platformName));
    }
    return buffer.toString();
  }

  /// Returns the best available device name for [guid].
  String _nameForGuid(String guid) {
    for (final device in _devices) {
      if (device.guid == guid) {
        return device.name;
      }
    }

    return 'Controller';
  }
}
