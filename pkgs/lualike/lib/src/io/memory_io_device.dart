/// In-memory IODevice implementation for testing and non-persistent storage
library;

import 'package:lualike/lualike.dart';
import 'io_device.dart';

// Global storage for in-memory files
final Map<String, String> _globalMemoryFiles = {};

/// Factory function for creating InMemory IODevices
/// Usage: IOLib.fileSystemProvider.setIODeviceFactory(createInMemoryIODevice)
Future<IODevice> createInMemoryIODevice(String path, String mode) async {
  // For write modes, ensure the file exists (can be empty)
  if (mode.contains('w') && !_globalMemoryFiles.containsKey(path)) {
    _globalMemoryFiles[path] = '';
  }

  // For read modes, check if file exists
  if (mode.contains('r') && !_globalMemoryFiles.containsKey(path)) {
    throw LuaError("File not found: $path");
  }

  return InMemoryIODevice(path, mode, _globalMemoryFiles);
}

/// In-memory IODevice implementation
class InMemoryIODevice extends BaseIODevice {
  final String _path;
  final Map<String, String> _fileSystem;
  int _position = 0;
  final StringBuffer _writeBuffer = StringBuffer();

  InMemoryIODevice(this._path, String mode, this._fileSystem) : super(mode);

  @override
  Future<void> close() async {
    if (!isClosed) {
      await flush();
      isClosed = true;
    }
  }

  @override
  Future<void> flush() async {
    checkOpen();
    if (_writeBuffer.isNotEmpty) {
      final currentContent = _fileSystem[_path] ?? '';
      if (mode.contains('w') && !mode.contains('+')) {
        // Write mode - replace entire content
        _fileSystem[_path] = _writeBuffer.toString();
      } else if (mode.contains('a')) {
        // Append mode
        _fileSystem[_path] = currentContent + _writeBuffer.toString();
      } else {
        // Other modes with writing
        _fileSystem[_path] = currentContent + _writeBuffer.toString();
      }
      _writeBuffer.clear();
    }
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    checkOpen();
    validateReadFormat(format);

    final content = _fileSystem[_path] ?? '';
    final normalizedFormat = normalizeReadFormat(format);

    try {
      if (normalizedFormat == "a") {
        // Read entire remaining content
        final result = content.substring(_position.clamp(0, content.length));
        _position = content.length;
        return ReadResult(result);
      } else if (normalizedFormat == "l" || normalizedFormat == "L") {
        // Read line
        if (_position >= content.length) {
          return ReadResult(null); // EOF
        }

        final lineEnd = content.indexOf('\n', _position);
        if (lineEnd == -1) {
          // No more newlines, read to end
          final result = content.substring(_position);
          _position = content.length;
          return ReadResult(result.isEmpty ? null : result);
        }

        final result = content.substring(_position, lineEnd);
        _position = lineEnd + 1;
        return ReadResult(normalizedFormat == "L" ? "$result\n" : result);
      } else if (normalizedFormat == "n") {
        // Read number - first read a line, then parse
        final line = await read("l");
        if (!line.isSuccess || line.value == null) {
          return line;
        }
        final number = num.tryParse(line.value as String);
        return ReadResult(number);
      } else {
        // Read n bytes
        final n = int.parse(normalizedFormat);
        if (_position >= content.length) {
          return ReadResult(null); // EOF
        }

        final endPos = (_position + n).clamp(0, content.length);
        final result = content.substring(_position, endPos);
        _position = endPos;
        return ReadResult(result);
      }
    } catch (e) {
      return ReadResult(null, e.toString());
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    if (!mode.contains('w') && !mode.contains('a') && !mode.contains('+')) {
      return WriteResult(false, "File not open for writing");
    }

    try {
      _writeBuffer.write(data);
      return WriteResult(true);
    } catch (e) {
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    if (!mode.contains('w') && !mode.contains('a') && !mode.contains('+')) {
      return WriteResult(false, "File not open for writing");
    }
    try {
      _writeBuffer.write(String.fromCharCodes(bytes));
      return WriteResult(true);
    } catch (e) {
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    final content = _fileSystem[_path] ?? '';
    final contentLength = content.length;

    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, contentLength);
        break;
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, contentLength);
        break;
      case SeekWhence.end:
        _position = (contentLength + offset).clamp(0, contentLength);
        break;
    }

    return _position;
  }

  @override
  Future<int> getPosition() async {
    checkOpen();
    return _position;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    final content = _fileSystem[_path] ?? '';
    return _position >= content.length;
  }

  /// Clear all in-memory files (for testing/debugging)
  static void clearMemoryStorage() {
    _globalMemoryFiles.clear();
  }

  /// Get all files in memory storage (for debugging)
  static Map<String, String> getMemoryStorage() {
    return Map.from(_globalMemoryFiles);
  }
}
