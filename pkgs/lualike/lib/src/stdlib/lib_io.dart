import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:lualike/src/utils/io_abstractions.dart' as io_abs;

import '../io/filesystem_provider.dart';
import '../io/io_device.dart';
import '../io/lua_file.dart';

class IOLib {
  // Singleton instances for standard devices
  static StdinDevice? _stdinDevice;
  static StdoutDevice? _stdoutDevice;
  static StdoutDevice? _stderrDevice;

  // File system provider - defaults to local file system
  static FileSystemProvider? _fileSystemProvider;

  static LuaFile? _defaultInput;
  static Value? _defaultOutput;
  static bool _defaultOutputExplicitlyClosed = false;

  // Get singleton instances
  static StdinDevice get stdinDevice {
    Logger.debug('Getting stdinDevice', category: 'IO');
    Logger.debug('Current _stdinDevice: $_stdinDevice', category: 'IO');
    if (_stdinDevice == null) {
      Logger.debug('Creating new StdinDevice', category: 'IO');
      _stdinDevice = StdinDevice();
      Logger.debug('Created StdinDevice: $_stdinDevice', category: 'IO');
    }
    return _stdinDevice!;
  }

  static StdoutDevice get stdoutDevice =>
      _stdoutDevice ??= StdoutDevice(io_abs.stdout, false);

  static StdoutDevice get stderrDevice =>
      _stderrDevice ??= StdoutDevice(io_abs.stderr);

  // File system provider factory
  static FileSystemProvider get fileSystemProvider =>
      _fileSystemProvider ??= FileSystemProvider();

  /// Set a custom file system provider
  static set fileSystemProvider(FileSystemProvider provider) {
    Logger.debug(
      'Setting file system provider to: ${provider.providerName}',
      category: 'FileSystem',
    );
    _fileSystemProvider = provider;
  }

  // Setters to allow custom devices (similar to what you mentioned exists for stdio)
  static set stdinDevice(StdinDevice device) => _stdinDevice = device;

  static set stdoutDevice(StdoutDevice device) => _stdoutDevice = device;

  static set stderrDevice(StdoutDevice device) => _stderrDevice = device;

  static LuaFile get defaultInput {
    Logger.debug('Getting default input', category: 'IO');
    Logger.debug('Current _defaultInput: $_defaultInput', category: 'IO');
    if (_defaultInput == null) {
      Logger.debug(
        'Creating new default input with stdinDevice',
        category: 'IO',
      );
      _defaultInput = LuaFile(stdinDevice);
      Logger.debug('Created default input: $_defaultInput', category: 'IO');
    } else {
      Logger.debug(
        'Using existing default input: $_defaultInput',
        category: 'IO',
      );
    }
    return _defaultInput!;
  }

  static set defaultInput(LuaFile? file) {
    _defaultInput = file;
  }

  static LuaFile get defaultOutput {
    Logger.debug('Getting default output');
    if (_defaultOutput == null) {
      final stdoutFile = LuaFile(stdoutDevice);
      _defaultOutput = Value(stdoutFile, metatable: fileClass.metamethods);
    }
    return _defaultOutput!.raw as LuaFile;
  }

  static set defaultOutput(Value? file) {
    _defaultOutput = file;
  }

  // File methods that operate on LuaFile objects
  static final Map<String, BuiltinFunction> fileMethods = {
    "close": FileClose(),
    "flush": FileFlush(),
    "read": FileRead(),
    "write": FileWrite(),
    "seek": FileSeek(),
    "lines": FileLines(),
    "setvbuf": FileSetvbuf(),
  };

