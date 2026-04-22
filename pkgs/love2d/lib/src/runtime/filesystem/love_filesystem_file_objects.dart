part of 'love_filesystem_runtime.dart';

class _LoveReadableHandle {
  const _LoveReadableHandle({required this.device, this.path});

  final IODevice device;
  final String? path;
}

String _filesystemAdapterErrorMessage(Object error) {
  return switch (error) {
    StateError(:final message) => message,
    UnsupportedError(:final message?) => message,
    ArgumentError(:final message?) when message != null => '$message',
    _ => '$error',
  }.trim();
}

StateError _openFileStateError(String logicalPath, Object error) {
  final message = _filesystemAdapterErrorMessage(error);
  if (message.isEmpty) {
    return StateError('Could not open file $logicalPath.');
  }

  if (message.startsWith('Could not open file ') ||
      message == 'Could not set write directory.') {
    return StateError(message);
  }

  return StateError('Could not open file $logicalPath ($message)');
}

Future<IODevice> _openFilesystemDeviceOrThrow(
  LoveFilesystemAdapter adapter,
  String physicalPath,
  String mode, {
  required String logicalPath,
}) async {
  try {
    return await adapter.openFile(physicalPath, mode);
  } catch (error) {
    throw _openFileStateError(logicalPath, error);
  }
}

int _normalizeLoveBufferSize(BufferMode mode, int size) {
  if (size < 0) {
    return size;
  }

  return mode == BufferMode.none ? 0 : size;
}

class LoveFilesystemFile {
  LoveFilesystemFile({required this.state, required this.filename});

  final LoveFilesystemState state;
  final String filename;

  IODevice? _device;
  String _mode = 'c';
  BufferMode _bufferMode = BufferMode.none;
  int _bufferSize = 0;
  String? _openedPath;

  bool get isOpen => _device != null;

  String get mode => _mode;

  String? get openedPath => _openedPath;

  BufferMode get bufferMode => _bufferMode;

  int get bufferSize => _bufferSize;

