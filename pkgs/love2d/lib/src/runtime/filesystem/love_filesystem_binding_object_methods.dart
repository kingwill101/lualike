part of 'love_filesystem_bindings.dart';

/// Builds the wrapper-object binding implementations for filesystem values.
extension _LoveFilesystemObjectBindingMethods on _LoveFilesystemBindings {
  /// Implements `File:close`.
  LoveApiImplementation fileClose() {
    return (args) => _requireFile(args, 0, 'File:close').close();
  }

  /// Implements `File:flush`.
  LoveApiImplementation fileFlush() {
    return (args) async {
      try {
        return await _requireFile(args, 0, 'File:flush').flush();
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  /// Implements `File:getBuffer`.
  LoveApiImplementation fileGetBuffer() {
    return (args) {
      final file = _requireFile(args, 0, 'File:getBuffer');
      return Value.multi(<Object?>[
        _bufferModeName(file.bufferMode),
        file.bufferSize,
      ]);
    };
  }

  /// Implements `File:getFilename`.
  LoveApiImplementation fileGetFilename() {
    return (args) => _requireFile(args, 0, 'File:getFilename').filename;
  }

  /// Implements `File:getExtension`.
  LoveApiImplementation fileGetExtension() {
    return (args) => _requireFile(args, 0, 'File:getExtension').extension;
  }

  /// Implements `File:getMode`.
  LoveApiImplementation fileGetMode() {
    return (args) => _requireFile(args, 0, 'File:getMode').mode;
  }

  /// Implements `File:getSize`.
  LoveApiImplementation fileGetSize() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:getSize');
      late final int? size;
      try {
        size = await file.getSize();
      } on StateError catch (error) {
        return _ioError(error.message);
      }
      if (!_hasKnownFilesystemNumber(size)) {
        return _ioError('Could not determine file size.');
      }
      final knownSize = size!;
      if (knownSize >= _loveFilesystemLuaNumberLimit) {
        return _ioError('Size is too large.');
      }
      return knownSize;
    };
  }

  /// Implements `File:isEOF`.
  LoveApiImplementation fileIsEOF() {
    return (args) => _requireFile(args, 0, 'File:isEOF').isEOF();
  }

  /// Implements `File:isOpen`.
  LoveApiImplementation fileIsOpen() {
    return (args) => _requireFile(args, 0, 'File:isOpen').isOpen;
  }

  /// Implements `File:lines`.
  LoveApiImplementation fileLines() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:lines');
      final restoreUserPosition = file.mode != 'c';
      final userPosition = restoreUserPosition && file.mode == 'r'
          ? math.max(0, await file.tell())
          : 0;

      if (file.mode != 'r') {
        if (file.mode != 'c') {
          await file.close();
        }

        try {
          final opened = await file.open('r');
          if (!opened) {
            throw LuaError('Could not open file.');
          }
        } on StateError {
          throw LuaError('Could not open file.');
        }
      }

      return _fileLinesIterator(
        file,
        restoreUserPosition: restoreUserPosition,
        userPosition: userPosition,
      );
    };
  }

  /// Implements `File:open`.
  LoveApiImplementation fileOpen() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:open');
      final mode = _fileMode(_requireString(args, 1, 'File:open'), 'File:open');
      try {
        return await file.open(mode);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  /// Implements `File:read`.
  LoveApiImplementation fileRead() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:read');
      var startIndex = 1;
      var containerType = _LoveFilesystemContainerType.string;
      if (_exactStringLike(_valueAt(args, 1)) != null) {
        try {
          containerType = _containerType(
            _requireString(args, 1, 'File:read'),
            'File:read',
          );
        } on LuaError catch (error) {
          return _ioError(error.message);
        }
        startIndex = 2;
      }

      final explicitSize = _optionalTruncatedInt(args, startIndex);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid read size.');
      }
      final size = explicitSize ?? -1;
      try {
        final bytes = await file.readBytes(size);
        return _readResult(
          bytes,
          filename: file.filename,
          containerType: containerType,
        );
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  /// Implements `File:seek`.
  LoveApiImplementation fileSeek() {
    return (args) {
      final file = _requireFile(args, 0, 'File:seek');
      final position = _numberValue(args, 1, 'File:seek');
      if (position < 0 || position >= _loveFilesystemLuaNumberLimitDouble) {
        return false;
      }
      return file.seek(position.toInt());
    };
  }

  /// Implements `File:setBuffer`.
  LoveApiImplementation fileSetBuffer() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:setBuffer');
      final mode = _bufferMode(
        _requireString(args, 1, 'File:setBuffer'),
        'File:setBuffer',
      );
      final size = _optionalTruncatedInt(args, 2) ?? 0;
      try {
        return await file.setBuffer(mode, size);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  /// Implements `File:tell`.
  LoveApiImplementation fileTell() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:tell');
      final position = await file.tell();
      if (position < 0) {
        return _ioError('Invalid position.');
      }
      if (position >= _loveFilesystemLuaNumberLimit) {
        return _ioError('Number is too large.');
      }
      return position;
    };
  }

  /// Implements `File:write`.
  LoveApiImplementation fileWrite() {
    return (args) async {
      final file = _requireFile(args, 0, 'File:write');
      final explicitSize = _optionalTruncatedInt(args, 2);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid write size.');
      }
      final bytes = _sliceBytes(
        await _dataBytes(
          _valueAt(args, 1),
          'File:write',
          bindings: this,
          argumentIndex: 2,
          expectedTypeDescription: 'string or data',
        ),
        explicitSize,
      );
      try {
        return await file.writeBytes(bytes);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  /// Implements `FileData:getExtension`.
  LoveApiImplementation fileDataGetExtension() {
    return (args) =>
        _requireFileData(args, 0, 'FileData:getExtension').extension;
  }

  /// Implements `FileData:getFilename`.
  LoveApiImplementation fileDataGetFilename() {
    return (args) => _requireFileData(args, 0, 'FileData:getFilename').filename;
  }

  /// Implements `FileData:clone`.
  LoveApiImplementation fileDataClone() {
    return (args) {
      final data = _requireFileData(args, 0, 'FileData:clone');
      return wrapFileData(data.clone());
    };
  }

  /// Implements `Data:getSize`.
  LoveApiImplementation dataGetSize() {
    return (args) => _requireFileData(args, 0, 'Data:getSize').size;
  }

  /// Implements `Data:getString`.
  LoveApiImplementation dataGetString() {
    return (args) {
      final data = _requireFileData(args, 0, 'Data:getString');
      return runtime.constantStringValue(data.bytes);
    };
  }

  /// Implements `Object:release`.
  LoveApiImplementation objectRelease() {
    return (args) async {
      final rawObject = _wrapperObject(args, 0, 'Object:release');
      if (_loveFilesystemReleased[rawObject] == true) {
        return false;
      }

      _loveFilesystemReleased[rawObject] = true;
      if (rawObject is LoveFilesystemFile && rawObject.isOpen) {
        await rawObject.close();
      }
      return true;
    };
  }

  /// Implements `Object:type`.
  LoveApiImplementation objectType() {
    return (args) => _wrapperTypeName(args, 0, 'Object:type');
  }

  /// Implements `Object:typeOf`.
  LoveApiImplementation objectTypeOf() {
    return (args) {
      final hierarchy = _wrapperHierarchy(args, 0, 'Object:typeOf');
      final typeName = _requireString(args, 1, 'Object:typeOf');
      return hierarchy.contains(typeName);
    };
  }

  /// Creates a `lines` iterator for an opened [file].
  Value _fileLinesIterator(
    LoveFilesystemFile file, {
    required bool restoreUserPosition,
    required int userPosition,
  }) {
    final cursor = _LoveFilesystemFileLineCursor(
      file: file,
      restoreUserPosition: restoreUserPosition,
      userPosition: userPosition,
    );
    return Value(
      _builder.create((args) async {
        final line = await cursor.next();
        if (line == null) {
          return null;
        }
        return runtime.constantStringValue(line);
      }),
      functionName: 'lines',
    );
  }
}
