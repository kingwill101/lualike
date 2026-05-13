part of '../love_api_bindings.dart';

/// Binds `love.joystick.getGamepadMappingString`.
///
/// This returns the registered SDL-style mapping string for a joystick GUID.
LoveApiImplementation _bindJoystickGetGamepadMappingString(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.joysticks.getGamepadMappingString(
    _requireString(args, 0, 'love.joystick.getGamepadMappingString'),
  );
}

/// Binds `love.joystick.getJoystickCount`.
///
/// This reports the number of currently connected joystick devices.
LoveApiImplementation _bindJoystickGetJoystickCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.joysticks.joystickCount;
}

/// Binds `love.joystick.getJoysticks`.
///
/// LOVE returns connected devices as a 1-based Lua array of `Joystick`
/// objects.
LoveApiImplementation _bindJoystickGetJoysticks(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final table = <Object?, Object?>{};
    final devices = runtime.joysticks.connectedDevices;
    for (var index = 0; index < devices.length; index++) {
      table[index + 1] = _wrapJoystick(context, devices[index]);
    }
    return ValueClass.table(table);
  };
}

/// Binds `love.joystick.loadGamepadMappings`.
///
/// LOVE accepts either raw mapping text or a filename whose contents should be
/// parsed as mapping entries.
LoveApiImplementation _bindJoystickLoadGamepadMappings(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.joystick.loadGamepadMappings';
    final source = _requireString(args, 0, symbol);
    final interpreter = context.interpreter;
    if (interpreter == null) {
      throw StateError('No Lua runtime available for LOVE bindings');
    }

    final filesystem = LoveFilesystemState.of(interpreter);
    var mappings = source;
    final fileInfo = await filesystem.getInfo(
      source,
      filterType: LoveFilesystemNodeType.file,
    );
    if (fileInfo != null) {
      LoveFilesystemFileData? fileData;
      try {
        fileData = await filesystem.readFileDataIfExistsOrThrow(
          source,
          filename: source,
        );
      } on StateError catch (error) {
        throw LuaError(error.message);
      }
      if (fileData == null) {
        throw _missingResourceFileError(source);
      }
      mappings = utf8.decode(fileData.bytes, allowMalformed: true);
    }

    try {
      runtime.joysticks.loadGamepadMappings(mappings);
    } on FormatException catch (error) {
      throw LuaError('$symbol ${error.message}');
    }
    return null;
  };
}

/// Binds `love.joystick.saveGamepadMappings`.
///
/// This returns the current mapping database as text and optionally writes it
/// to a file when a filename is provided.
LoveApiImplementation _bindJoystickSaveGamepadMappings(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.joystick.saveGamepadMappings';
    final mappings = runtime.joysticks.saveGamepadMappings();
    final filenameValue = _rawValue(_valueAt(args, 0));
    if (filenameValue != null) {
      final filename = _requireString(args, 0, symbol);
      await _writeResourceBytesOrThrow(
        context,
        filename,
        utf8.encode(mappings),
        symbol: symbol,
      );
    }

    return mappings;
  };
}

/// Binds `love.joystick.setGamepadMapping`.
///
/// This updates one gamepad input mapping for a GUID and supports LOVE's extra
/// hat-direction argument for hat inputs.
LoveApiImplementation _bindJoystickSetGamepadMapping(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.joystick.setGamepadMapping';
    final guid = _requireString(args, 0, symbol);
    if (guid.length != 32) {
      throw LuaError('$symbol invalid joystick GUID "$guid"');
    }

    final input = _requireJoystickGamepadInput(args, 1, symbol);
    final inputType = _requireJoystickInputType(args, 2, symbol);
    final inputIndex = _requireRoundedInt(args, 3, symbol);
    if (inputIndex < 1) {
      throw LuaError('$symbol invalid joystick input index $inputIndex');
    }

    final hatDirection = inputType == 'hat'
        ? _requireJoystickHat(args, 4, symbol)
        : null;
    final success = runtime.joysticks.setGamepadMapping(
      guid,
      input,
      inputType,
      inputIndex,
      hatDirection: hatDirection,
    );
    if (!success) {
      throw LuaError('$symbol failed to set gamepad mapping');
    }

    return true;
  };
}

/// Binds `Joystick:getAxes`.
///
/// LOVE returns each axis value as a separate result rather than a table.
LoveApiImplementation _bindJoystickGetAxes(LibraryContext context) {
  return (args) {
    final axes = _requireJoystick(args, 0, 'Joystick:getAxes').axes;
    return Value.multi(<Object?>[...axes]);
  };
}