  static final ValueClass fileClass = ValueClass.create({
    "__name": "FILE*",
    "__gc": (List<Object?> args) async {
      Logger.debug('Garbage collecting file', category: 'IO');
      final file = args[0];
      if (file is! Value) {
        throw LuaError.typeError("file expected");
      }
      final luaFile = file.raw as LuaFile;
      Logger.debug(
        'GC: About to close file: ${luaFile.toString()}, isClosed: ${luaFile.isClosed}',
        category: 'IO',
      );

      // Check if this is a default file before closing
      final isDefaultOutput = IOLib._defaultOutput?.raw == luaFile;
      final isDefaultInput = luaFile == IOLib._defaultInput;

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
      final file = args[0];
      if (file is! Value) {
        throw LuaError.typeError("file expected");
      }
      final result = await (file.raw as LuaFile).close();
      return Value.multi(result);
    },
    "__tostring": (List<Object?> args) {
      Logger.debug('Converting file to string', category: 'IO');
      final file = args[0];
      if (file is! Value) {
        throw LuaError.typeError("file expected");
      }
      return Value((file.raw as LuaFile).toString());
    },
    "__index": (List<Object?> args) {
      final file = args[0] as Value;
      final key = args[1] as Value;
      Logger.debug(
        'File __index metamethod called for ${key.raw}',
        category: 'IO',
      );

      if (key.raw is String) {
        final method = fileMethods[key.raw];
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
            if (callArgs.isNotEmpty && callArgs.first == file) {
              return method.call(callArgs);
            }

            // Otherwise, prepend the file as self (for io.stdin.close() syntax)
            return method.call([file, ...callArgs]);
          });
        }
      }

      Logger.debug('File method not found: ${key.raw}', category: 'IO');
      return Value(null);
    },
  });

  static final Map<String, BuiltinFunction> functions = {
    "close": IOClose(),
    "flush": IOFlush(),
    "input": IOInput(),
    "lines": IOLines(),
    "open": IOOpen(),
    "output": IOOutput(),
    "popen": IOPopen(),
    "read": IORead(),
    "tmpfile": IOTmpfile(),
    "type": IOType(),
    "write": IOWrite(),
  };

  static Future<void> reset() async {
    if (_defaultInput?.device is! StdinDevice) {
      await _defaultInput?.close();
    }
    _defaultInput = null;

    if (_defaultOutput?.raw is LuaFile &&
        (_defaultOutput!.raw as LuaFile).device is! StdoutDevice) {
      await (_defaultOutput!.raw as LuaFile).close();
    }
    _defaultOutput = null;
    _defaultOutputExplicitlyClosed = false;
  }
}

class IOClose implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO close', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Closing default output', category: 'IO');
      final result = await IOLib.defaultOutput.close();
      IOLib._defaultOutputExplicitlyClosed = true;
      Logger.debug(
        'Set _defaultOutputExplicitlyClosed to true',
        category: 'IO',
      );
      IOLib._defaultOutput = null; // Reset to stdout on next access
      return Value.multi(result);
    }

    final file = args[0];
    if (file is! Value) {
      throw LuaError.typeError("file expected");
    }
    if (file.raw is! LuaFile) {
      Logger.debug('Attempt to close non-file object', category: 'IO');
      return Value.multi([null, "attempt to close a non-file object"]);
    }

    Logger.debug('Closing file', category: 'IO');
    final luaFile = file.raw as LuaFile;

    // Check if this is a standard file (stdin, stdout, stderr)
    if (_isStandardFile(luaFile)) {
      Logger.debug('Cannot close standard file', category: 'IO');
      return Value(false); // Standard files cannot be closed
    }

    // Check if file is already closed
    if (luaFile.isClosed) {
      Logger.debug('File is already closed', category: 'IO');

      // Special handling for default input/output files
      // If this is the default input or output file that was closed (e.g., by GC),
      // we should return success rather than throwing an error
      if (luaFile == IOLib._defaultInput ||
          luaFile == IOLib._defaultOutput?.raw) {
        Logger.debug(
          'Default input/output file already closed, returning success',
          category: 'IO',
        );
        return Value.multi([true]);
      }

      // For other files, throw an error as expected
      throw LuaError("closed file");
    }

    final result = await luaFile.close();
    if (IOLib._defaultOutput?.raw == luaFile) {
      // When closing the current output file, revert to stdout
      Logger.debug('Resetting default output to stdout', category: 'IO');
      IOLib._defaultOutput = null;
    }

    // Note: We don't reset _defaultInput to null here because we want
    // subsequent io.read calls to detect the closed file and throw an error
    return Value.multi(result);
  }

  static bool _isStandardFile(LuaFile file) {
    // Check if this file uses one of the standard singleton devices
    return file.device == IOLib.stdinDevice ||
        file.device == IOLib.stdoutDevice ||
        file.device == IOLib.stderrDevice;
  }
}

