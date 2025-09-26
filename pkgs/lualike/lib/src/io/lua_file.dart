import 'dart:async';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/value.dart';

import '../stdlib/lib_io.dart';
import 'io_device.dart';

// Create metamethods for the wrapped file
final fileMetamethods = {
  "__name": "FILE*",
  "__gc": (List<Object?> args) async {
    Logger.debug('Garbage collecting file', category: 'IO');
    final fileValue = args[0];
    if (fileValue is! Value || fileValue.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }
    final luaFile = fileValue.raw as LuaFile;
    Logger.debug(
      'GC: About to close file: ${luaFile.toString()}, isClosed: ${luaFile.isClosed}',
      category: 'IO',
    );

    // Check if this is a default file before closing
    final isDefaultOutput = IOLib.defaultOutput.raw == luaFile;
    final isDefaultInput = IOLib.defaultInput.raw == luaFile;

    Logger.debug(
      'GC: Is this the default output? $isDefaultOutput',
      category: 'IO',
    );
    Logger.debug(
      'GC: Is this the default input? $isDefaultInput',
      category: 'IO',
    );

    // Don't close if already closed
    if (luaFile.isClosed) {
      Logger.debug('GC: File already closed, skipping', category: 'IO');
      return Value(null);
    }

    // For default files that are being GC'd, we need to be more careful
    if (isDefaultOutput || isDefaultInput) {
      // Check if this is a standard file that should never be closed
      if (luaFile.device == IOLib.stdoutDevice ||
          luaFile.device == IOLib.stderrDevice ||
          luaFile.device == IOLib.stdinDevice) {
        Logger.debug('GC: Skipping close of standard device', category: 'IO');
        return Value(null);
      }

      // For non-standard default files, reset the default but don't close yet
      // The file will be closed when explicitly closed or when a new default is set
      Logger.debug(
        'GC: Default file being collected, but keeping it alive',
        category: 'IO',
      );
      return Value(null);
    }

    // Not a default file and not closed, safe to close
    await luaFile.close();
    Logger.debug('GC: File closed successfully', category: 'IO');
    return Value(null);
  },
  "__close": (List<Object?> args) async {
    Logger.debug('Closing file', category: 'IO');
    final fileValue = args[0];
    if (fileValue is Value && fileValue.raw is LuaFile) {
      final file = fileValue.raw as LuaFile;
      final result = await file.close();
      return Value.multi(result);
    } else {
      throw LuaError.typeError("file expected");
    }
  },
  "__tostring": (List<Object?> args) {
    Logger.debug('Converting file to string', category: 'IO');
    final fileValue = args[0];
    if (fileValue is Value && fileValue.raw is LuaFile) {
      final file = fileValue.raw as LuaFile;
      return Value(file.toString());
    } else {
      throw LuaError.typeError("file expected");
    }
  },
  "__index": (List<Object?> args) {
    final fileValue = args[0];
    final key = args[1] as Value;
    Logger.debug(
      'File __index metamethod called for ${key.raw}',
      category: 'IO',
    );

    if (key.raw is String) {
      final method = LuaFile.fileMethods[key.raw];
      if (method != null) {
        Logger.debug('Found file method: ${key.raw}', category: 'IO');

        // Return a bound method that checks for proper self argument
        return Value((callArgs) {
          Logger.debug(
            'File method ${key.raw} called with ${callArgs.length} arguments',
            category: 'IO',
          );

          // If called without arguments, it should fail
          if (callArgs.isEmpty) {
            // This is the case: local f = io.stdin.close; f()
            return method.call(callArgs); // Let method handle the error
          }

          // If first argument is this file, call method normally
          if (callArgs.isNotEmpty && callArgs.first == fileValue) {
            return method.call(callArgs);
          }

          // Otherwise, prepend the file as self (for io.stdin.close() syntax)
          return method.call([fileValue, ...callArgs]);
        });
      }
    }

    Logger.debug('File method not found: ${key.raw}', category: 'IO');
    return Value(null);
  },
};

/// Represents a Lua file object
class LuaFile {
  final IODevice device;

  bool get isClosed => device.isClosed;

  String get mode => device.mode;

  /// Whether this file is a standard file (stdin, stdout, stderr)
  final bool isStandardFile;

  LuaFile(this.device, {this.isStandardFile = false}) {
    Logger.debug(
      "Created LuaFile with mode: $mode, isStandardFile: $isStandardFile",
      category: 'LuaFile',
    );
  }

  static final Map<String, BuiltinFunction> fileMethods = {
    "close": FileClose(),
    "flush": FileFlush(),
    "read": FileRead(),
    "write": FileWrite(),
    "seek": FileSeek(),
    "lines": FileLines(),
    "setvbuf": FileSetvbuf(),
  };

  /// Close the file
  Future<List<Object?>> close() async {
    Logger.debug(
      "Closing file: $this (device: ${device.runtimeType})",
      category: 'LuaFile',
    );
    try {
      await device.close();
      Logger.debug("File closed successfully", category: 'LuaFile');
      return [true];
    } catch (e) {
      Logger.error("Error closing file: $e", error: 'LuaFile');
      return [null, e.toString()];
    }
  }

