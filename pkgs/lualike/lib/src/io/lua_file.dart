import 'dart:async';

import 'package:lualike/lualike.dart';

import 'io_device.dart';

/// Represents a Lua file object that wraps an IODevice
class LuaFile {
  final IODevice _device;

  IODevice get device => _device;

  bool get isClosed => _device.isClosed;

  String get mode => _device.mode;

  LuaFile(this._device) {
    Logger.debug("Created LuaFile with mode: $mode", category: 'LuaFile');
  }

  /// Close the file
  Future<List<Object?>> close() async {
    Logger.debug("Closing file", category: 'LuaFile');
    try {
      await _device.close();
      Logger.debug("File closed successfully", category: 'LuaFile');
      return [true];
    } catch (e) {
      Logger.error("Error closing file: $e", error: 'LuaFile');
      return [null, e.toString()];
    }
  }

  /// Flush any buffered output
  Future<List<Object?>> flush() async {
    Logger.debug("Flushing file buffer", category: 'LuaFile');
    try {
      await _device.flush();
      Logger.debug("File buffer flushed successfully", category: 'LuaFile');
      return [true];
    } catch (e) {
      Logger.error("Error flushing file buffer: $e", error: 'LuaFile');
      return [null, e.toString()];
    }
  }

  /// Read from the file according to the given format
  Future<List<Object?>> read([String format = "l"]) async {
    Logger.debug(
      "Reading from file with format '$format'",
      category: 'LuaFile',
    );
    final result = await _device.read(format);
    if (result.isSuccess) {
      Logger.debug("Read successful: ${result.value}", category: 'LuaFile');
    } else {
      Logger.error("Read failed: ${result.error}", error: 'LuaFile');
    }
    return result.toLua();
  }

  /// Write data to the file
  Future<List<Object?>> write(String data) async {
    Logger.debug(
      "Writing to file: ${data.length} characters",
      category: 'LuaFile',
    );
    final result = await _device.write(data);
    if (result.success) {
      Logger.debug("Write successful", category: 'LuaFile');
    } else {
      Logger.error(
        "Write failed: ${result.error} code: ${result.errorCode}",
        error: 'LuaFile',
      );
    }
    return result.toLua();
  }

  /// Seek to a position in the file
  /// whence can be:
  /// - "set": from start of file
  /// - "cur": from current position
  /// - "end": from end of file
  Future<List<Object?>> seek(String whence, [int offset = 0]) async {
    Logger.debug(
      "Seeking in file: whence=$whence, offset=$offset",
      category: 'LuaFile',
    );
    try {
      final whenceEnum = switch (whence) {
        "set" => SeekWhence.set,
        "cur" => SeekWhence.cur,
        "end" => SeekWhence.end,
        _ => throw LuaError("invalid option '$whence'"),
      };

      Logger.debug("Seek whence mapped to: $whenceEnum", category: 'LuaFile');
      final position = await _device.seek(whenceEnum, offset);
      Logger.debug(
        "Seek successful: new position=$position",
        category: 'LuaFile',
      );
      return [position];
    } catch (e) {
      Logger.error("Error during seek operation: $e", error: 'LuaFile $e');
      // Return 3-value error tuple as expected by Lua: (nil, message, code)
      return [null, e.toString(), 0];
    }
  }

  /// Set the buffering mode for the file
  /// mode can be:
  /// - "no": no buffering
  /// - "full": full buffering
  /// - "line": line buffering
  Future<List<Object?>> setvbuf(String mode, [int? size]) async {
    Logger.debug(
      "Setting buffer mode: mode=$mode, size=$size",
      category: 'LuaFile',
    );
    try {
      final bufferMode = switch (mode) {
        "no" => BufferMode.none,
        "full" => BufferMode.full,
        "line" => BufferMode.line,
        _ => throw LuaError("invalid option '$mode'"),
      };

      Logger.debug("Buffer mode mapped to: $bufferMode", category: 'LuaFile');
      await _device.setBuffering(bufferMode, size);
      Logger.debug("Buffer mode set successfully", category: 'LuaFile');
      return [true];
    } catch (e) {
      Logger.error("Error setting buffer mode: $e", error: 'LuaFile $e');
      return [null, e.toString()];
    }
  }

  /// Create an iterator that reads lines from the file
  Future<Value> lines([List<String> formats = const ["l"]]) async {
    Logger.debug(
      "Creating file line iterator with formats: $formats",
      category: 'LuaFile',
    );
    bool hasBeenClosed = false;

    return Value((List<Object?> args) async {
      if (hasBeenClosed) {
        Logger.debug(
          "Line iterator called after file was closed",
          category: 'LuaFile',
        );
        throw LuaError("file is already closed");
      }

      if (isClosed) {
        Logger.debug(
          "Line iterator called but file is closed",
          category: 'LuaFile',
        );
        hasBeenClosed = true;
        throw LuaError("file is already closed");
      }

      Logger.debug("Line iterator checking EOF", category: 'LuaFile');
      if (await _device.isEOF()) {
        Logger.debug(
          "Reached EOF in line iterator, closing file",
          category: 'LuaFile',
        );
        await close();
        hasBeenClosed = true;
        return Value(null);
      }

      // Read all formats in a single call and return multiple values
      final results = <Object?>[];
      for (final format in formats) {
        Logger.debug(
          "Line iterator reading format: $format",
          category: 'LuaFile',
        );

        final result = await _device.read(format);
        if (!result.isSuccess || result.value == null) {
          Logger.debug(
            "Line iterator read unsuccessful, closing file",
            category: 'LuaFile',
          );
          await close();
          hasBeenClosed = true;
          return Value(null);
        }

        results.add(result.value);
      }

      Logger.debug(
        "Line iterator read successful: ${results.length} values",
        category: 'LuaFile',
      );

      // Return multiple values if there are multiple formats
      if (results.length == 1) {
        return Value(results[0]);
      } else {
        return Value.multi(results);
      }
    });
  }

  @override
  String toString() {
    return isClosed ? "file (closed)" : "file ($mode)";
  }
}