class IOFlush implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO flush', category: 'IO');
    final result = await IOLib.defaultOutput.flush();
    return Value.multi(result);
  }
}

class IOInput implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO input', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Returning default input', category: 'IO');
      return Value(IOLib.defaultInput, metatable: IOLib.fileClass.metamethods);
    }

    LuaFile? newFile;
    Value? result;

    if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Setting default input to provided file', category: 'IO');
      newFile = (args[0] as Value).raw as LuaFile;
      result = args[0] as Value;
    } else {
      final filename = (args[0] as Value).raw.toString();
      Logger.debug('Opening file for input: $filename', category: 'IO');
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        newFile = LuaFile(device);
        result = Value(newFile, metatable: IOLib.fileClass.metamethods);
      } catch (e) {
        Logger.debug('Error opening file: $e', category: 'IO');
        // Match Lua's behavior: throw an error instead of returning error values
        throw LuaError("cannot open file '$filename' ($e)");
      }
    }

    // Do not auto-close the previous default input (matches Lua semantics).
    // Simply switch the handle; if it's the same handle, keep it as-is.
    if (!identical(IOLib._defaultInput, newFile)) {
      IOLib._defaultInput = newFile;
    }
    return result;
  }
}

class IOLines implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO lines with ${args.length} args', category: 'IO');

    // Log the arguments
    for (int i = 0; i < args.length; i++) {
      final arg = args[i] as Value;
      Logger.debug(
        'Arg $i: ${arg.raw} (type: ${arg.raw.runtimeType})',
        category: 'IO',
      );
    }

    // Check for too many arguments (Lua limit is around 251)
    if (args.length > 251) {
      throw LuaError("too many arguments");
    }

    LuaFile file;
    List<String> formats;

    if (args.isEmpty) {
      Logger.debug('Using default input for lines (no args)', category: 'IO');
      Logger.debug('About to get defaultInput...', category: 'IO');
      file = IOLib.defaultInput;
      Logger.debug('Got defaultInput: $file', category: 'IO');
      formats = ["l"];
      Logger.debug('About to call file.lines()...', category: 'IO');
      return await file.lines(formats);
    } else if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Using provided file for lines', category: 'IO');
      file = (args[0] as Value).raw as LuaFile;
      formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
      if (formats.isEmpty) formats = ["l"];
      return await file.lines(formats);
    } else if (args[0] is Value && (args[0] as Value).raw != null) {
      Logger.debug('Opening new file for lines', category: 'IO');
      final filename = (args[0] as Value).raw.toString();
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        file = LuaFile(device);
        formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
        if (formats.isEmpty) formats = ["l"];
        final iterator = await file.lines(
          formats,
          true,
        ); // closeOnEof = true for io.lines(filename)

        // Return iterator, dummy state/control (nil), and a to-be-closed variable
        final toClose = Value.toBeClose(
          file,
          metatable: IOLib.fileClass.metamethods,
        );
        return Value.multi([iterator, Value(null), Value(null), toClose]);
      } catch (e) {
        Logger.debug('Error opening file: $e', category: 'IO');
        throw LuaError(e.toString());
      }
    } else {
      // First argument is nil, use default input
      Logger.debug(
        'Using default input for lines (nil argument)',
        category: 'IO',
      );
      Logger.debug('About to get defaultInput for nil case...', category: 'IO');
      file = IOLib.defaultInput;
      Logger.debug('Got defaultInput for nil case: $file', category: 'IO');
      formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
      if (formats.isEmpty) formats = ["l"];
      Logger.debug(
        'About to call file.lines() for nil case with formats: $formats...',
        category: 'IO',
      );
      return await file.lines(formats);
    }
  }
}

class IOOpen implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO open', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Missing filename', category: 'IO');
      return Value.multi([null, "missing filename"]);
    }

    final filename = (args[0] as Value).raw.toString();
    final mode = args.length > 1 ? (args[1] as Value).raw.toString() : "r";
    Logger.debug('Opening file: $filename with mode: $mode', category: 'IO');

    try {
      final device = await IOLib.fileSystemProvider.openFile(filename, mode);
      final file = LuaFile(device);
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error opening file: $e', category: 'IO');

      // Invalid mode should throw (not return tuple)
      if (e is LuaError && e.message == "invalid mode") {
        rethrow;
      }

      // File system errors should return tuple
      final errno = io_abs.extractOsErrorCode(e);
      return Value.multi([null, e.toString(), errno]);
    }
  }
}

