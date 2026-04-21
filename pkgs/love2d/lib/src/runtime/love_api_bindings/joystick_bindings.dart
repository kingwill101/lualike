part of '../love_api_bindings.dart';

LoveApiImplementation _bindJoystickGetGamepadMappingString(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.joysticks.getGamepadMappingString(
    _requireString(args, 0, 'love.joystick.getGamepadMappingString'),
  );
}

LoveApiImplementation _bindJoystickGetJoystickCount(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.joysticks.joystickCount;
}

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

LoveApiImplementation _bindJoystickGetAxes(LibraryContext context) {
  return (args) {
    final axes = _requireJoystick(args, 0, 'Joystick:getAxes').axes;
    return Value.multi(<Object?>[...axes]);
  };
}

LoveApiImplementation _bindJoystickGetAxis(LibraryContext context) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:getAxis',
  ).getAxis(_requireRoundedInt(args, 1, 'Joystick:getAxis'));
}

LoveApiImplementation _bindJoystickGetAxisCount(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:getAxisCount').axes.length;
}

LoveApiImplementation _bindJoystickGetButtonCount(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:getButtonCount').buttonCount;
}

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

LoveApiImplementation _bindJoystickGetGuid(LibraryContext context) {
  return (args) => _requireJoystick(args, 0, 'Joystick:getGUID').guid;
}

LoveApiImplementation _bindJoystickGetGamepadAxis(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getGamepadAxis');
    return joystick.getGamepadAxis(
      _requireJoystickGamepadAxis(args, 1, 'Joystick:getGamepadAxis'),
    );
  };
}

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

LoveApiImplementation _bindJoystickGetGamepadMappingStringMethod(
  LibraryContext context,
) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:getGamepadMappingString',
  ).getGamepadMappingString();
}

LoveApiImplementation _bindJoystickGetHat(LibraryContext context) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:getHat',
  ).getHat(_requireRoundedInt(args, 1, 'Joystick:getHat'));
}

LoveApiImplementation _bindJoystickGetHatCount(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:getHatCount').hats.length;
}

LoveApiImplementation _bindJoystickGetId(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getID');
    return Value.multi(<Object?>[
      joystick.id,
      joystick.connected ? joystick.instanceId : null,
    ]);
  };
}

LoveApiImplementation _bindJoystickGetName(LibraryContext context) {
  return (args) => _requireJoystick(args, 0, 'Joystick:getName').name;
}

LoveApiImplementation _bindJoystickGetVibration(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:getVibration');
    return Value.multi(<Object?>[
      joystick.vibrationLeft,
      joystick.vibrationRight,
    ]);
  };
}

LoveApiImplementation _bindJoystickIsConnected(LibraryContext context) {
  return (args) => _requireJoystick(args, 0, 'Joystick:isConnected').connected;
}

LoveApiImplementation _bindJoystickIsDown(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:isDown');
    return joystick.isDown(
      _joystickButtonIndicesFromArgs(args, 1, 'Joystick:isDown'),
    );
  };
}

LoveApiImplementation _bindJoystickIsGamepad(LibraryContext context) {
  return (args) =>
      _requireJoystick(args, 0, 'Joystick:isGamepad').recognizedAsGamepad;
}

LoveApiImplementation _bindJoystickIsGamepadDown(LibraryContext context) {
  return (args) {
    final joystick = _requireJoystick(args, 0, 'Joystick:isGamepadDown');
    return joystick.isGamepadDown(
      _joystickGamepadButtonsFromArgs(args, 1, 'Joystick:isGamepadDown'),
    );
  };
}

LoveApiImplementation _bindJoystickIsVibrationSupported(
  LibraryContext context,
) {
  return (args) => _requireJoystick(
    args,
    0,
    'Joystick:isVibrationSupported',
  ).vibrationSupported;
}

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

String _requireJoystickHat(List<Object?> args, int index, String symbol) {
  final direction = _requireString(args, index, symbol);
  if (!loveIsValidJoystickHat(direction)) {
    throw LuaError('$symbol invalid joystick hat "$direction"');
  }

  return direction;
}

String _requireJoystickInputType(List<Object?> args, int index, String symbol) {
  final inputType = _requireString(args, index, symbol);
  if (!loveIsValidJoystickInputType(inputType)) {
    throw LuaError('$symbol invalid joystick input type "$inputType"');
  }

  return inputType;
}

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
