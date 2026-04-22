part of 'love_filesystem_bindings.dart';

extension _LoveFilesystemObjectBindingMethods on _LoveFilesystemBindings {
  LoveApiImplementation fileClose() {
    return (args) => _requireFile(args, 0, 'File:close').close();
  }

  LoveApiImplementation fileFlush() {
    return (args) async {
      try {
        return await _requireFile(args, 0, 'File:flush').flush();
      } on StateError catch (error) {
        return _ioError(error.message);
      }
    };
  }

  LoveApiImplementation fileGetBuffer() {
    return (args) {
      final file = _requireFile(args, 0, 'File:getBuffer');
      return Value.multi(<Object?>[
        _bufferModeName(file.bufferMode),
        file.bufferSize,
      ]);
    };
  }

  LoveApiImplementation fileGetFilename() {
    return (args) => _requireFile(args, 0, 'File:getFilename').filename;
  }

  LoveApiImplementation fileGetExtension() {
    return (args) => _requireFile(args, 0, 'File:getExtension').extension;
  }

  LoveApiImplementation fileGetMode() {
    return (args) => _requireFile(args, 0, 'File:getMode').mode;
  }

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

  LoveApiImplementation fileIsEOF() {
    return (args) => _requireFile(args, 0, 'File:isEOF').isEOF();
  }

  LoveApiImplementation fileIsOpen() {
    return (args) => _requireFile(args, 0, 'File:isOpen').isOpen;
  }

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

  LoveApiImplementation fileDataGetExtension() {
    return (args) =>
        _requireFileData(args, 0, 'FileData:getExtension').extension;
  }

  LoveApiImplementation fileDataGetFilename() {
    return (args) => _requireFileData(args, 0, 'FileData:getFilename').filename;
  }

  LoveApiImplementation fileDataClone() {
    return (args) {
      final data = _requireFileData(args, 0, 'FileData:clone');
      return wrapFileData(data.clone());
    };
  }

  LoveApiImplementation dataGetSize() {
    return (args) => _requireFileData(args, 0, 'Data:getSize').size;
  }

  LoveApiImplementation dataGetString() {
    return (args) {
      final data = _requireFileData(args, 0, 'Data:getString');
      return runtime.constantStringValue(data.bytes);
    };
  }

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

  LoveApiImplementation objectType() {
    return (args) => _wrapperTypeName(args, 0, 'Object:type');
  }

  LoveApiImplementation objectTypeOf() {
    return (args) {
      final hierarchy = _wrapperHierarchy(args, 0, 'Object:typeOf');
      final typeName = _requireString(args, 1, 'Object:typeOf');
      return hierarchy.contains(typeName);
    };
  }

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