class IOOutput implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('IOOutput.call() started', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('No args - returning default output', category: 'IO');
      return Value(IOLib.defaultOutput, metatable: IOLib.fileClass.metamethods);
    }

    Logger.debug('IOOutput.call() processing arguments', category: 'IO');
    LuaFile? newFile;
    Value? result;

    if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Arg is LuaFile - setting as output', category: 'IO');
      newFile = (args[0] as Value).raw as LuaFile;
      result = args[0] as Value;
    } else {
      final filename = (args[0] as Value).raw.toString();
      Logger.debug('Arg is filename: $filename - opening file', category: 'IO');

      Logger.debug('About to call fileSystemProvider.openFile', category: 'IO');
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "w");
        Logger.debug('fileSystemProvider.openFile succeeded', category: 'IO');

        Logger.debug('Creating LuaFile wrapper', category: 'IO');
        newFile = LuaFile(device);
        Logger.debug('Creating Value wrapper', category: 'IO');
        result = Value(newFile, metatable: IOLib.fileClass.metamethods);
        Logger.debug('File opening complete', category: 'IO');
      } catch (e) {
        Logger.debug('File opening failed: $e', category: 'IO');
        rethrow;
      }
    }

    Logger.debug('About to handle current default output', category: 'IO');
    // Avoid hanging - just set the new output without closing problematic files
    if (IOLib._defaultOutput?.raw is LuaFile &&
        (IOLib._defaultOutput!.raw as LuaFile).device is! StdoutDevice) {
      Logger.debug('Current output is not stdout - replacing', category: 'IO');
      // Don't attempt to close - just replace the reference
      IOLib._defaultOutput = null;
    }

    Logger.debug('Setting new default output', category: 'IO');
    IOLib._defaultOutput = result;
    IOLib._defaultOutputExplicitlyClosed =
        false; // Reset the flag when setting new output
    Logger.debug(
      'Reset _defaultOutputExplicitlyClosed to false',
      category: 'IO',
    );
    Logger.debug('IOOutput.call() completed', category: 'IO');
    return result;
  }
}

class IOPopen implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO popen', category: 'IO');
    if (args.isEmpty) {
      throw LuaError.typeError("io.popen requires a command string");
    }

    final cmd = (args[0] as Value).raw.toString();
    var mode = args.length > 1 ? (args[1] as Value).raw.toString() : 'r';

    // Only 'r' or 'w' (optionally with trailing 'b') are valid for popen
    if (mode.endsWith('b')) {
      mode = mode.substring(0, mode.length - 1);
    }
    if (mode != 'r' && mode != 'w') {
      throw LuaError('invalid mode');
    }

    try {
      final device = await ProcessIODevice.start(cmd, mode);
      final file = PopenLuaFile(device);
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error starting popen process: $e', category: 'IO');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IORead implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO read', category: 'IO');

    final formats = args.isEmpty
        ? ["l"]
        : args.map((e) => (e as Value).raw.toString()).toList();
    Logger.debug('Reading with formats: $formats', category: 'IO');
    final results = <Object?>[];
    bool encounteredFailure = false;

    for (final format in formats) {
      if (encounteredFailure) {
        // If any previous read failed, all subsequent reads return nil
        results.add(null);
        continue;
      }

      Logger.debug('Reading format: $format', category: 'IO');

      try {
        final result = await IOLib.defaultInput.read(format);
        if (format == '1') {
          final v = result.isNotEmpty ? result[0] : null;
          if (v is LuaString) {
            Logger.debug(
              'IORead(1): byte=${v.bytes.isNotEmpty ? v.bytes[0] : 'nil'}',
              category: 'IO',
            );
          } else {
            Logger.debug('IORead(1): non-LuaString value=$v', category: 'IO');
          }
        }

        // Check if this is an error or EOF condition
        if (result[0] == null && result.length > 1 && result[1] != null) {
          // This is an error
          Logger.debug('Error reading format: ${result[1]}', category: 'IO');
          return Value.multi(result);
        }

        if (result[0] == null) {
          // This read failed (EOF or parse error), mark failure for subsequent reads
          encounteredFailure = true;
        }

        // Even if null (EOF), add it to results
        results.add(result[0]);
      } catch (e) {
        // Catch device-level errors and convert to expected error message
        Logger.debug(
          'IORead caught exception: ${e.toString()}',
          category: 'IO',
        );
        if (e.toString().contains("attempt to use a closed file")) {
          Logger.debug(
            'Converting closed file error to input file closed',
            category: 'IO',
          );
          throw LuaError(" input file is closed");
        }
        // Re-throw other errors as-is
        Logger.debug('Re-throwing exception as-is', category: 'IO');
        rethrow;
      }
    }

    return Value.multi(results);
  }
}

