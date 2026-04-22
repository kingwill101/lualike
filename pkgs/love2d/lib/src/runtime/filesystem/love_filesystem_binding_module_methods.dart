part of 'love_filesystem_bindings.dart';

extension _LoveFilesystemModuleBindingMethods on _LoveFilesystemBindings {
  LoveApiImplementation append() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.append');
      final explicitSize = _optionalTruncatedInt(args, 2);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid write size.');
      }
      final bytes = _sliceBytes(
        await _dataBytes(
          _valueAt(args, 1),
          'love.filesystem.append',
          bindings: this,
          argumentIndex: 2,
        ),
        explicitSize,
      );
      try {
        await state.writeBytesOrThrow(filename, bytes, append: true);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
      return true;
    };
  }

  LoveApiImplementation areSymlinksEnabled() {
    return (args) => state.symlinksEnabled;
  }

  LoveApiImplementation createDirectory() {
    return (args) async {
      final path = _requireString(args, 0, 'love.filesystem.createDirectory');
      return state.createDirectory(path);
    };
  }

  LoveApiImplementation getAppdataDirectory() {
    return (args) => state.getAppdataDirectory();
  }

  LoveApiImplementation getCRequirePath() {
    return (args) => state.getCRequirePathString();
  }

  LoveApiImplementation getDirectoryItems() {
    return (args) async {
      final directory = _requireString(
        args,
        0,
        'love.filesystem.getDirectoryItems',
      );
      final items = await state.getDirectoryItems(directory);
      return _arrayTable(items);
    };
  }

  LoveApiImplementation getIdentity() {
    return (args) => state.identity;
  }

  LoveApiImplementation getInfo() {
    return (args) async {
      final targetPath = _requireString(args, 0, 'love.filesystem.getInfo');
      LoveFilesystemNodeType? filterType;
      Value? wrappedTable;
      Map<dynamic, dynamic>? infoTable;
      var tableArgumentIndex = 1;

      if (args.length >= 2) {
        final typeName = _luaStringLike(_valueAt(args, 1));
        if (typeName != null) {
          filterType = _fileType(typeName, 'love.filesystem.getInfo');
          tableArgumentIndex = 2;
        }
      }

      if (args.length > tableArgumentIndex) {
        final tableTarget = _tableTargetIfPresent(
          _valueAt(args, tableArgumentIndex),
        );
        if (tableTarget != null) {
          wrappedTable = tableTarget.$1;
          infoTable = tableTarget.$2;
        }
      }

      final info = await state.getInfo(targetPath, filterType: filterType);
      if (info == null) {
        return null;
      }

      final table = infoTable ?? <Object?, Object?>{};
      table['type'] = _fileTypeName(info.type);
      if (_hasKnownFilesystemNumber(info.size)) {
        table['size'] = _clampLuaFilesystemNumber(info.size!);
      }
      if (_hasKnownFilesystemNumber(info.modtime)) {
        table['modtime'] = _clampLuaFilesystemNumber(info.modtime!);
      }

      if (wrappedTable != null) {
        return wrappedTable;
      }
      if (infoTable != null) {
        return infoTable;
      }
      return Value(table);
    };
  }

  LoveApiImplementation getRealDirectory() {
    return (args) async {
      final targetPath = _requireString(
        args,
        0,
        'love.filesystem.getRealDirectory',
      );
      final realDirectory = await state.getRealDirectory(targetPath);
      if (realDirectory == null) {
        return _ioError('File does not exist on disk.');
      }
      return realDirectory;
    };
  }

  LoveApiImplementation getRequirePath() {
    return (args) => state.getRequirePathString();
  }

  LoveApiImplementation getSaveDirectory() {
    return (args) => state.getSaveDirectory();
  }

  LoveApiImplementation getSource() {
    return (args) => state.source;
  }

  LoveApiImplementation getSourceBaseDirectory() {
    return (args) => state.getSourceBaseDirectory();
  }

  LoveApiImplementation getUserDirectory() {
    return (args) => state.getUserDirectory();
  }

  LoveApiImplementation getWorkingDirectory() {
    return (args) => state.getWorkingDirectory();
  }

  LoveApiImplementation init() {
    return (args) {
      final arg0 = _requireString(args, 0, 'love.filesystem.init');
      state.init(arg0);
      return null;
    };
  }

  LoveApiImplementation isFused() {
    return (args) => state.fused;
  }

  LoveApiImplementation lines() {
    return (args) async {
      final filename = _luaStringLike(_valueAt(args, 0));
      if (filename == null) {
        throw LuaError('love.filesystem.lines expected filename.');
      }
      try {
        return await _createLinesIterator(filename);
      } on LuaError {
        throw LuaError('Could not open file.');
      }
    };
  }

  LoveApiImplementation load() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.load');
      late final List<int> bytes;
      try {
        bytes = await state.readAllBytesOrThrow(filename);
      } on StateError catch (error) {
        return _ioError(error.message);
      }

      final result = await runtime.loadChunk(
        LuaChunkLoadRequest(
          source: runtime.constantStringValue(bytes),
          chunkName: '@$filename',
        ),
      );
      if (!result.isSuccess) {
        throw LuaError(
          formatLoveFilesystemLoadSyntaxError(result.errorMessage),
        );
      }
      return result.chunk;
    };
  }

  LoveApiImplementation mount() {
    return (args) async {
      final droppedFile = _droppedFileIfPresent(_valueAt(args, 0));
      if (droppedFile != null) {
        final mountpoint = _requireString(args, 1, 'love.filesystem.mount');
        final appendToPath = _optionalBool(args, 2, defaultValue: false);
        return state.mount(
          droppedFile.physicalPath,
          mountpoint: mountpoint,
          appendToPath: appendToPath,
        );
      }

      final mountedData = await _mountedDataIfPresent(
        _valueAt(args, 0),
        symbol: 'love.filesystem.mount',
        argumentIndex: 1,
        bindings: this,
      );
      if (mountedData != null) {
        late final String archiveName;
        late final String mountpoint;
        late final bool appendToPath;

        if (mountedData.archiveName != null &&
            !(args.length >= 3 && _luaStringLike(_valueAt(args, 2)) != null)) {
          archiveName = mountedData.archiveName!;
          mountpoint = _requireString(args, 1, 'love.filesystem.mount');
          appendToPath = _optionalBool(args, 2, defaultValue: false);
        } else {
          archiveName = _requireString(args, 1, 'love.filesystem.mount');
          mountpoint = _requireString(args, 2, 'love.filesystem.mount');
          appendToPath = _optionalBool(args, 3, defaultValue: false);
        }

        return state.mountArchiveBytes(
          mountedData.bytes,
          sourceIdentity: mountedData.sourceIdentity,
          archiveName: archiveName,
          mountpoint: mountpoint,
          appendToPath: appendToPath,
        );
      }

      final archive = _requireString(args, 0, 'love.filesystem.mount');
      final mountpoint = _requireString(args, 1, 'love.filesystem.mount');
      final appendToPath = _optionalBool(args, 2, defaultValue: false);
      return state.mount(
        archive,
        mountpoint: mountpoint,
        appendToPath: appendToPath,
      );
    };
  }

  LoveApiImplementation newFile() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.newFile');
      final file = LoveFilesystemFile(state: state, filename: filename);

      final modeName = _luaStringLike(_valueAt(args, 1));
      if (modeName != null) {
        final mode = _fileMode(modeName, 'love.filesystem.newFile');
        try {
          final opened = await file.open(mode);
          if (!opened) {
            return _ioError('Could not open file.');
          }
        } on StateError catch (error) {
          return _ioError(error.message);
        }
      }

      return wrapFile(file);
    };
  }

  LoveApiImplementation newFileData() {
    return (args) async {
      if (args.length == 1) {
        final source = _valueAt(args, 0);
        final filename = _luaStringLike(source);
        if (filename != null) {
          try {
            return wrapFileData(
              await state.readFileDataOrThrow(filename, filename: filename),
            );
          } on StateError catch (error) {
            return _ioError(error.message);
          }
        }

        final file = _fileIfPresent(source);
        if (file == null) {
          throw LuaError(
            'love.filesystem.newFileData expected filename or File at argument 1',
          );
        }

        try {
          final bytes = await file.readBytes();
          return wrapFileData(
            LoveFilesystemFileData(bytes: bytes, filename: file.filename),
          );
        } on StateError catch (error) {
          return _ioError(error.message);
        }
      }

      final bytes = await _dataBytes(
        _valueAt(args, 0),
        'love.filesystem.newFileData',
        bindings: this,
        argumentIndex: 1,
      );
      final filename = _requireString(args, 1, 'love.filesystem.newFileData');
      return wrapFileData(
        LoveFilesystemFileData(bytes: bytes, filename: filename),
      );
    };
  }

  LoveApiImplementation read() {
    return (args) async {
      var startIndex = 0;
      var containerType = _LoveFilesystemContainerType.string;
      if (args.length >= 2 && _exactStringLike(_valueAt(args, 1)) != null) {
        containerType = _containerType(
          _requireString(args, 0, 'love.filesystem.read'),
          'love.filesystem.read',
        );
        startIndex = 1;
      }

      final filename = _requireString(args, startIndex, 'love.filesystem.read');
      final explicitSize = _optionalTruncatedInt(args, startIndex + 1);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid read size.');
      }
      final size = explicitSize ?? -1;
      late final List<int> bytes;
      try {
        bytes = await state.readAllBytesOrThrow(filename, size: size);
      } on StateError catch (error) {
        return _ioError(error.message);
      }

      return _readResult(
        bytes,
        filename: filename,
        containerType: containerType,
      );
    };
  }

  LoveApiImplementation remove() {
    return (args) async {
      final targetPath = _requireString(args, 0, 'love.filesystem.remove');
      return state.remove(targetPath);
    };
  }

  LoveApiImplementation setCRequirePath() {
    return (args) {
      final value = _requireString(args, 0, 'love.filesystem.setCRequirePath');
      state.setCRequirePath(value);
      syncLoveFilesystemPackageInterop(runtime);
      return null;
    };
  }

  LoveApiImplementation setIdentity() {
    return (args) {
      final identity = _requireString(args, 0, 'love.filesystem.setIdentity');
      final appendToPath = _optionalBool(args, 1, defaultValue: false);
      if (!state.setIdentity(identity, appendToPath: appendToPath)) {
        throw LuaError('Could not set write directory.');
      }
      return null;
    };
  }

  LoveApiImplementation setRequirePath() {
    return (args) {
      final value = _requireString(args, 0, 'love.filesystem.setRequirePath');
      state.setRequirePath(value);
      syncLoveFilesystemPackageInterop(runtime);
      return null;
    };
  }

  LoveApiImplementation setSource() {
    return (args) async {
      final source = _requireString(args, 0, 'love.filesystem.setSource');
      if (!await state.setSourceFromFilesystem(source)) {
        throw LuaError('Could not set source.');
      }
      return null;
    };
  }

  LoveApiImplementation setSymlinksEnabled() {
    return (args) {
      state.setSymlinksEnabled(
        _requireBoolean(args, 0, 'love.filesystem.setSymlinksEnabled'),
      );
      return null;
    };
  }

  LoveApiImplementation unmount() {
    return (args) async {
      final sourceIdentity = await _mountedDataIdentityIfPresent(
        _valueAt(args, 0),
        bindings: this,
      );
      if (sourceIdentity != null) {
        return state.unmountData(sourceIdentity);
      }

      final archive = _requireString(args, 0, 'love.filesystem.unmount');
      return await state.unmount(archive);
    };
  }

  LoveApiImplementation write() {
    return (args) async {
      final filename = _requireString(args, 0, 'love.filesystem.write');
      final explicitSize = _optionalTruncatedInt(args, 2);
      if (explicitSize != null && explicitSize < 0) {
        return _ioError('Invalid write size.');
      }
      final bytes = _sliceBytes(
        await _dataBytes(
          _valueAt(args, 1),
          'love.filesystem.write',
          bindings: this,
          argumentIndex: 2,
        ),
        explicitSize,
      );
      try {
        await state.writeBytesOrThrow(filename, bytes, append: false);
      } on StateError catch (error) {
        return _ioError(error.message);
      }
      return true;
    };
  }

  Future<Value> _createLinesIterator(
    String filename, {
    int startOffset = 0,
  }) async {
    try {
      final bytes = await state.readAllBytesOrThrow(filename);
      return _linesIterator(bytes, startOffset: startOffset);
    } on StateError catch (error) {
      throw LuaError(error.message);
    }
  }

  Value _linesIterator(List<int> bytes, {int startOffset = 0}) {
    final cursor = _LoveFilesystemLineCursor(bytes, startOffset: startOffset);
    return Value(
      _builder.create((args) {
        final line = cursor.next();
        if (line == null) {
          return null;
        }
        return runtime.constantStringValue(line);
      }),
      functionName: 'lines',
    );
  }
}
