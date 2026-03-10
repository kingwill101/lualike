import 'dart:async';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/gc/gc.dart';

import '../stdlib/lib_io.dart';
import 'io_device.dart';

final fileMetamethods = {
  "__name": "FILE*",
  "__gc": (List<Object?> args) async {
    Logger.debugLazy(() => 'Garbage collecting file', category: 'IO');
    final fileValue = args[0];
    if (fileValue is! Value || fileValue.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }
    final luaFile = fileValue.raw as LuaFile;

    Logger.debugLazy(
      () =>
          'GC: About to close file: ${luaFile.toString()}, isClosed: ${luaFile.isClosed}',
      category: 'IO',
    );

    final isDefaultFile = IOLib.isCurrentDefaultFile(luaFile);

    Logger.debugLazy(
      () => 'GC: Is this a current default file? $isDefaultFile',
      category: 'IO',
    );

    // Don't close if already closed
    if (luaFile.isClosed) {
      Logger.debugLazy(
        () => 'GC: File already closed, skipping',
        category: 'IO',
      );
      IOLib.unregisterOpenFile(args[0] as Value);
      return Value(null);
    }

    final trackedWrapper = IOLib.trackedOpenFileWrapper(luaFile);
    if (trackedWrapper != null && !identical(trackedWrapper, fileValue)) {
      Logger.debugLazy(
        () => 'GC: Skipping close for non-canonical file wrapper',
        category: 'IO',
      );
      return Value(null);
    }

    // For default files that are being GC'd, we need to be more careful
    if (isDefaultFile) {
      // Check if this is a standard file that should never be closed
      if (luaFile.device == IOLib.stdoutDevice ||
          luaFile.device == IOLib.stderrDevice ||
          luaFile.device == IOLib.stdinDevice) {
        Logger.debugLazy(
          () => 'GC: Skipping close of standard device',
          category: 'IO',
        );
        return Value(null);
      }

      // For non-standard default files, reset the default but don't close yet
      // The file will be closed when explicitly closed or when a new default is set
      Logger.debugLazy(
        () => 'GC: Default file being collected, but keeping it alive',
        category: 'IO',
      );
      return Value(null);
    }

    // Not a default file and not closed, safe to close
    await luaFile.close();
    IOLib.unregisterOpenFile(args[0] as Value);
    Logger.debugLazy(() => 'GC: File closed successfully', category: 'IO');
    return Value(null);
  },
  "__close": (List<Object?> args) async {
    Logger.debugLazy(() => 'Closing file', category: 'IO');
    final fileValue = args[0];
    if (fileValue is Value && fileValue.raw is LuaFile) {
      final file = fileValue.raw as LuaFile;
      final result = await file.close();
      if (result.isNotEmpty && result[0] == true) {
        IOLib.unregisterOpenFile(fileValue);
      }
      return Value.multi(result);
    } else {
      throw LuaError.typeError("file expected");
    }
  },
  "__tostring": (List<Object?> args) {
    Logger.debugLazy(() => 'Converting file to string', category: 'IO');
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
    Logger.debugLazy(
      () => 'File __index metamethod called for ${key.raw}',
      category: 'IO',
    );

    final keyStr = switch (key.raw) {
      final String stringValue => stringValue,
      final LuaString stringValue => stringValue.toString(),
      _ => null,
    };
    if (keyStr != null) {
      // Handle file methods
      final method = LuaFile.fileMethods[keyStr];
      if (method != null) {
        Logger.debugLazy(() => 'Found file method: $keyStr', category: 'IO');
        return Value(method);
      }

      // Handle file properties
      if (fileValue is Value && fileValue.raw is LuaFile) {
        final luaFile = fileValue.raw as LuaFile;

        switch (keyStr) {
          case 'mode':
            Logger.debugLazy(
              () => 'Returning file mode: ${luaFile.mode}',
              category: 'IO',
            );
            return Value(luaFile.mode);
          case 'isClosed':
            Logger.debugLazy(
              () => 'Returning file isClosed: ${luaFile.isClosed}',
              category: 'IO',
            );
            return Value(luaFile.isClosed);
          case 'isStandardFile':
            Logger.debugLazy(
              () => 'Returning file isStandardFile: ${luaFile.isStandardFile}',
              category: 'IO',
            );
            return Value(luaFile.isStandardFile);
        }
      }
    }

    Logger.debugLazy(
      () => 'File property/method not found: ${key.raw}',
      category: 'IO',
    );
    return Value(null);
  },
};

/// Represents a Lua file object
class LuaFile {
  final IODevice device;
  Future<List<Object?>>? _closeFuture;

  bool get isClosed => device.isClosed;

  String get mode => device.mode;

  /// Whether this file is a standard file (stdin, stdout, stderr)
  final bool isStandardFile;