class IOTmpfile implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO tmpfile', category: 'IO');
    try {
      final device = await IOLib.fileSystemProvider.createTempFile('lua_temp');
      final file = LuaFile(device);
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error creating temporary file: $e', category: 'IO');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOType implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO type', category: 'IO');
    if (args.isEmpty) return Value(null);

    final obj = args[0] as Value;
    if (obj.raw is! LuaFile) return Value(null);

    final file = obj.raw as LuaFile;
    final type = file.isClosed ? "closed file" : "file";
    Logger.debug('File type: $type', category: 'IO');
    return Value(type);
  }
}

class IOWrite implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO write', category: 'IO');

    // Check if default output was explicitly closed
    Logger.debug(
      'Checking _defaultOutputExplicitlyClosed: ${IOLib._defaultOutputExplicitlyClosed}',
      category: 'IO',
    );
    if (IOLib._defaultOutputExplicitlyClosed) {
      Logger.debug(
        'Default output was explicitly closed, throwing error',
        category: 'IO',
      );
      throw LuaError(" output file is closed");
    }

    if (args.isEmpty) {
      Logger.debug('No arguments to write', category: 'IO');
      return Value.multi([true]);
    }

    for (final arg in args) {
      final val = arg as Value;
      try {
        if (val.raw is LuaString) {
          final bytes = (val.raw as LuaString).bytes;
          Logger.debug('Writing ${bytes.length} raw bytes', category: 'IO');
          final result = await IOLib.defaultOutput.writeBytes(bytes);
          if (result[0] == null) {
            Logger.debug(
              'Error writing raw bytes: ${result[1]}',
              category: 'IO',
            );
            return Value.multi(result);
          }
        } else {
          final str = val.raw.toString();
          Logger.debug('Writing string: $str', category: 'IO');
          final result = await IOLib.defaultOutput.write(str);
          if (result[0] == null) {
            Logger.debug('Error writing: ${result[1]}', category: 'IO');
            return Value.multi(result);
          }
        }
      } catch (e) {
        // Catch device-level errors and convert to expected error message
        Logger.debug(
          'IOWrite caught exception: ${e.toString()}',
          category: 'IO',
        );
        if (e.toString().contains("attempt to use a closed file")) {
          Logger.debug(
            'Converting closed file error to output file closed',
            category: 'IO',
          );
          throw LuaError(" output file is closed");
        }
        // Re-throw other errors as-is
        Logger.debug('Re-throwing exception as-is', category: 'IO');
        rethrow;
      }
    }

    return IOLib._defaultOutput ??
        Value(IOLib.defaultOutput, metatable: IOLib.fileClass.metamethods);
  }
}

// File method implementations that work on LuaFile objects
class FileClose implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: close', category: 'IO');

    if (args.isEmpty) {
      throw LuaError("got no value");
    }

    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }

    final luaFile = file.raw as LuaFile;

    // Check if this is a standard file (stdin, stdout, stderr)
    if (IOClose._isStandardFile(luaFile)) {
      Logger.debug('Cannot close standard file', category: 'IO');
      return Value(false); // Standard files cannot be closed
    }

    final result = await luaFile.close();

    // If this file was the current default output, reset it to stdout
    if (IOLib._defaultOutput?.raw == luaFile) {
      Logger.debug(
        'Resetting default output to stdout after file close',
        category: 'IO',
      );
      IOLib._defaultOutput = null;
      IOLib._defaultOutputExplicitlyClosed = false; // Reset the flag
    }

    // Similarly for default input
    if (luaFile == IOLib._defaultInput) {
      Logger.debug(
        'Resetting default input to stdin after file close',
        category: 'IO',
      );
      IOLib._defaultInput = null;
    }

    return Value.multi(result);
  }
}

