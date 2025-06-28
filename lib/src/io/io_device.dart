import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:lualike/lualike.dart';

/// Represents the result of a read operation
class ReadResult {
  final Object? value;
  final String? error;
  final int? errorCode;

  ReadResult(this.value, [this.error, this.errorCode]) {
    Logger.debug(
      'ReadResult created: value=${value?.toString() ?? "null"}, error=${error ?? "null"}, errorCode=${errorCode ?? "null"}',
      category: 'IO',
    );
  }

  bool get isSuccess => error == null;

  /// Convert to Lua-style error tuple
  List<Object?> toLua() {
    final result = error != null ? [null, error, errorCode] : [value];
    Logger.debug('ReadResult toLua: $result', category: 'IO');
    return result;
  }
}

/// Represents the result of a write operation
class WriteResult {
  final bool success;
  final String? error;
  final int? errorCode;

  WriteResult(this.success, [this.error, this.errorCode]) {
    Logger.debug(
      'WriteResult created: success=$success, error=${error ?? "null"}, errorCode=${errorCode ?? "null"}',
      category: 'IO',
    );
  }

  /// Convert to Lua-style error tuple
  List<Object?> toLua() {
    final result = success ? [true] : [null, error, errorCode];
    Logger.debug('WriteResult toLua: $result', category: 'IO');
    return result;
  }
}

/// Represents a seek position in a file
enum SeekWhence {
  set, // Offset from start
  cur, // Offset from current position
  end, // Offset from end
}

/// Represents buffering modes for IO operations
enum BufferMode {
  none, // No buffering
  line, // Line buffering
  full, // Full buffering
}

/// Abstract interface for IO devices
abstract class IODevice {
  /// Whether the device is closed
  bool get isClosed;

  /// The mode this device was opened in (r, w, a, etc.)
  String get mode;

  /// Close the device
  Future<void> close();

  /// Flush any buffered data
  Future<void> flush();

  /// Read from the device according to the given format
  /// format can be:
  /// - "n" for number
  /// - "a" for the entire content
  /// - "l" for a line (default)
  /// - "L" for a line including the end-of-line character
  /// - A number for that many bytes
  Future<ReadResult> read([String format = "l"]);

  /// Write data to the device
  Future<WriteResult> write(String data);

  /// Seek to a position in the device
  /// Returns the new position
  Future<int> seek(SeekWhence whence, int offset);

  /// Set the buffering mode and optionally the buffer size
  Future<void> setBuffering(BufferMode mode, [int? size]);

  /// Get the current position in the device
  Future<int> getPosition();

  /// Check if we're at the end of the device
  Future<bool> isEOF();
}

/// Base implementation with common functionality
abstract class BaseIODevice implements IODevice {
  @override
  bool isClosed = false;

  @override
  final String mode;

  BufferMode bufferMode = BufferMode.full;
  int bufferSize = 8192;

  BaseIODevice(this.mode) {
    Logger.debug('Created BaseIODevice with mode: $mode', category: 'IO');
  }

  @override
  Future<void> setBuffering(BufferMode mode, [int? size]) async {
    Logger.debug(
      'Setting buffering: mode=$mode, size=${size ?? bufferSize}',
      category: 'IO',
    );
    bufferMode = mode;
    if (size != null) bufferSize = size;
  }

  /// Helper to ensure device is open before operations
  void checkOpen() {
    Logger.debug(
      'Checking if device is open (isClosed=$isClosed)',
      category: 'IO',
    );
    if (isClosed) {
      Logger.debug('Device is closed, throwing exception', category: 'IO');
      throw Exception("attempt to use a closed file");
    }
  }

  /// Helper to validate read format
  void validateReadFormat(String format) {
    Logger.debug("Validating read format: $format", category: "IO");
    if (!RegExp(r'^(n|a|l|L|\d+)$').hasMatch(format)) {
      Logger.debug("Invalid format: $format", category: "IO");
      throw LuaError("invalid format: $format");
    }
    Logger.debug("Format $format is valid", category: "IO");
  }
}

