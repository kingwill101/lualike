import 'dart:async';
import 'package:lualike/lualike.dart';

/// Represents the result of a read operation
class ReadResult {
  final Object? value;
  final String? error;
  final int? errorCode;

  ReadResult(this.value, [this.error, this.errorCode]) {
    final valueStr = value is String && (value as String).length > 100
        ? '${(value as String).length} characters'
        : value?.toString() ?? "null";
    Logger.debug(
      'ReadResult created: value=$valueStr, error=${error ?? "null"}, errorCode=${errorCode ?? "null"}',
      category: 'IO',
    );
  }

  bool get isSuccess => error == null;

  /// Convert to Lua-style error tuple
  List<Object?> toLua() {
    final result = error != null ? [null, error, errorCode] : [value];
    final resultStr =
        result.isNotEmpty &&
            result[0] is String &&
            (result[0] as String).length > 100
        ? '[String of ${(result[0] as String).length} characters, ...]'
        : '$result';
    Logger.debug('ReadResult toLua: $resultStr', category: 'IO');
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
    final resultStr =
        result.length > 1 &&
            result[1] is String &&
            (result[1] as String).length > 100
        ? '[null, String of ${(result[1] as String).length} characters, ...]'
        : '$result';
    Logger.debug('WriteResult toLua: $resultStr', category: 'IO');
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

  BaseIODevice([this.mode = 'r']) {
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
    if (!RegExp(r'^(\*?n|\*?a|\*?l|\*?L|\d+)$').hasMatch(format)) {
      Logger.debug("Invalid format: $format", category: "IO");
      throw LuaError("invalid format: $format");
    }
    Logger.debug("Format $format is valid", category: "IO");
  }

  /// Helper to normalize read format by removing * prefix
  String normalizeReadFormat(String format) {
    if (format.startsWith('*')) {
      return format.substring(1);
    }
    return format;
  }
}

Future<T> synchronized<T>(Object lock, Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (e) {
    rethrow;
  }
}
