part of '../love_api_bindings.dart';

LoveApiImplementation _bindMouseGetCursor(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final cursor = runtime.mouse.cursor;
    return cursor == null ? null : _wrapCursor(context, cursor);
  };
}

LoveApiImplementation _bindMouseGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[runtime.mouse.x, runtime.mouse.y]);
}

LoveApiImplementation _bindMouseGetRelativeMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.relativeMode;
}

LoveApiImplementation _bindMouseGetSystemCursor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.mouse.getSystemCursor';
    _requireCursorSupport(runtime.mouse, symbol);
    return _wrapCursor(
      context,
      runtime.mouse.getSystemCursor(_requireMouseCursorType(args, 0, symbol)),
    );
  };
}

LoveApiImplementation _bindMouseGetX(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.x;
}

LoveApiImplementation _bindMouseGetY(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.y;
}

LoveApiImplementation _bindMouseIsCursorSupported(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.cursorSupported;
}

LoveApiImplementation _bindMouseIsDown(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.isDown(_mouseButtonSequence(args));
}

LoveApiImplementation _bindMouseIsGrabbed(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.grabbed;
}

LoveApiImplementation _bindMouseIsVisible(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.visible;
}

LoveApiImplementation _bindMouseNewCursor(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.mouse.newCursor';
    _requireCursorSupport(runtime.mouse, symbol);
    var imageData = _imageDataIfPresent(_valueAt(args, 0));
    String? source;
    if (imageData == null) {
      final fileData = await _requireResourceFileData(
        context,
        _valueAt(args, 0),
        symbol,
        expectedKinds: 'ImageData, filename, FileData, or File',
      );
      source = fileData.filename;
      try {
        imageData = LoveImageData.decodeEncodedBytes(
          bytes: fileData.bytes,
          source: fileData.filename,
        );
      } catch (error) {
        throw LuaError('$symbol failed to load "${fileData.filename}": $error');
      }
    }

    final cursor = runtime.mouse.newCursor(
      imageData: imageData,
      source: source,
      hotspotX: args.length >= 2 ? _requireRoundedInt(args, 1, symbol) : 0,
      hotspotY: args.length >= 3 ? _requireRoundedInt(args, 2, symbol) : 0,
    );
    return _wrapCursor(context, cursor);
  };
}

LoveApiImplementation _bindMouseSetCursor(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty) {
      runtime.mouse.setCursor();
      return null;
    }

    runtime.mouse.setCursor(_requireCursor(args, 0, 'love.mouse.setCursor'));
    return null;
  };
}

LoveApiImplementation _bindMouseSetGrabbed(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.grabbed = _requireBoolean(args, 0, 'love.mouse.setGrabbed');
    return null;
  };
}

LoveApiImplementation _bindMouseSetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setPosition(
      _requireNumber(args, 0, 'love.mouse.setPosition'),
      _requireNumber(args, 1, 'love.mouse.setPosition'),
    );
    return null;
  };
}

LoveApiImplementation _bindMouseSetRelativeMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.setRelativeMode(
    _requireBoolean(args, 0, 'love.mouse.setRelativeMode'),
  );
}

LoveApiImplementation _bindMouseSetVisible(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setVisible(_requireBoolean(args, 0, 'love.mouse.setVisible'));
    return null;
  };
}

LoveApiImplementation _bindMouseSetX(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setX(_requireNumber(args, 0, 'love.mouse.setX'));
    return null;
  };
}

LoveApiImplementation _bindMouseSetY(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setY(_requireNumber(args, 0, 'love.mouse.setY'));
    return null;
  };
}

void _requireCursorSupport(LoveMouseState mouse, String symbol) {
  if (!mouse.cursorSupported) {
    throw LuaError('$symbol cursors are not supported');
  }
}

String _requireMouseCursorType(List<Object?> args, int index, String symbol) {
  final cursorType = _requireString(args, index, symbol);
  if (!loveIsValidCursorType(cursorType)) {
    throw LuaError('$symbol invalid cursor type "$cursorType"');
  }

  return cursorType;
}

List<int> _mouseButtonSequence(List<Object?> args) {
  const symbol = 'love.mouse.isDown';
  if (args.isEmpty) {
    return const <int>[];
  }

  final table = args.length == 1 ? _tableIfPresent(args.first) : null;
  if (table != null) {
    final values = <int>[];
    for (var index = 1; ; index++) {
      final entry = _tableIndexedEntry(table, index);
      if (entry == null) {
        break;
      }

      final raw = _rawValue(entry);
      if (raw is! num) {
        throw LuaError('$symbol expected numeric button indices in table');
      }
      values.add(raw.round());
    }
    return values;
  }

  return List<int>.generate(
    args.length,
    (index) => _requireRoundedInt(args, index, symbol),
    growable: false,
  );
}