  LuaFile(this.device, {this.isStandardFile = false}) {
    Logger.debugLazy(
      () => "Created LuaFile with mode: $mode, isStandardFile: $isStandardFile",
      category: 'LuaFile',
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LuaFile &&
            identical(device, other.device) &&
            isStandardFile == other.isStandardFile;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(device), isStandardFile);

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
    final inFlight = _closeFuture;
    if (inFlight != null) {
      return inFlight;
    }

    Logger.debugLazy(
      () => "Closing file: $this (device: ${device.runtimeType})",
      category: 'LuaFile',
    );
    _closeFuture = () async {
      if (device.isClosed) {
        Logger.debugLazy(() => "File already closed", category: 'LuaFile');
        return [true];
      }
      try {
        await device.close();
        Logger.debugLazy(() => "File closed successfully", category: 'LuaFile');
        return [true];
      } catch (e, st) {
        Logger.error("Error closing file: $e", error: 'LuaFile', trace: st);
        return [null, e.toString()];
      }
    }();
    return _closeFuture!;
  }

  /// Flush any buffered output
  Future<List<Object?>> flush() async {
    Logger.debugLazy(() => "Flushing file buffer: $this", category: 'LuaFile');
    try {
      await device.flush();
      Logger.debugLazy(
        () => "File buffer flushed successfully",
        category: 'LuaFile',
      );
      return [true];
    } catch (e) {
      Logger.error("Error flushing file buffer: $e", error: 'LuaFile');
      return [null, e.toString()];
    }
  }

  /// Read from the file according to the given format
  Future<List<Object?>> read([String format = "l"]) async {
    Logger.debugLazy(
      () => "Reading from file $this with format '$format'",
      category: 'LuaFile',
    );

    if (isClosed) {
      throw LuaError(" input file is closed");
    }

    final result = await device.read(format);
    if (result.isSuccess) {
      Logger.debugLazy(
        () => "Read successful: ${result.value}",
        category: 'LuaFile',
      );
    } else {
      Logger.error("Read failed: ${result.error}", error: 'LuaFile');
    }
    return result.toLua();
  }