class FileFlush implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: flush', category: 'IO');
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }
    final result = await (file.raw as LuaFile).flush();
    return Value.multi(result);
  }
}

class FileRead implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: read', category: 'IO');
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final formats = actualArgs.isNotEmpty
        ? actualArgs.map((e) => (e as Value).raw.toString()).toList()
        : ["l"];

    final luaFile = file.raw as LuaFile;
    final results = <Object?>[];
    bool encounteredFailure = false;

    for (final format in formats) {
      if (encounteredFailure) {
        // If any previous read failed, all subsequent reads return nil
        results.add(null);
        continue;
      }

      final result = await luaFile.read(format);
      if (result[0] == null && result.length > 1 && result[1] != null) {
        // This is an error (not just EOF), return the error immediately
        return Value.multi(result);
      }

      if (result[0] == null) {
        // This read failed (EOF or parse error), mark failure for subsequent reads
        encounteredFailure = true;
      }

      results.add(result[0]);
    }

    return Value.multi(results);
  }
}

class FileWrite implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: write', category: 'IO');
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    // In Lua, file:write returns the file handle on success to allow chaining.
    // Even when called with no arguments, it should return the file itself.
    if (actualArgs.isEmpty) {
      return file;
    }

    final luaFile = file.raw as LuaFile;
    for (final arg in actualArgs) {
      final val = arg as Value;
      List<Object?> result;
      if (val.raw is LuaString) {
        final bytes = (val.raw as LuaString).bytes;
        Logger.debug('File:write raw ${bytes.length} bytes', category: 'IO');
        result = await luaFile.writeBytes(bytes);
      } else {
        final str = val.raw.toString();
        result = await luaFile.write(str);
      }
      if (result[0] == null) {
        // On failure, propagate the (nil, errmsg[, errno]) tuple.
        return Value.multi(result);
      }
    }
    // Success: return the file handle (self) for chaining.
    return file;
  }
}

class FileSeek implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: seek', category: 'IO');
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final whence = actualArgs.isNotEmpty
        ? (actualArgs[0] as Value).raw.toString()
        : "cur";
    final offset = actualArgs.length > 1
        ? (actualArgs[1] as Value).raw as int
        : 0;

    final result = await (file.raw as LuaFile).seek(whence, offset);
    return Value.multi(result);
  }
}

class FileLines implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: lines', category: 'IO');
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final formats = actualArgs.isNotEmpty
        ? actualArgs.map((e) => (e as Value).raw.toString()).toList()
        : ["l"];

    final result = await (file.raw as LuaFile).lines(formats);
    return result;
  }
}

class FileSetvbuf implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: setvbuf', category: 'IO');
    if (args.isEmpty) {
      throw LuaError("got no value");
    }
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }

    // Skip self parameter
    final actualArgs = args.skip(1).toList();
    final mode = actualArgs.isNotEmpty
        ? (actualArgs[0] as Value).raw.toString()
        : 'full';
    final size = actualArgs.length > 1
        ? NumberUtils.toInt((actualArgs[1] as Value).raw)
        : null;

    final result = await (file.raw as LuaFile).setvbuf(mode, size);
    return Value.multi(result);
  }
}

void defineIOLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  Logger.debug('Defining IO library', category: 'IO');
  final ioTable = <String, dynamic>{};
  IOLib.functions.forEach((key, value) {
    ioTable[key] = value;
  });

  Logger.debug('Adding standard streams', category: 'IO');
  // Use the singleton instances
  ioTable["stdin"] = Value(
    LuaFile(IOLib.stdinDevice),
    metatable: IOLib.fileClass.metamethods,
  );
  ioTable["stdout"] = Value(
    LuaFile(IOLib.stdoutDevice),
    metatable: IOLib.fileClass.metamethods,
  );
  ioTable["stderr"] = Value(
    LuaFile(IOLib.stderrDevice),
    metatable: IOLib.fileClass.metamethods,
  );

  env.define("io", ioTable);
  Logger.debug('IO library defined', category: 'IO');
}