/// Binds `Joystick:getAxis`.
LoveApiImplementation _bindJoystickGetAxis(LibraryContext context) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:getAxis',
  ).getAxis(_requireRoundedInt(args, 1, 'Joystick:getAxis'));
}

/// Binds `Joystick:getAxisCount`.
LoveApiImplementation _bindJoystickGetAxisCount(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:getAxisCount').axes.length;
}

/// Binds `Joystick:getButtonCount`.
LoveApiImplementation _bindJoystickGetButtonCount(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:getButtonCount').buttonCount;
}

/// Binds `Joystick:getDeviceInfo`.
///
/// This returns vendor id, product id, and product version as multiple values.
LoveApiImplementation _bindJoystickGetDeviceInfo(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getDeviceInfo');
    return Value.multi(<Object?>[
      joystick.vendorId,
      joystick.productId,
      joystick.productVersion,
    ]);
  };
}

/// Binds `Joystick:getGUID`.
LoveApiImplementation _bindJoystickGetGuid(LibraryContext context) {
  return (args) => _requireJoystick(args, 0, 'Joystick:getGUID').guid;
}

/// Binds `Joystick:getGamepadAxis`.
LoveApiImplementation _bindJoystickGetGamepadAxis(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getGamepadAxis');
    return joystick.getGamepadAxis(
      _requireJoystickGamepadAxis(args, 1, 'Joystick:getGamepadAxis'),
    );
  };
}

/// Binds `Joystick:getGamepadMapping`.
///
/// LOVE returns mapping type and input index, plus hat direction when the
/// mapping targets a hat input.
LoveApiImplementation _bindJoystickGetGamepadMapping(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getGamepadMapping');
    final binding = joystick.getGamepadMapping(
      _requireJoystickGamepadInput(args, 1, 'Joystick:getGamepadMapping'),
    );
    if (binding == null) {
      return null;
    }

    final values = <Object?>[binding.type, binding.inputIndex];
    if (binding.hatDirection != null) {
      values.add(binding.hatDirection);
    }
    return Value.multi(values);
  };
}

/// Binds `Joystick:getGamepadMappingString`.
LoveApiImplementation _bindJoystickGetGamepadMappingStringMethod(
  LibraryContext context,
) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:getGamepadMappingString',
  ).getGamepadMappingString();
}

/// Binds `Joystick:getHat`.
LoveApiImplementation _bindJoystickGetHat(LibraryContext context) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:getHat',
  ).getHat(_requireRoundedInt(args, 1, 'Joystick:getHat'));
}

/// Binds `Joystick:getHatCount`.
LoveApiImplementation _bindJoystickGetHatCount(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:getHatCount').hats.length;
}

/// Binds `Joystick:getID`.
///
/// This returns the stable LOVE id and, when connected, the transient instance
/// id as a second result.
LoveApiImplementation _bindJoystickGetId(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getID');
    return Value.multi(<Object?>[
      joystick.id,
      joystick.connected ? joystick.instanceId : null,
    ]);
  };
}

/// Binds `Joystick:getName`.
LoveApiImplementation _bindJoystickGetName(LibraryContext context) {
  return (args) => _requireJoystick(args, 0, 'Joystick:getName').name;
}

/// Binds `Joystick:getVibration`.
///
/// This returns left and right motor strengths as multiple values.
LoveApiImplementation _bindJoystickGetVibration(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getVibration');
    return Value.multi(<Object?>[
      joystick.vibrationLeft,
      joystick.vibrationRight,
    ]);
  };
}

/// Binds `Joystick:isConnected`.
LoveApiImplementation _bindJoystickIsConnected(LibraryContext context) {
  return (args) => _requireJoystick(args, 0, 'Joystick:isConnected').connected;
}

/// Binds `Joystick:isDown`.
///
/// LOVE accepts either multiple button indices or a single table of indices.
LoveApiImplementation _bindJoystickIsDown(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:isDown');
    return joystick.isDown(
      _joystickButtonIndicesFromArgs(args, 1, 'Joystick:isDown'),
    );
  };
}

/// Binds `Joystick:isGamepad`.
LoveApiImplementation _bindJoystickIsGamepad(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:isGamepad').recognizedAsGamepad;
}

/// Binds `Joystick:isGamepadDown`.
///
/// LOVE accepts either multiple button names or a single table of button
/// names.
LoveApiImplementation _bindJoystickIsGamepadDown(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:isGamepadDown');
    return joystick.isGamepadDown(
      _joystickGamepadButtonsFromArgs(args, 1, 'Joystick:isGamepadDown'),
    );
  };
}

