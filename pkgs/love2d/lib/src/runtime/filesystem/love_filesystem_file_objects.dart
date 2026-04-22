part of 'love_filesystem_runtime.dart';

/// A readable filesystem handle resolved from either a physical or virtual
/// filesystem node.
class _LoveReadableHandle {
  /// Creates a readable handle for [device] and its optional physical [path].
  const _LoveReadableHandle({required this.device, this.path});

  /// The device used to read the resolved file contents.
  final IODevice device;

  /// The physical host path backing [device], when one exists.
  final String? path;
}

/// Normalizes adapter exceptions to the message format expected by LOVE file
/// operations.
String _filesystemAdapterErrorMessage(Object error) {
  return switch (error) {
    StateError(:final message) => message,
    UnsupportedError(:final message?) => message,
    ArgumentError(:final message?) when message != null => '$message',
    _ => '$error',
  }.trim();
}

/// Wraps adapter failures for [logicalPath] in a LOVE-style [StateError].
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

/// Opens [physicalPath] through [adapter] and converts host errors to
/// filesystem [StateError]s.
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

/// Normalizes LOVE buffer sizes for [mode].
///
/// Unbuffered mode always uses a size of `0`.
int _normalizeLoveBufferSize(BufferMode mode, int size) {
  if (size < 0) {
    return size;
  }

  return mode == BufferMode.none ? 0 : size;
}

/// A LOVE filesystem file object backed by the runtime state.
class LoveFilesystemFile {
  /// Creates a file object for the logical [filename].
  LoveFilesystemFile({required this.state, required this.filename});

  /// The filesystem runtime that resolves this file's logical path.
  final LoveFilesystemState state;

  /// The logical file path exposed to Lua.
  final String filename;

  /// The active IO device when this file is open.
  IODevice? _device;

  /// The current LOVE file mode, or `'c'` when the file is closed.
  String _mode = 'c';

  /// The configured buffering mode for future opens.
  BufferMode _bufferMode = BufferMode.none;

  /// The configured buffering size for future opens.
  int _bufferSize = 0;

  /// The currently opened host path, when the file is backed by a physical
  /// file.
  String? _openedPath;

  /// Whether this file currently has an open IO device.
  bool get isOpen => _device != null;

  /// The current LOVE file mode.
  String get mode => _mode;

  /// The physical host path currently opened for this file, if any.
  String? get openedPath => _openedPath;

  /// The buffering mode that will be applied to the underlying device.
  BufferMode get bufferMode => _bufferMode;

  /// The buffering size that will be applied to the underlying device.
  int get bufferSize => _bufferSize;

  /// The filename extension without a leading dot.
  String get extension {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex + 1);
  }

  /// Opens this file in LOVE [mode].
  ///
  /// Returns `false` when the file is already open. Throws a [StateError] when
  /// the target path cannot be resolved or opened.
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

  /// Closes the open device for this file.
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

  /// Reads up to [size] bytes from this file.
  ///
  /// Opens the file temporarily in read mode when needed.
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

  /// Reads the next line from this file as bytes.
  ///
  /// Returns `null` at end of file.
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

  /// Writes [bytes] to this file.
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

  /// Flushes buffered writes to the underlying device.
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

  /// Whether the underlying device is at end of file.
  Future<bool> isEOF() async {
    final device = _device;
    if (device == null) {
      return true;
    }

    return device.isEOF();
  }

  /// The current read or write position, or `-1` when the file is closed.
  Future<int> tell() async {
    final device = _device;
    if (device == null) {
      return -1;
    }

    return device.getPosition();
  }

  /// Seeks to [position] from the start of the file.
  Future<bool> seek(int position) async {
    final device = _device;
    if (device == null || position < 0) {
      return false;
    }

    await device.seek(SeekWhence.set, position);
    return true;
  }

  /// Configures buffering for this file.
  ///
  /// When the file is already open, the buffering settings are applied
  /// immediately to the current device.
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

  /// Returns the file size in bytes, if it can be resolved.
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

/// A file object representing a dropped host file outside the mounted runtime
/// filesystem.
class LoveFilesystemDroppedFile extends LoveFilesystemFile {
  /// Creates a dropped-file wrapper for the host [filename].
  LoveFilesystemDroppedFile({required super.state, required String filename})
    : super(filename: path.normalize(filename));

  /// The normalized physical path of the dropped file.
  String get physicalPath => filename;

  @override
  /// Opens this dropped file directly from the host filesystem.
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
  /// Configures buffering for the dropped-file device.
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
  /// Returns the size of the dropped host file.
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
