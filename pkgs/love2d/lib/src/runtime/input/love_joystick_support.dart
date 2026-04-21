part of '../love_runtime.dart';

const String _loveJoystickDefaultGuid = '00000000000000000000000000000000';

const List<String> _loveJoystickGamepadAxisConstants = <String>[
  'leftx',
  'lefty',
  'rightx',
  'righty',
  'triggerleft',
  'triggerright',
];

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

const List<String> _loveJoystickInputTypeConstants = <String>[
  'axis',
  'button',
  'hat',
];

const List<String> _loveJoystickGamepadInputOrder = <String>[
  ..._loveJoystickGamepadAxisConstants,
  ..._loveJoystickGamepadButtonConstants,
];

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

final Map<int, String> _loveJoystickHatFromSdlValue = <int, String>{
  for (final entry in _loveJoystickHatToSdlValue.entries)
    entry.value: entry.key,
};

bool loveIsValidGamepadAxis(String axis) =>
    _loveJoystickGamepadAxisConstants.contains(axis);

bool loveIsValidGamepadButton(String button) =>
    _loveJoystickGamepadButtonConstants.contains(button);

bool loveIsValidGamepadInput(String input) =>
    loveIsValidGamepadAxis(input) || loveIsValidGamepadButton(input);

bool loveIsValidJoystickHat(String direction) =>
    _loveJoystickHatConstants.contains(direction);

bool loveIsValidJoystickInputType(String inputType) =>
    _loveJoystickInputTypeConstants.contains(inputType);

double _loveClampJoystickAxis(double value) {
  if (!value.isFinite) {
    return value;
  }

  return value.clamp(-1.0, 1.0).toDouble();
}

double _loveClampJoystickVibration(double value) {
  if (!value.isFinite) {
    return value;
  }

  return value.clamp(0.0, 1.0).toDouble();
}

class LoveJoystickInputBinding {
  const LoveJoystickInputBinding({
    required this.type,
    required this.inputIndex,
    this.hatDirection,
  });

  final String type;
  final int inputIndex;
  final String? hatDirection;

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

  @override
  bool operator ==(Object other) {
    return other is LoveJoystickInputBinding &&
        other.type == type &&
        other.inputIndex == inputIndex &&
        other.hatDirection == hatDirection;
  }

  @override
  int get hashCode => Object.hash(type, inputIndex, hatDirection);
}

class LoveJoystickGamepadMapping {
  LoveJoystickGamepadMapping({
    required this.guid,
    this.name = 'Controller',
    Map<String, String>? rawBindings,
    Map<String, String>? extras,
    this.platform,
  }) : _rawBindings = <String, String>{...?rawBindings},
       _extras = <String, String>{...?extras};

  final String guid;
  String name;
  String? platform;
  final Map<String, String> _rawBindings;
  final Map<String, String> _extras;

  Map<String, String> get rawBindings =>
      UnmodifiableMapView<String, String>(_rawBindings);

  Map<String, String> get extras =>
      UnmodifiableMapView<String, String>(_extras);

  LoveJoystickInputBinding? getBinding(String input) {
    final token = _rawBindings[input];
    return token == null ? null : LoveJoystickInputBinding.fromSdlToken(token);
  }

  void setBinding(String input, LoveJoystickInputBinding binding) {
    _rawBindings[input] = binding.toSdlToken();
  }

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

class LoveJoystickDevice {
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

  final int id;
  String name;
  bool connected;
  bool gamepad;
  int? instanceId;
  String guid;
  int vendorId;
  int productId;
  int productVersion;
  bool vibrationSupported;
  final List<double> _axes;
  int _buttonCount;
  final Set<int> _buttonsDown;
  final List<String> _hats;
  final Map<String, double> _gamepadAxes;
  final Set<String> _gamepadButtons;
  double _vibrationLeft;
  double _vibrationRight;
  LoveJoystickManager? _manager;

  List<double> get axes =>
      List<double>.unmodifiable(connected ? _axes : const []);

  int get buttonCount => connected ? _buttonCount : 0;

  Set<int> get buttonsDown => UnmodifiableSetView<int>(_buttonsDown);

  List<String> get hats =>
      List<String>.unmodifiable(connected ? _hats : const []);

  Map<String, double> get gamepadAxes =>
      UnmodifiableMapView<String, double>(connected ? _gamepadAxes : const {});

