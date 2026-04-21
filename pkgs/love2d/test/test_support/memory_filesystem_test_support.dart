import 'package:lualike/lualike.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

const String loveTestMountedSourceRoot = 'game';

Map<String, List<int>> mountLoveTestFiles(
  Map<String, List<int>> files, {
  String sourceRoot = loveTestMountedSourceRoot,
}) {
  return Map<String, List<int>>.unmodifiable(
    files.map(
      (path, bytes) => MapEntry(
        '$sourceRoot/$path',
        List<int>.unmodifiable(bytes),
      ),
    ),
  );
}

class MemoryLoveFilesystemAdapter implements LoveFilesystemAdapter {
  MemoryLoveFilesystemAdapter({required Map<String, List<int>> files})
    : files = Map<String, List<int>>.unmodifiable(
        files.map(
          (path, bytes) => MapEntry(path, List<int>.unmodifiable(bytes)),
        ),
      );

  final Map<String, List<int>> files;

  @override
  String? get appdataDirectory => null;

  @override
  String? get executablePath => null;

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;

  @override
  String? get userDirectory => null;

  @override
  String? get workingDirectory => null;

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      true;

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<bool> directoryExists(String path) async {
    final normalizedPath = path.endsWith('/') ? path : '$path/';
    return files.keys.any((key) => key.startsWith(normalizedPath));
  }

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<int?> fileSize(String path) async => files[path]?.length;

  @override
  Future<List<String>> listDirectory(String path) async {
    final normalizedPath = path.endsWith('/') ? path : '$path/';
    final entries = <String>{};
    for (final key in files.keys) {
      if (!key.startsWith(normalizedPath)) {
        continue;
      }

      final remainder = key.substring(normalizedPath.length);
      if (remainder.isEmpty) {
        continue;
      }

      final separatorIndex = remainder.indexOf('/');
      entries.add(
        separatorIndex < 0 ? remainder : remainder.substring(0, separatorIndex),
      );
    }

    return entries.toList()..sort();
  }

  @override
  Future<DateTime?> modified(String path) async => null;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final bytes = files[path];
    if (mode == 'r' && bytes != null) {
      return _MemoryReadIODevice(bytes);
    }

    throw UnsupportedError('openFile only supports read mode in this test');
  }

  @override
  Future<List<int>?> readFileBytes(String path) async => files[path];
}

class _MemoryReadIODevice extends BaseIODevice {
  _MemoryReadIODevice(List<int> bytes)
    : _bytes = List<int>.unmodifiable(bytes),
      super('r') {
    isClosed = false;
  }

  final List<int> _bytes;
  int _position = 0;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
  }

  @override
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    validateReadFormat(format);

    final normalized = normalizeReadFormat(format);
    if (normalized == 'a') {
      final chunk = _bytes.sublist(_position.clamp(0, _bytes.length));
      _position = _bytes.length;
      return ReadResult(LuaString.fromBytes(chunk));
    }

    if (normalized == 'l' || normalized == 'L') {
      if (_position >= _bytes.length) {
        return ReadResult(null);
      }

      var end = _position;
      while (end < _bytes.length && _bytes[end] != 10) {
        end++;
      }

      final includeTerminator = normalized == 'L' && end < _bytes.length;
      final line = _bytes.sublist(_position, includeTerminator ? end + 1 : end);
      _position = end < _bytes.length ? end + 1 : _bytes.length;
      return ReadResult(LuaString.fromBytes(line));
    }

    if (normalized == 'n') {
      return ReadResult(null, 'number reads are not supported in this test');
    }

    final count = int.parse(normalized);
    if (_position >= _bytes.length) {
      return ReadResult(null);
    }

    final end = (_position + count).clamp(0, _bytes.length);
    final chunk = _bytes.sublist(_position, end);
    _position = end;
    return ReadResult(LuaString.fromBytes(chunk));
  }

  @override
  Future<WriteResult> write(String data) async =>
      WriteResult(false, 'File not open for writing');

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async =>
      WriteResult(false, 'File not open for writing');

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, _bytes.length);
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, _bytes.length);
      case SeekWhence.end:
        _position = (_bytes.length + offset).clamp(0, _bytes.length);
    }
    return _position;
  }

  @override
  Future<void> setBuffering(BufferMode mode, [int? size]) async {}

  @override
  Future<int> getPosition() async {
    checkOpen();
    return _position;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    return _position >= _bytes.length;
  }
}