  /// Flush any buffered output
  Future<List<Object?>> flush() async {
    Logger.debug("Flushing file buffer: $this", category: 'LuaFile');
    try {
      await device.flush();
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
      "Reading from file $this with format '$format'",
      category: 'LuaFile',
    );

    if (isClosed) {
      throw Exception(" input file is closed");
    }

    final result = await device.read(format);
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
      "Writing to file $this: ${data.length} characters",
      category: 'LuaFile',
    );
    final result = await device.write(data);
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

  /// Write raw bytes to the file without encoding
  Future<List<Object?>> writeBytes(List<int> bytes) async {
    Logger.debug(
      "Writing raw bytes to file $this: ${bytes.length} bytes",
      category: 'LuaFile',
    );
    final result = await device.writeBytes(bytes);
    if (result.success) {
      Logger.debug("Raw write successful", category: 'LuaFile');
    } else {
      Logger.error(
        "Raw write failed: ${result.error} code: ${result.errorCode}",
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
      "Seeking in file $this: whence=$whence, offset=$offset",
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
      final position = await device.seek(whenceEnum, offset);
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
      "Setting buffer mode for $this: mode=$mode, size=$size",
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
      await device.setBuffering(bufferMode, size);
      Logger.debug("Buffer mode set successfully", category: 'LuaFile');
      return [true];
    } catch (e) {
      Logger.error("Error setting buffer mode: $e", error: 'LuaFile $e');
      return [null, e.toString()];
    }
  }

  /// Create an iterator that reads lines from the file
  /// [closeOnEof] - whether to close the file when EOF is reached (default: false)
  Future<Value> lines([
    List<String> formats = const ["l"],
    bool closeOnEof = false,
  ]) async {
    Logger.debug(
      "Creating file line iterator for $this with formats: $formats",
      category: 'IO',
    );

    // Check if file was opened for reading - return error function instead of throwing
    if (mode == "w" || mode == "a") {
      Logger.debug(
        'Cannot create lines iterator for write-only file $this with mode: $mode',
        category: 'IO',
      );
      return Value((List<Object?> args) async {
        throw LuaError("Cannot read from write-only file");
      });
    }

    bool hasBeenClosed = false;
    int iterationCount = 0;

    return Value((List<Object?> args) async {
      iterationCount++;
      Logger.debug(
        "Line iterator call #$iterationCount for $this",
        category: 'IO',
      );

      if (hasBeenClosed) {
        Logger.debug(
          "Line iterator called after file $this was closed (iteration #$iterationCount)",
          category: 'IO',
        );
        throw LuaError("file is already closed");
      }

      if (isClosed) {
        Logger.debug(
          "Line iterator called but file $this is closed (iteration #$iterationCount)",
          category: 'IO',
        );
        hasBeenClosed = true;
        throw LuaError("file is already closed");
      }

      Logger.debug(
        "Line iterator checking EOF for $this (iteration #$iterationCount)",
        category: 'IO',
      );
      final isAtEOF = await device.isEOF();
      Logger.debug(
        "EOF check result: $isAtEOF for $this (iteration #$iterationCount)",
        category: 'IO',
      );

      if (isAtEOF) {
        Logger.debug(
          "Reached EOF in line iterator for $this, closeOnEof=$closeOnEof (iteration #$iterationCount)",
          category: 'IO',
        );
        if (closeOnEof) {
          await close();
          hasBeenClosed = true;
          Logger.debug(
            "File closed due to closeOnEof=true, returning null to end iteration (iteration #$iterationCount)",
            category: 'IO',
          );
        } else {
          Logger.debug(
            "EOF reached but closeOnEof=false, returning null to end iteration without closing (iteration #$iterationCount)",
            category: 'IO',
          );
        }
        return Value(null);
      }

      // Read all formats in a single call and return multiple values
      final results = <Object?>[];
      for (final format in formats) {
        Logger.debug(
          "Line iterator reading format: $format from $this (iteration #$iterationCount)",
          category: 'IO',
        );

        final result = await device.read(format);
        Logger.debug(
          "Read result: success=${result.isSuccess}, value=${result.value}, error=${result.error} (iteration #$iterationCount)",
          category: 'IO',
        );

        if (!result.isSuccess || result.value == null) {
          Logger.debug(
            "Line iterator read unsuccessful for $this, closing file (iteration #$iterationCount)",
            category: 'IO',
          );
          await close();
          hasBeenClosed = true;
          Logger.debug(
            "File closed, returning null to end iteration (iteration #$iterationCount)",
            category: 'LuaFile',
          );
          return Value(null);
        }

        results.add(result.value);
      }

      Logger.debug(
        "Line iterator read successful for $this: ${results.length} values (iteration #$iterationCount)",
        category: 'IO',
      );

      // Log what we're about to return
      if (results.length == 1) {
        Logger.debug(
          "Returning single value: ${results[0]} (iteration #$iterationCount)",
          category: 'IO',
        );
      } else {
        Logger.debug(
          "Returning multi values: $results (iteration #$iterationCount)",
          category: 'IO',
        );
      }

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

/// Helper function to create a LuaFile wrapped in a Value with proper metamethods
Value createLuaFile(IODevice device, {bool isStandardFile = false}) {
  final luaFile = LuaFile(device, isStandardFile: isStandardFile);

  return Value(luaFile, metatable: fileMetamethods);
}