/// Binds `Joystick:isVibrationSupported`.
LoveApiImplementation _bindJoystickIsVibrationSupported(
  LibraryContext context,
) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:isVibrationSupported',
  ).vibrationSupported;
}

/// Binds `Joystick:setVibration`.
///
/// Omitting the first motor strength stops vibration. Otherwise this accepts
/// left strength, optional right strength, and optional duration.
LoveApiImplementation _bindJoystickSetVibration(LibraryContext context) {
  return (args) {
    const symbol = 'Joystick:setVibration';
    final joystick = _requireJoystick(args, 0, symbol);
    if (_rawValue(_valueAt(args, 1)) == null) {
      return joystick.stopVibration();
    }

    final left = _requireNumber(args, 1, symbol);
    final right = _rawValue(_valueAt(args, 2)) == null
        ? left
        : _requireNumber(args, 2, symbol);
    final duration = _rawValue(_valueAt(args, 3)) == null
        ? -1.0
        : _requireNumber(args, 3, symbol);
    return joystick.setVibration(left: left, right: right, duration: duration);
  };
}

/// Returns a validated gamepad axis name.
String _requireJoystickGamepadAxis(
  List<Object?> args,
  int index,
  String symbol,
) {
  final axis = _requireString(args, index, symbol);
  if (!loveIsValidGamepadAxis(axis)) {
    throw LuaError('$symbol invalid gamepad axis "$axis"');
  }

  return axis;
}

/// Returns a validated gamepad button name.
String _requireJoystickGamepadButton(
  List<Object?> args,
  int index,
  String symbol,
) {
  final button = _requireString(args, index, symbol);
  if (!loveIsValidGamepadButton(button)) {
    throw LuaError('$symbol invalid gamepad button "$button"');
  }

  return button;
}

/// Returns a validated gamepad input name.
///
/// This accepts either an axis or button identifier for mapping operations.
String _requireJoystickGamepadInput(
  List<Object?> args,
  int index,
  String symbol,
) {
  final input = _requireString(args, index, symbol);
  if (!loveIsValidGamepadInput(input)) {
    throw LuaError('$symbol invalid gamepad axis/button "$input"');
  }

  return input;
}

/// Returns a validated joystick hat direction.
String _requireJoystickHat(List<Object?> args, int index, String symbol) {
  final direction = _requireString(args, index, symbol);
  if (!loveIsValidJoystickHat(direction)) {
    throw LuaError('$symbol invalid joystick hat "$direction"');
  }

  return direction;
}

/// Returns a validated joystick mapping input type.
String _requireJoystickInputType(List<Object?> args, int index, String symbol) {
  final inputType = _requireString(args, index, symbol);
  if (!loveIsValidJoystickInputType(inputType)) {
    throw LuaError('$symbol invalid joystick input type "$inputType"');
  }

  return inputType;
}

/// Normalizes joystick button indices from varargs or a single Lua table.
List<int> _joystickButtonIndicesFromArgs(
  List<Object?> args,
  int startIndex,
  String symbol,
) {
  final table = args.length == startIndex + 1
      ? _tableIfPresent(_valueAt(args, startIndex))
      : null;
  if (table != null) {
    final buttons = <int>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }

      final raw = _rawValue(entry);
      if (raw is! num) {
        throw LuaError('$symbol expected numeric button indices in table');
      }
      buttons.add(raw.round());
    }
    if (buttons.isEmpty) {
      _requireRoundedInt(args, startIndex, symbol);
    }
    return List<int>.unmodifiable(buttons);
  }

  if (args.length <= startIndex) {
    _requireRoundedInt(args, startIndex, symbol);
  }

  return List<int>.generate(
    args.length - startIndex,
    (index) => _requireRoundedInt(args, startIndex + index, symbol),
    growable: false,
  );
}

/// Normalizes gamepad button names from varargs or a single Lua table.
List<String> _joystickGamepadButtonsFromArgs(
  List<Object?> args,
  int startIndex,
  String symbol,
) {
  final table = args.length == startIndex + 1
      ? _tableIfPresent(_valueAt(args, startIndex))
      : null;
  if (table != null) {
    final buttons = <String>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }

      buttons.add(_requireJoystickGamepadButton(<Object?>[entry], 0, symbol));
    }
    if (buttons.isEmpty) {
      _requireJoystickGamepadButton(args, startIndex, symbol);
    }
    return List<String>.unmodifiable(buttons);
  }

  if (args.length <= startIndex) {
    _requireJoystickGamepadButton(args, startIndex, symbol);
  }

  return List<String>.generate(
    args.length - startIndex,
    (index) => _requireJoystickGamepadButton(args, startIndex + index, symbol),
    growable: false,
  );
}