/// Implementation for real files using dart:io
class FileIODevice extends BaseIODevice {
  RandomAccessFile? _file;

  FileIODevice._(RandomAccessFile file, String mode) : super(mode) {
    _file = file;
    Logger.debug('Created FileIODevice with mode: $mode', category: 'IO');
  }

  static Future<FileIODevice> open(String path, String mode) async {
    Logger.debug('Opening file: $path with mode: $mode', category: 'IO');
    FileMode fileMode;
    switch (mode) {
      case "r":
        fileMode = FileMode.read;
        break;
      case "w":
        fileMode = FileMode.write;
        break;
      case "a":
        fileMode = FileMode.append;
        break;
      case "r+":
        fileMode = FileMode.append;
        break;
      case "w+":
        fileMode = FileMode.writeOnly;
        break;
      case "a+":
        fileMode = FileMode.append;
        break;
      default:
        Logger.debug('Invalid file mode: $mode', category: 'IO');
        throw Exception("Invalid file mode: $mode");
    }

    try {
      Logger.debug('Attempting to open file: $path', category: 'IO');
      final file = await File(path).open(mode: fileMode);
      Logger.debug('Successfully opened file: $path', category: 'IO');
      return FileIODevice._(file, mode);
    } catch (e) {
      Logger.debug('Failed to open file: $path, error: $e', category: 'IO');
      throw Exception("Could not open file: $e");
    }
  }

  @override
  Future<void> close() async {
    Logger.debug('Closing file', category: 'IO');
    if (!isClosed && _file != null) {
      await _file!.close();
      _file = null;
      isClosed = true;
      Logger.debug('File closed successfully', category: 'IO');
    } else {
      Logger.debug('File already closed or null', category: 'IO');
    }
  }

