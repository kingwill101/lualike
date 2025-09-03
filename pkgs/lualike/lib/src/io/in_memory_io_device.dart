/// Simple in-memory IODevice implementation for direct assignment
library;

import 'package:lualike/lualike.dart';
import 'io_device.dart';

/// Simple in-memory IODevice that can be used directly
/// Usage: IOLib.fileSystemProvider.ioDevice = InMemoryIODevice()
class InMemoryIODevice extends BaseIODevice {
  final Map<String, String> _files = {};
  String? _currentFile;
  String _currentContent = '';
  int _position = 0;
  final StringBuffer _writeBuffer = StringBuffer();

  InMemoryIODevice() : super("r+");

  /// Set the current file content for operations
  void setFileContent(String filename, String content) {
    _files[filename] = content;
    Logger.debug(
      'Set content for file: $filename (${content.length} chars)',
      category: 'InMemoryIO',
    );
  }

  /// Get the content of a file
  String? getFileContent(String filename) {
    return _files[filename];
  }

  /// Open a file for operations (simulated)
  void openFile(String filename, [String mode = "r+"]) {
    _currentFile = filename;
    _currentContent = _files[filename] ?? '';
    _position = 0;
    _writeBuffer.clear();
    isClosed = false;

    // For append mode, start at the end
    if (mode.contains('a')) {
      _position = _currentContent.length;
    }

    Logger.debug(
      'Opened file: $filename with mode: $mode',
      category: 'InMemoryIO',
    );
  }

  @override
  Future<void> close() async {
    if (!isClosed && _currentFile != null) {
      await flush();
      isClosed = true;
      Logger.debug('Closed file: $_currentFile', category: 'InMemoryIO');
    }
  }

  @override
  Future<void> flush() async {
    checkOpen();
    if (_writeBuffer.isNotEmpty && _currentFile != null) {
      if (mode.contains('a')) {
        // Append mode
        _files[_currentFile!] = _currentContent + _writeBuffer.toString();
      } else {
        // Write/read+ mode - replace content at current position
        final before = _currentContent.substring(
          0,
          _position.clamp(0, _currentContent.length),
        );
        final newContent = _writeBuffer.toString();
        final after = _position + newContent.length < _currentContent.length
            ? _currentContent.substring(_position + newContent.length)
            : '';
        _files[_currentFile!] = before + newContent + after;
      }
      _currentContent = _files[_currentFile!]!;
      _writeBuffer.clear();
      Logger.debug('Flushed file: $_currentFile', category: 'InMemoryIO');
    }
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    checkOpen();
    validateReadFormat(format);

    final normalizedFormat = normalizeReadFormat(format);

    try {
      if (normalizedFormat == "a") {
        // Read entire remaining content
        final result = _currentContent.substring(
          _position.clamp(0, _currentContent.length),
        );
        _position = _currentContent.length;
        return ReadResult(result);
      } else if (normalizedFormat == "l" || normalizedFormat == "L") {
        // Read line
        if (_position >= _currentContent.length) {
          return ReadResult(null); // EOF
        }

        final lineEnd = _currentContent.indexOf('\n', _position);
        if (lineEnd == -1) {
          // No more newlines, read to end
          final result = _currentContent.substring(_position);
          _position = _currentContent.length;
          return ReadResult(result.isEmpty ? null : result);
        }

        final result = _currentContent.substring(_position, lineEnd);
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
        if (_position >= _currentContent.length) {
          return ReadResult(null); // EOF
        }

        final endPos = (_position + n).clamp(0, _currentContent.length);
        final result = _currentContent.substring(_position, endPos);
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
    try {
      _writeBuffer.write(data);
      return WriteResult(true);
    } catch (e) {
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    final contentLength = _currentContent.length;

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
    return _position >= _currentContent.length;
  }

  /// Clear all in-memory files (for testing/debugging)
  void clearAllFiles() {
    _files.clear();
    _currentContent = '';
    _position = 0;
    _writeBuffer.clear();
    Logger.debug('Cleared all in-memory files', category: 'InMemoryIO');
  }

  /// Get all files (for debugging)
  Map<String, String> getAllFiles() {
    return Map.from(_files);
  }

  /// List all file names
  List<String> getFileNames() {
    return _files.keys.toList();
  }
}