  Set<String> get gamepadButtons =>
      UnmodifiableSetView<String>(connected ? _gamepadButtons : const {});

  double get vibrationLeft => _vibrationLeft;

  double get vibrationRight => _vibrationRight;

  LoveJoystickGamepadMapping? get gamepadMapping =>
      _manager?.mappingForGuid(guid);

  bool get recognizedAsGamepad =>
      gamepad || (_manager?.hasGamepadMapping(guid) ?? false);

  bool get isConnected => connected;

  void setAxes(Iterable<double> axes) {
    _axes
      ..clear()
      ..addAll(axes.map(_loveClampJoystickAxis));
  }

  void setAxis(int axis, double value) {
    if (axis < 1) {
      return;
    }

    while (_axes.length < axis) {
      _axes.add(0.0);
    }
    _axes[axis - 1] = _loveClampJoystickAxis(value);
  }

  double getAxis(int axis) {
    if (!connected || axis < 1 || axis > _axes.length) {
      return 0.0;
    }

    return _axes[axis - 1];
  }

  void setButtonCount(int count) {
    _buttonCount = math.max(0, count);
  }

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

  void setHat(int hat, String direction) {
    if (hat < 1 || !loveIsValidJoystickHat(direction)) {
      return;
    }

    setHatCount(hat);
    _hats[hat - 1] = direction;
  }

  String getHat(int hat) {
    if (!connected || hat < 1 || hat > _hats.length) {
      return '';
    }

    return _hats[hat - 1];
  }

  void setGamepadAxis(String axis, double value) {
    if (!loveIsValidGamepadAxis(axis)) {
      return;
    }

    _gamepadAxes[axis] = _loveClampJoystickAxis(value);
  }

  double getGamepadAxis(String axis) {
    if (!connected || !recognizedAsGamepad || !loveIsValidGamepadAxis(axis)) {
      return 0.0;
    }

    return _gamepadAxes[axis] ?? 0.0;
  }

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

  bool isGamepadDown(Iterable<String> buttons) {
    if (!connected || !recognizedAsGamepad) {
      return false;
    }

    return buttons.any(_gamepadButtons.contains);
  }

  LoveJoystickInputBinding? getGamepadMapping(String input) {
    if (!recognizedAsGamepad || !loveIsValidGamepadInput(input)) {
      return null;
    }

    return gamepadMapping?.getBinding(input);
  }

  String? getGamepadMappingString() {
    if (!recognizedAsGamepad) {
      return null;
    }

    return _manager?.getGamepadMappingString(guid);
  }

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

  bool stopVibration() => setVibration(left: 0.0, right: 0.0);
}

class LoveJoystickManager {
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

  String? _platformName;
  final List<LoveJoystickDevice> _devices;
  final Map<String, LoveJoystickGamepadMapping> _gamepadMappings =
      <String, LoveJoystickGamepadMapping>{};
  final Set<String> _recentGamepadGuids = <String>{};

  String? get platformName => _platformName;

  set platformName(String? value) {
    _platformName = value == null || value.isEmpty ? null : value;
  }

  List<LoveJoystickDevice> get devices =>
      List<LoveJoystickDevice>.unmodifiable(_devices);

  List<LoveJoystickDevice> get connectedDevices =>
      _devices.where((device) => device.connected).toList(growable: false);

  int get joystickCount => connectedDevices.length;

  Map<String, LoveJoystickGamepadMapping> get gamepadMappings =>
      UnmodifiableMapView<String, LoveJoystickGamepadMapping>(_gamepadMappings);

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

  void addDevice(LoveJoystickDevice device) {
    device._manager = this;
    _devices.add(device);
  }

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

  bool hasGamepadMapping(String guid) => _gamepadMappings.containsKey(guid);

  LoveJoystickGamepadMapping? mappingForGuid(String guid) =>
      _gamepadMappings[guid];

  String? getGamepadMappingString(String guid) {
    final mapping = _gamepadMappings[guid];
    if (mapping == null) {
      return null;
    }

    _recentGamepadGuids.add(guid);
    return mapping.toMappingString(defaultPlatform: _platformName);
  }

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

  String _nameForGuid(String guid) {
    for (final device in _devices) {
      if (device.guid == guid) {
        return device.name;
      }
    }

    return 'Controller';
  }
}