  @override
  Future<void> flush() async {
    Logger.debug('Flushing file', category: 'IO');
    checkOpen();
    await _file?.flush();
    Logger.debug('File flushed successfully', category: 'IO');
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    Logger.debug('Reading file with format: $format', category: 'IO');
    checkOpen();
    validateReadFormat(format);

    try {
      if (format == "a") {
        // Read entire file
        Logger.debug('Reading entire file', category: 'IO');
        final length = await _file!.length();
        Logger.debug('File length: $length bytes', category: 'IO');
        final bytes = await _file!.read(length);
        Logger.debug('Read ${bytes.length} bytes from file', category: 'IO');
        final result = utf8.decode(bytes);
        Logger.debug('Decoded ${result.length} characters', category: 'IO');
        return ReadResult(result);
      } else if (format == "l" || format == "L") {
        // Read line
        Logger.debug('Reading line from file', category: 'IO');
        final buffer = <int>[];
        int byte;
        while ((byte = await _file!.readByte()) != -1) {
          if (byte == 10) {
            // \n
            Logger.debug('Found newline character', category: 'IO');
            if (format == "L") buffer.add(byte);
            break;
          }
          buffer.add(byte);
        }
        Logger.debug('Read ${buffer.length} bytes for line', category: 'IO');
        if (buffer.isEmpty) {
          Logger.debug('Read empty line (EOF)', category: 'IO');
          return ReadResult(null);
        }
        final result = utf8.decode(buffer);
        Logger.debug('Decoded line: "$result"', category: 'IO');
        return ReadResult(result);
      } else if (format == "n") {
        // Read number
        Logger.debug('Reading number from file', category: 'IO');
        final line = await read("l");
        if (!line.isSuccess || line.value == null) {
          Logger.debug('Failed to read line for number', category: 'IO');
          return line;
        }
        Logger.debug('Parsing "${line.value}" as number', category: 'IO');
        final number = num.tryParse(line.value as String);
        if (number == null) {
          Logger.debug('Failed to parse as number', category: 'IO');
        } else {
          Logger.debug('Parsed number: $number', category: 'IO');
        }
        return ReadResult(number);
      } else {
        // Read n bytes
        final n = int.parse(format);
        Logger.debug('Reading $n bytes from file', category: 'IO');
        final bytes = await _file!.read(n);
        Logger.debug('Read ${bytes.length} bytes', category: 'IO');
        final result = utf8.decode(bytes);
        Logger.debug('Decoded ${result.length} characters', category: 'IO');
        return ReadResult(result);
      }
    } catch (e) {
      Logger.debug('Error reading from file: $e', category: 'IO');
      return ReadResult(null, e.toString());
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    Logger.debug(
      'Writing to file: "${data.length} characters"',
      category: 'IO',
    );
    checkOpen();
    try {
      final bytes = utf8.encode(data);
      Logger.debug('Encoded ${bytes.length} bytes to write', category: 'IO');
      await _file!.writeFrom(bytes);
      Logger.debug('Successfully wrote ${bytes.length} bytes', category: 'IO');
      return WriteResult(true);
    } catch (e) {
      Logger.debug('Error writing to file: $e', category: 'IO');
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    Logger.debug(
      'Seeking in file: whence=$whence, offset=$offset',
      category: 'IO',
    );
    checkOpen();
    switch (whence) {
      case SeekWhence.set:
        Logger.debug('Seeking to absolute position: $offset', category: 'IO');
        await _file!.setPosition(offset);
        final pos = await _file!.position();
        Logger.debug('New position: $pos', category: 'IO');
        return pos;
      case SeekWhence.cur:
        final currentPos = await _file!.position();
        Logger.debug('Current position: $currentPos', category: 'IO');
        final newPos = currentPos + offset;
        Logger.debug('Seeking to relative position: $newPos', category: 'IO');
        await _file!.setPosition(newPos);
        final pos = await _file!.position();
        Logger.debug('New position: $pos', category: 'IO');
        return pos;
      case SeekWhence.end:
        final length = await _file!.length();
        Logger.debug('File length: $length', category: 'IO');
        final newPos = length + offset;
        Logger.debug(
          'Seeking to end-relative position: $newPos',
          category: 'IO',
        );
        await _file!.setPosition(newPos);
        final pos = await _file!.position();
        Logger.debug('New position: $pos', category: 'IO');
        return pos;
    }
  }

  @override
  Future<int> getPosition() async {
    Logger.debug('Getting file position', category: 'IO');
    checkOpen();
    final pos = await _file!.position();
    Logger.debug('Current position: $pos', category: 'IO');
    return pos;
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug('Checking if at EOF', category: 'IO');
    checkOpen();
    final pos = await _file!.position();
    final length = await _file!.length();
    final isAtEnd = pos >= length;
    Logger.debug(
      'Position: $pos, Length: $length, EOF: $isAtEnd',
      category: 'IO',
    );
    return isAtEnd;
  }
}

/// Implementation for stdin
class StdinDevice extends BaseIODevice {
  StdinDevice() : super("r") {
    Logger.debug('Created StdinDevice', category: 'IO');
  }

  @override
  Future<void> close() async {
    Logger.debug('Closing StdinDevice', category: 'IO');
    isClosed = true;
    Logger.debug('StdinDevice closed', category: 'IO');
  }

  @override
  Future<void> flush() async {
    Logger.debug('Flush called on StdinDevice (no-op)', category: 'IO');
    // No-op for stdin
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    Logger.debug('Reading from stdin with format: $format', category: 'IO');
    checkOpen();
    validateReadFormat(format);

    try {
      if (format == "l" || format == "L") {
        Logger.debug('Reading line from stdin', category: 'IO');
        final line = stdin.readLineSync(encoding: utf8);
        if (line == null) {
          Logger.debug('Read null line from stdin (EOF)', category: 'IO');
          return ReadResult(null);
        }
        final result = format == "L" ? "$line\n" : line;
        Logger.debug('Read line from stdin: "$result"', category: 'IO');
        return ReadResult(result);
      } else if (format == "a") {
        // Read until EOF
        Logger.debug(
          'Reading all content from stdin until EOF',
          category: 'IO',
        );
        final buffer = StringBuffer();
        String? line;
        int lineCount = 0;
        while ((line = stdin.readLineSync(encoding: utf8)) != null) {
          buffer.writeln(line);
          lineCount++;
        }
        Logger.debug('Read $lineCount lines from stdin', category: 'IO');
        final result = buffer.toString();
        Logger.debug(
          'Read ${result.length} characters from stdin',
          category: 'IO',
        );
        return ReadResult(result);
      } else if (format == "n") {
        Logger.debug('Reading number from stdin', category: 'IO');
        final line = await read("l");
        if (!line.isSuccess || line.value == null) {
          Logger.debug(
            'Failed to read line for number from stdin',
            category: 'IO',
          );
          return line;
        }
        final inputStr = line.value as String;
        Logger.debug('Parsing "$inputStr" as number', category: 'IO');
        final number = num.tryParse(inputStr);
        if (number == null) {
          Logger.debug('Failed to parse as number', category: 'IO');
        } else {
          Logger.debug('Parsed number: $number', category: 'IO');
        }
        return ReadResult(number);
      } else {
        throw LuaError("Unsupported format for stdin: $format");
      }
    } catch (e) {
      return ReadResult(null, e.toString());
    }
  }

  @override
  Future<WriteResult> write(String data) async {
    return WriteResult(false, "Cannot write to stdin");
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    throw UnsupportedError("Cannot seek in stdin");
  }

  @override
  Future<int> getPosition() async {
    throw UnsupportedError("Cannot get position in stdin");
  }

  @override
  Future<bool> isEOF() async {
    try {
      return stdin.readLineSync() == null;
    } catch (e) {
      return true; // If we can't read, treat as EOF
    }
  }
}

/// Implementation for stdout/stderr with configurable flushing
class StdoutDevice extends BaseIODevice {
  final IOSink _sink;
  final bool _allowFlush;
  static final Map<IOSink, StdoutDevice> _instances = {};
  final Object _lock = Object(); // Lock for synchronization

  // Use a factory constructor to ensure singleton instances
  factory StdoutDevice(IOSink sink, {bool? allowFlush}) {
    if (!_instances.containsKey(sink)) {
      final allowFlushValue = allowFlush ?? LuaLikeConfig().flushAfterPrint;
      _instances[sink] = StdoutDevice._internal(sink, allowFlushValue);
    }
    return _instances[sink]!;
  }

  StdoutDevice._internal(this._sink, this._allowFlush) : super("w");

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
    if (_allowFlush) {
      synchronized(_lock, () async => await _sink.flush());
    }
  }

  @override
  Future<ReadResult> read([String format = "l"]) async {
    return ReadResult(null, "Cannot read from stdout");
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    try {
      Logger.debug('Writing to stdout: "$data"', category: 'StdoutDevice');

      // Synchronize the write and flush operations
      await synchronized(_lock, () async {
        _sink.write(data);
        if (_allowFlush) await _sink.flush();
      });

      Logger.debug('Write successful', category: 'StdoutDevice');
      return WriteResult(true);
    } catch (e) {
      Logger.error('Write failed: $e', error: 'LuaFile');
      return WriteResult(false, e.toString());
    }
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    Logger.debug('Seeking in stdout (ignored)', category: 'StdoutDevice');
    throw UnsupportedError("Cannot seek in stdout");
  }

  @override
  Future<int> getPosition() async {
    Logger.debug(
      'Getting position in stdout (always 0)',
      category: 'StdoutDevice',
    );
    throw UnsupportedError("Cannot get position in stdout");
  }

  @override
  Future<bool> isEOF() async {
    Logger.debug(
      'Checking if at EOF (always false for stdout)',
      category: 'StdoutDevice',
    );
    return false;
  }
}

Future<T> synchronized<T>(Object lock, Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (e) {
    rethrow;
  }
}