  String get extension {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex + 1);
  }

  Future<bool> open(String mode) async {
    if (mode == 'c') {
      return true;
    }

    if (isOpen) {
      return false;
    }

    late final IODevice device;
    String? openedPath;

    if (mode == 'r') {
      final readable = await state._openReadable(filename);
      if (readable == null) {
        throw StateError('Could not open file $filename. Does not exist.');
      }
      device = readable.device;
      openedPath = readable.path;
    } else {
      final physicalPath = await state.resolveWritablePhysicalPath(filename);
      if (physicalPath == null) {
        throw StateError('Could not set write directory.');
      }

      if (!await state._ensureSaveDirectoryExists()) {
        throw StateError('Could not set write directory.');
      }

      final parent = path.dirname(physicalPath);
      final saveDirectory = state.getSaveDirectory();
      if (path.normalize(parent) != path.normalize(saveDirectory) &&
          !await state.adapter.directoryExists(parent)) {
        throw StateError('Could not open file $filename.');
      }

      device = await _openFilesystemDeviceOrThrow(
        state.adapter,
        physicalPath,
        mode,
        logicalPath: filename,
      );
      openedPath = physicalPath;
    }

    final effectiveBufferSize = _normalizeLoveBufferSize(
      _bufferMode,
      _bufferSize,
    );
    try {
      await device.setBuffering(_bufferMode, effectiveBufferSize);
      _bufferSize = effectiveBufferSize;
    } catch (_) {
      _bufferMode = BufferMode.none;
      _bufferSize = 0;
    }

    _device = device;
    _mode = mode;
    _openedPath = openedPath;
    if (openedPath != null) {
      state._registerOpenPath(openedPath);
    }
    return true;
  }

  Future<bool> close() async {
    final device = _device;
    if (device == null) {
      return false;
    }

    try {
      await device.close();
    } catch (_) {
      return false;
    }
    final openedPath = _openedPath;
    if (openedPath != null) {
      state._unregisterOpenPath(openedPath);
    }
    _device = null;
    _mode = 'c';
    _openedPath = null;
    return true;
  }

  Future<List<int>> readBytes([int size = -1]) async {
    final wasOpen = isOpen;
    if (wasOpen && _mode != 'r') {
      throw StateError('File is not opened for reading.');
    }
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      final device = _device!;
      final result = await device.read(size < 0 ? 'a' : '$size');
      if (!result.isSuccess) {
        throw StateError(result.error ?? 'Could not read from file.');
      }
      if (result.value == null && size == 0) {
        return const <int>[];
      }

      return _bytesFromIODeviceValue(result.value);
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }

  Future<List<int>?> readLineBytes({bool includeLineTerminator = false}) async {
    final wasOpen = isOpen;
    if (wasOpen && _mode != 'r') {
      throw StateError('File is not opened for reading.');
    }
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      final device = _device!;
      final result = await device.read(includeLineTerminator ? 'L' : 'l');
      if (!result.isSuccess) {
        throw StateError(result.error ?? 'Could not read from file.');
      }

      final value = result.value;
      if (value == null) {
        return null;
      }

      return _bytesFromIODeviceValue(value);
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }

  Future<bool> writeBytes(List<int> bytes) async {
    final device = _device;
    if (device == null || (_mode != 'w' && _mode != 'a')) {
      throw StateError('File is not opened for writing.');
    }

    final result = await device.writeBytes(bytes);
    if (!result.success) {
      if (result.error != null && result.error!.isNotEmpty) {
        throw StateError(result.error!);
      }
      return false;
    }

    return true;
  }

  Future<bool> flush() async {
    final device = _device;
    if (device == null || (_mode != 'w' && _mode != 'a')) {
      throw StateError('File is not opened for writing.');
    }

    try {
      await device.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEOF() async {
    final device = _device;
    if (device == null) {
      return true;
    }

    return device.isEOF();
  }

  Future<int> tell() async {
    final device = _device;
    if (device == null) {
      return -1;
    }

    return device.getPosition();
  }

  Future<bool> seek(int position) async {
    final device = _device;
    if (device == null || position < 0) {
      return false;
    }

    await device.seek(SeekWhence.set, position);
    return true;
  }

  Future<bool> setBuffer(BufferMode mode, int size) async {
    if (size < 0) {
      return false;
    }

    final isOpen = _device != null;
    final effectiveSize = isOpen ? _normalizeLoveBufferSize(mode, size) : size;

    final device = _device;
    if (device != null) {
      try {
        await device.setBuffering(mode, effectiveSize);
      } catch (_) {
        return false;
      }
    }

    _bufferMode = mode;
    _bufferSize = effectiveSize;
    return true;
  }

  Future<int?> getSize() async {
    final wasOpen = isOpen;
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      final openedPath = _openedPath;
      if (openedPath != null) {
        return state.adapter.fileSize(openedPath);
      }

      return (await state.getInfo(
        filename,
        filterType: LoveFilesystemNodeType.file,
      ))?.size;
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }
}

class LoveFilesystemDroppedFile extends LoveFilesystemFile {
  LoveFilesystemDroppedFile({required super.state, required String filename})
    : super(filename: path.normalize(filename));

  String get physicalPath => filename;

  @override
  Future<bool> open(String mode) async {
    if (mode == 'c') {
      return true;
    }

    if (isOpen) {
      return false;
    }

    late final IODevice device;
    if (mode == 'r') {
      if (!await state.adapter.fileExists(physicalPath)) {
        throw StateError('Could not open file $physicalPath. Does not exist.');
      }
      try {
        device = await state.adapter.openFile(physicalPath, mode);
      } catch (_) {
        throw StateError('Could not open file $physicalPath. Does not exist.');
      }
    } else {
      try {
        device = await state.adapter.openFile(physicalPath, mode);
      } catch (_) {
        _mode = mode;
        return false;
      }
    }

    final effectiveBufferSize = _normalizeLoveBufferSize(
      bufferMode,
      bufferSize,
    );
    try {
      await device.setBuffering(bufferMode, effectiveBufferSize);
      _bufferSize = effectiveBufferSize;
    } catch (_) {
      _bufferMode = BufferMode.none;
      _bufferSize = 0;
    }

    _device = device;
    _mode = mode;
    _openedPath = physicalPath;
    return true;
  }

  @override
  Future<bool> setBuffer(BufferMode mode, int size) async {
    if (size < 0) {
      return false;
    }

    final effectiveSize = _normalizeLoveBufferSize(mode, size);

    final device = _device;
    if (device != null) {
      try {
        await device.setBuffering(mode, effectiveSize);
      } catch (_) {
        return false;
      }
    }

    _bufferMode = mode;
    _bufferSize = effectiveSize;
    return true;
  }

  @override
  Future<int?> getSize() async {
    final wasOpen = isOpen;
    if (!wasOpen) {
      final opened = await open('r');
      if (!opened) {
        throw StateError('Could not open file.');
      }
    }

    try {
      return state.adapter.fileSize(physicalPath);
    } finally {
      if (!wasOpen) {
        await close();
      }
    }
  }
}
