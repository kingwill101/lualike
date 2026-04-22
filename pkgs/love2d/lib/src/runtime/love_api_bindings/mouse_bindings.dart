part of '../love_api_bindings.dart';

/// Binds `love.mouse.getCursor`.
LoveApiImplementation _bindMouseGetCursor(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final cursor = runtime.mouse.cursor;
    return cursor == null ? null : _wrapCursor(context, cursor);
  };
}

/// Binds `love.mouse.getPosition`.
LoveApiImplementation _bindMouseGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[runtime.mouse.x, runtime.mouse.y]);
}

/// Binds `love.mouse.getRelativeMode`.
LoveApiImplementation _bindMouseGetRelativeMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.relativeMode;
}

/// Binds `love.mouse.getSystemCursor`.
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

/// Binds `love.mouse.getX`.
LoveApiImplementation _bindMouseGetX(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.x;
}

/// Binds `love.mouse.getY`.
LoveApiImplementation _bindMouseGetY(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.y;
}

/// Binds `love.mouse.isCursorSupported`.
LoveApiImplementation _bindMouseIsCursorSupported(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.cursorSupported;
}

/// Binds `love.mouse.isDown`.
LoveApiImplementation _bindMouseIsDown(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.isDown(_mouseButtonSequence(args));
}

/// Binds `love.mouse.isGrabbed`.
LoveApiImplementation _bindMouseIsGrabbed(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.grabbed;
}

/// Binds `love.mouse.isVisible`.
LoveApiImplementation _bindMouseIsVisible(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.visible;
}

/// Binds `love.mouse.newCursor`.
///
/// LOVE accepts either [LoveImageData] or a resource-backed image source, so
/// this binding resolves file inputs into decoded image data before constructing
/// the runtime cursor.
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

/// Binds `love.mouse.setCursor`.
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

/// Binds `love.mouse.setGrabbed`.
LoveApiImplementation _bindMouseSetGrabbed(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.grabbed = _requireBoolean(args, 0, 'love.mouse.setGrabbed');
    return null;
  };
}

/// Binds `love.mouse.setPosition`.
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

/// Binds `love.mouse.setRelativeMode`.
LoveApiImplementation _bindMouseSetRelativeMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.mouse.setRelativeMode(
    _requireBoolean(args, 0, 'love.mouse.setRelativeMode'),
  );
}

/// Binds `love.mouse.setVisible`.
LoveApiImplementation _bindMouseSetVisible(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setVisible(_requireBoolean(args, 0, 'love.mouse.setVisible'));
    return null;
  };
}

/// Binds `love.mouse.setX`.
LoveApiImplementation _bindMouseSetX(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setX(_requireNumber(args, 0, 'love.mouse.setX'));
    return null;
  };
}

/// Binds `love.mouse.setY`.
LoveApiImplementation _bindMouseSetY(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.mouse.setY(_requireNumber(args, 0, 'love.mouse.setY'));
    return null;
  };
}

/// Throws when cursor APIs are unavailable on the current mouse backend.
void _requireCursorSupport(LoveMouseState mouse, String symbol) {
  if (!mouse.cursorSupported) {
    throw LuaError('$symbol cursors are not supported');
  }
}

/// Returns the validated LOVE system cursor type at [index].
String _requireMouseCursorType(List<Object?> args, int index, String symbol) {
  final cursorType = _requireString(args, index, symbol);
  if (!loveIsValidCursorType(cursorType)) {
    throw LuaError('$symbol invalid cursor type "$cursorType"');
  }

  return cursorType;
}

/// Normalizes `love.mouse.isDown` arguments into button indices.
///
/// LOVE accepts either positional button arguments or a single array table of
/// buttons, and this helper supports both shapes.
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