  /// Write data to the file
  Future<List<Object?>> write(String data) async {
    Logger.debugLazy(
      () => "Writing to file $this: ${data.length} characters",
      category: 'LuaFile',
    );
    final result = await device.write(data);
    if (result.success) {
      Logger.debugLazy(() => "Write successful", category: 'LuaFile');
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
    Logger.debugLazy(
      () => "Writing raw bytes to file $this: ${bytes.length} bytes",
      category: 'LuaFile',
    );
    final result = await device.writeBytes(bytes);
    if (result.success) {
      Logger.debugLazy(() => "Raw write successful", category: 'LuaFile');
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
    Logger.debugLazy(
      () => "Seeking in file $this: whence=$whence, offset=$offset",
      category: 'LuaFile',
    );
    try {
      final whenceEnum = switch (whence) {
        "set" => SeekWhence.set,
        "cur" => SeekWhence.cur,
        "end" => SeekWhence.end,
        _ => throw LuaError("invalid option '$whence'"),
      };

      Logger.debugLazy(
        () => "Seek whence mapped to: $whenceEnum",
        category: 'LuaFile',
      );
      final position = await device.seek(whenceEnum, offset);
      Logger.debugLazy(
        () => "Seek successful: new position=$position",
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
    Logger.debugLazy(
      () => "Setting buffer mode for $this: mode=$mode, size=$size",
      category: 'LuaFile',
    );
    try {
      final bufferMode = switch (mode) {
        "no" => BufferMode.none,
        "full" => BufferMode.full,
        "line" => BufferMode.line,
        _ => throw LuaError("invalid option '$mode'"),
      };

      Logger.debugLazy(
        () => "Buffer mode mapped to: $bufferMode",
        category: 'LuaFile',
      );
      await device.setBuffering(bufferMode, size);
      Logger.debugLazy(
        () => "Buffer mode set successfully",
        category: 'LuaFile',
      );
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
    Value? owner,
  ]) async {
    Logger.debugLazy(
      () => "Creating file line iterator for $this with formats: $formats",
      category: 'IO',
    );

    // Check if file was opened for reading - return error function instead of throwing
    if (mode == "w" || mode == "a") {
      Logger.debugLazy(
        () =>
            'Cannot create lines iterator for write-only file $this with mode: $mode',
        category: 'IO',
      );
      return Value((List<Object?> args) async {
        throw LuaError("Cannot read from write-only file");
      });
    }
    final iteratorValue = Value(
      _LuaFileLineIterator(
        file: this,
        formats: formats,
        closeOnEof: closeOnEof,
        owner: owner,
      ),
    );
    if (owner != null) {
      iteratorValue.upvalues = [
        Upvalue(
          valueBox: Box<dynamic>(owner, isTransient: true),
          interpreter: owner.interpreter,
        ),
      ];
    }
    return iteratorValue;
  }

  @override
  String toString() {
    return isClosed ? "file (closed)" : "file ($mode)";
  }
}

final class _LuaFileLineIterator extends BuiltinFunction implements GCObject {
  _LuaFileLineIterator({
    required this.file,
    required this.formats,
    required this.closeOnEof,
    required this.owner,
  });

  final LuaFile file;
  final List<String> formats;
  final bool closeOnEof;
  final Value? owner;

  bool hasBeenClosed = false;
  int iterationCount = 0;

  @override
  bool marked = false;

  @override
  bool isOld = false;

  @override
  int get estimatedSize => 96;

  @override
  List<Object?> getReferences() => [if (owner != null) owner];

  @override
  void free() {}

  @override
  Future<Object?> call(List<Object?> args) async {
    iterationCount++;
    Logger.debugLazy(
      () => "Line iterator call #$iterationCount for $file",
      category: 'IO',
    );

    if (hasBeenClosed) {
      Logger.debugLazy(
        () =>
            "Line iterator called after file $file was closed (iteration #$iterationCount)",
        category: 'IO',
      );
      throw LuaError("file is already closed");
    }

    if (file.isClosed) {
      Logger.debugLazy(
        () =>
            "Line iterator called but file $file is closed (iteration #$iterationCount)",
        category: 'IO',
      );
      hasBeenClosed = true;
      throw LuaError("file is already closed");
    }

    Logger.debugLazy(
      () => "Line iterator checking EOF for $file (iteration #$iterationCount)",
      category: 'IO',
    );
    final isAtEOF = await file.device.isEOF();
    Logger.debugLazy(
      () => "EOF check result: $isAtEOF for $file (iteration #$iterationCount)",
      category: 'IO',
    );

    if (isAtEOF) {
      Logger.debugLazy(
        () =>
            "Reached EOF in line iterator for $file, closeOnEof=$closeOnEof (iteration #$iterationCount)",
        category: 'IO',
      );
      if (closeOnEof) {
        await file.close();
        hasBeenClosed = true;
        Logger.debugLazy(
          () =>
              "File closed due to closeOnEof=true, returning null to end iteration (iteration #$iterationCount)",
          category: 'IO',
        );
      } else {
        Logger.debugLazy(
          () =>
              "EOF reached but closeOnEof=false, returning null to end iteration without closing (iteration #$iterationCount)",
          category: 'IO',
        );
      }
      return Value(null);
    }

    final results = <Object?>[];
    for (final format in formats) {
      Logger.debugLazy(
        () =>
            "Line iterator reading format: $format from $file (iteration #$iterationCount)",
        category: 'IO',
      );

      final result = await file.device.read(format);
      Logger.debugLazy(
        () =>
            "Read result: success=${result.isSuccess}, value=${result.value}, error=${result.error} (iteration #$iterationCount)",
        category: 'IO',
      );

      if (!result.isSuccess) {
        Logger.debugLazy(
          () =>
              "Line iterator read failed for $file: ${result.error} (iteration #$iterationCount)",
          category: 'IO',
        );
        if (closeOnEof) {
          Logger.debugLazy(
            () =>
                "closeOnEof=true, marking iterator closed after read error (iteration #$iterationCount)",
            category: 'IO',
          );
          hasBeenClosed = true;
        }
        throw LuaError(result.error ?? "file read error");
      }

      if (result.value == null) {
        Logger.debugLazy(
          () =>
              "Line iterator reached EOF for $file (iteration #$iterationCount)",
          category: 'IO',
        );
        hasBeenClosed = true;
        if (closeOnEof) {
          Logger.debugLazy(
            () =>
                "closeOnEof=true, deferring close to to-be-closed variable (iteration #$iterationCount)",
            category: 'IO',
          );
        } else {
          Logger.debugLazy(
            () =>
                "closeOnEof=false, iterator marked closed but file remains open for manual close (iteration #$iterationCount)",
            category: 'IO',
          );
        }
        return Value(null);
      }

      results.add(result.value);
    }

    Logger.debugLazy(
      () =>
          "Line iterator read successful for $file: ${results.length} values (iteration #$iterationCount)",
      category: 'IO',
    );

    if (results.length == 1) {
      Logger.debugLazy(
        () =>
            "Returning single value: ${results[0]} (iteration #$iterationCount)",
        category: 'IO',
      );
      return Value(results[0]);
    }

    Logger.debugLazy(
      () => "Returning multi values: $results (iteration #$iterationCount)",
      category: 'IO',
    );
    return Value.multi(results);
  }
}

/// Helper function to create a LuaFile wrapped in a Value with proper metamethods
Value wrapLuaFileValue(
  LuaFile luaFile, {
  LuaRuntime? interpreter,
}) {
  final fileValue = Value(
    luaFile,
    metatable: fileMetamethods,
    interpreter: interpreter,
  );
  IOLib.registerOpenFile(fileValue);
  return fileValue;
}

Value createLuaFile(
  IODevice device, {
  bool isStandardFile = false,
  LuaRuntime? interpreter,
}) {
  final luaFile = LuaFile(device, isStandardFile: isStandardFile);
  return wrapLuaFileValue(luaFile, interpreter: interpreter);
}
