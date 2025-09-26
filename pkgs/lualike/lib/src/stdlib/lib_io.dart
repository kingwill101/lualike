import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/utils/io_abstractions.dart' as io_abs;
import 'package:lualike/src/value.dart';

import '../io/filesystem_provider.dart';
import '../io/io_device.dart';
import '../io/lua_file.dart';
import 'library.dart';

/// IO library implementation using the new Library system
class IOLibrary extends Library {
  @override
  String get name => "io";

  @override
  Map<String, Function>? getMetamethods(Interpreter interpreter) => null;

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Register all IO functions directly
    context.define("close", IOClose());
    context.define("flush", IOFlush());
    context.define("input", IOInput());
    context.define("lines", IOLines());
    context.define("open", IOOpen());
    context.define("output", IOOutput());
    context.define("popen", IOPopen());
    context.define("read", IORead());
    context.define("tmpfile", IOTmpfile());
    context.define("type", IOType());
    context.define("write", IOWrite());

    // Add standard streams
    context.define(
      "stdin",
      createLuaFile(IOLib.stdinDevice, isStandardFile: true),
    );
    context.define(
      "stdout",
      createLuaFile(IOLib.stdoutDevice, isStandardFile: true),
    );
    context.define(
      "stderr",
      createLuaFile(IOLib.stderrDevice, isStandardFile: true),
    );
  }
}

LuaFile? extractLuaFile(dynamic value) {
  if (value is LuaFile) {
    // already a LuaFile
    return value;
  }
  if (value is Value && value.raw is LuaFile) {
    // wrapped in a Value
    return value.raw as LuaFile;
  }
  return null;
}

/// Helper function to check if a value represents a LuaFile
bool isLuaFile(dynamic value) {
  return value is LuaFile || (value is Value && value.raw is LuaFile);
}

class IOLib {
  // Singleton instances for standard devices
  static StdinDevice? _stdinDevice;
  static StdoutDevice? _stdoutDevice;
  static StdoutDevice? _stderrDevice;

  // File system provider - defaults to local file system
  static FileSystemProvider? _fileSystemProvider;

  static Value? _defaultInput;
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

  static Value get defaultInput {
    Logger.debug('Getting default input', category: 'IO');
    Logger.debug('Current _defaultInput: $_defaultInput', category: 'IO');
    if (_defaultInput == null) {
      Logger.debug(
        'Creating new default input with stdinDevice',
        category: 'IO',
      );
      _defaultInput = createLuaFile(stdinDevice);
      Logger.debug('Created default input: $_defaultInput', category: 'IO');
    } else {
      Logger.debug(
        'Using existing default input: $_defaultInput',
        category: 'IO',
      );
    }
    return _defaultInput!;
  }

  static set defaultInput(Value? file) {
    _defaultInput = file;
  }

  static Value get defaultOutput {
    Logger.debug('Getting default output');
    _defaultOutput ??= createLuaFile(stdoutDevice);
    return _defaultOutput!;
  }

  static set defaultOutput(Value? file) {
    _defaultOutput = file;
  }

  static Future<void> reset() async {
    if (_defaultInput != null && _defaultInput!.raw is LuaFile) {
      final luaFile = _defaultInput!.raw as LuaFile;
      if (luaFile.device is! StdinDevice) {
        await luaFile.close();
      }
    }
    _defaultInput = null;

    if (_defaultOutput != null && _defaultOutput!.raw is LuaFile) {
      final luaFile = _defaultOutput!.raw as LuaFile;
      if (luaFile.device is! StdoutDevice) {
        await luaFile.close();
      }
    }
    _defaultOutput = null;
    _defaultOutputExplicitlyClosed = false;
  }
}

class IOClose extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO close', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Closing default output', category: 'IO');
      final defaultOutput = IOLib.defaultOutput;
      final luaFile = defaultOutput.raw as LuaFile;
      final result = await luaFile.close();
      IOLib._defaultOutputExplicitlyClosed = true;
      Logger.debug(
        'Set _defaultOutputExplicitlyClosed to true',
        category: 'IO',
      );
      IOLib._defaultOutput = null; // Reset to stdout on next access
      return Value.multi(result);
    }

    final file = args[0];
    if (!isLuaFile(file)) {
      Logger.debug('Attempt to close non-file object', category: 'IO');
      return Value.multi([null, "attempt to close a non-file object"]);
    }

    Logger.debug('Closing file', category: 'IO');
    final luaFile = extractLuaFile(file)!;

    // Check if this is a standard file (stdin, stdout, stderr)
    if (luaFile.isStandardFile) {
      Logger.debug('Cannot close standard file', category: 'IO');
      return Value(false); // Standard files cannot be closed
    }

    // Check if file is already closed
    if (luaFile.isClosed) {
      Logger.debug('File is already closed', category: 'IO');

      // Special handling for default input/output files
      // If this is the default input or output file that was closed (e.g., by GC),
      // we should return success rather than throwing an error
      if ((IOLib._defaultInput != null &&
              IOLib._defaultInput!.raw == luaFile) ||
          (IOLib._defaultOutput != null &&
              IOLib._defaultOutput!.raw == luaFile)) {
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
    if (IOLib._defaultOutput != null && IOLib._defaultOutput!.raw == luaFile) {
      // When closing the current output file, revert to stdout
      Logger.debug('Resetting default output to stdout', category: 'IO');
      IOLib._defaultOutput = null;
    }

    // Note: We don't reset _defaultInput to null here because we want
    // subsequent io.read calls to detect the closed file and throw an error
    return Value.multi(result);
  }
}

class IOFlush extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO flush', category: 'IO');
    final defaultOutput = IOLib.defaultOutput;
    final luaFile = defaultOutput.raw as LuaFile;
    final result = await luaFile.flush();
    return Value.multi(result);
  }
}

class IOInput extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO input', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Returning default input', category: 'IO');
      return IOLib.defaultInput;
    }

    Value? newFile;
    Object? result;

    if (isLuaFile(args[0])) {
      Logger.debug('Setting default input to provided file', category: 'IO');
      newFile = args[0] as Value;
      result = args[0];
    } else {
      final filename = (args[0] as Value).raw.toString();
      Logger.debug('Opening file for input: $filename', category: 'IO');
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        newFile = createLuaFile(device);
        result = newFile;
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

class IOLines extends BuiltinFunction {
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

    Value fileValue;
    List<String> formats;

    if (args.isEmpty) {
      Logger.debug('Using default input for lines (no args)', category: 'IO');
      Logger.debug('About to get defaultInput...', category: 'IO');
      fileValue = IOLib.defaultInput;
      Logger.debug('Got defaultInput: $fileValue', category: 'IO');
      formats = ["l"];
      Logger.debug('About to call file.lines()...', category: 'IO');
      final luaFile = fileValue.raw as LuaFile;
      return await luaFile.lines(formats);
    } else if (isLuaFile(args[0])) {
      Logger.debug('Using provided file for lines', category: 'IO');
      fileValue = args[0] as Value;
      final luaFile = fileValue.raw as LuaFile;
      formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
      if (formats.isEmpty) formats = ["l"];
      return await luaFile.lines(formats);
    } else if (args[0] is Value && (args[0] as Value).raw != null) {
      Logger.debug('Opening new file for lines', category: 'IO');
      final filename = (args[0] as Value).raw.toString();
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        fileValue = createLuaFile(device);
        final luaFile = fileValue.raw as LuaFile;
        formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
        if (formats.isEmpty) formats = ["l"];
        final iterator = await luaFile.lines(
          formats,
          true,
        ); // closeOnEof = true for io.lines(filename)

        // Return iterator, dummy state/control (nil), and a to-be-closed variable
        // Get current Library metamethods from interpreter
        final toClose = Value.toBeClose(fileValue);
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
      fileValue = IOLib.defaultInput;
      Logger.debug('Got defaultInput for nil case: $fileValue', category: 'IO');
      final luaFile = fileValue.raw as LuaFile;
      formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
      if (formats.isEmpty) formats = ["l"];
      Logger.debug(
        'About to call file.lines() for nil case with formats: $formats...',
        category: 'IO',
      );
      return await luaFile.lines(formats);
    }
  }
}

class IOOpen extends BuiltinFunction {
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
      return createLuaFile(device);
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

class IOOutput extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('IOOutput.call() started', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('No args - returning default output', category: 'IO');
      return IOLib.defaultOutput;
    }

    Logger.debug('IOOutput.call() processing arguments', category: 'IO');
    Value? newFile;

    if (isLuaFile(args[0])) {
      Logger.debug('Arg is LuaFile - setting as output', category: 'IO');
      newFile = args[0] as Value;
    } else {
      final filename = (args[0] as Value).raw.toString();
      Logger.debug('Arg is filename: $filename - opening file', category: 'IO');

      Logger.debug('About to call fileSystemProvider.openFile', category: 'IO');
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "w");
        Logger.debug('fileSystemProvider.openFile succeeded', category: 'IO');

        Logger.debug('Creating LuaFile wrapper', category: 'IO');
        newFile = createLuaFile(device);
        Logger.debug('File opening complete', category: 'IO');
      } catch (e) {
        Logger.debug('File opening failed: $e', category: 'IO');
        rethrow;
      }
    }

    Logger.debug('About to handle current default output', category: 'IO');
    // Avoid hanging - just set the new output without closing problematic files
    if (IOLib._defaultOutput != null &&
        IOLib._defaultOutput!.raw is LuaFile &&
        (IOLib._defaultOutput!.raw as LuaFile).device is! StdoutDevice) {
      Logger.debug('Current output is not stdout - replacing', category: 'IO');
      // Don't attempt to close - just replace the reference
      IOLib._defaultOutput = null;
    }

    Logger.debug('Setting new default output', category: 'IO');
    IOLib._defaultOutput = newFile;
    IOLib._defaultOutputExplicitlyClosed =
        false; // Reset the flag when setting new output
    Logger.debug(
      'Reset _defaultOutputExplicitlyClosed to false',
      category: 'IO',
    );
    Logger.debug('IOOutput.call() completed', category: 'IO');
    return newFile;
  }
}

class IOPopen extends BuiltinFunction {
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
      return Value(file, metatable: fileMetamethods);
    } catch (e) {
      Logger.debug('Error starting popen process: $e', category: 'IO');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IORead extends BuiltinFunction {
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
        final defaultInput = IOLib.defaultInput;
        final luaFile = defaultInput.raw as LuaFile;
        final result = await luaFile.read(format);
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

class IOTmpfile extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO tmpfile', category: 'IO');
    try {
      final device = await IOLib.fileSystemProvider.createTempFile('lua_temp');
      return createLuaFile(device);
    } catch (e) {
      Logger.debug('Error creating temporary file: $e', category: 'IO');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOType extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO type', category: 'IO');
    if (args.isEmpty) return Value(null);

    final obj = args[0];
    if (!isLuaFile(obj)) return Value(null);

    final file = extractLuaFile(obj)!;
    final type = file.isClosed ? "closed file" : "file";
    Logger.debug('File type: $type', category: 'IO');
    return Value(type);
  }
}

class IOWrite extends BuiltinFunction {
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
        final defaultOutput = IOLib.defaultOutput;
        final luaFile = defaultOutput.raw as LuaFile;
        if (val.raw is LuaString) {
          final bytes = (val.raw as LuaString).bytes;
          Logger.debug('Writing ${bytes.length} raw bytes', category: 'IO');
          final result = await luaFile.writeBytes(bytes);
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
          final result = await luaFile.write(str);
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

    // Get current Library metamethods from interpreter
    if (IOLib._defaultOutput != null) {
      return IOLib._defaultOutput;
    }
    return IOLib.defaultOutput;
  }
}

// File method implementations that work on LuaFile objects
class FileClose extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: close', category: 'IO');

    if (args.isEmpty) {
      throw LuaError("got no value");
    }

    final file = args[0];
    if (!isLuaFile(file)) {
      Logger.debug(
        'Attempt to close non-file object file type: ${file.runtimeType} and value: $file',
        category: 'IO',
      );
      throw LuaError.typeError("file expected");
    }

    final luaFile = extractLuaFile(file)!;

    // Check if this is a standard file (stdin, stdout, stderr)
    if (luaFile.isStandardFile) {
      Logger.debug('Cannot close standard file', category: 'IO');
      return Value(false); // Standard files cannot be closed
    }

    final result = await luaFile.close();

    // If this file was the current default output, reset it to stdout
    if (IOLib._defaultOutput != null && IOLib._defaultOutput!.raw == luaFile) {
      Logger.debug(
        'Resetting default output to stdout after file close',
        category: 'IO',
      );
      IOLib._defaultOutput = null;
      IOLib._defaultOutputExplicitlyClosed = false; // Reset the flag
    }

    // Similarly for default input
    if (IOLib._defaultInput != null && IOLib._defaultInput!.raw == luaFile) {
      Logger.debug(
        'Resetting default input to stdin after file close',
        category: 'IO',
      );
      IOLib._defaultInput = null;
    }

    return Value.multi(result);
  }
}

class FileFlush extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: flush', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }
    final result = await extractLuaFile(file)!.flush();
    return Value.multi(result);
  }
}

class FileRead extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: read', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final formats = actualArgs.isNotEmpty
        ? actualArgs.map((e) => (e as Value).raw.toString()).toList()
        : ["l"];

    final luaFile = extractLuaFile(file)!;
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

class FileWrite extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: write', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    // In Lua, file:write returns the file handle on success to allow chaining.
    // Even when called with no arguments, it should return the file itself.
    if (actualArgs.isEmpty) {
      return file;
    }

    final luaFile = extractLuaFile(file)!;
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

class FileSeek extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: seek', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
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

    final result = await extractLuaFile(file)!.seek(whence, offset);
    return Value.multi(result);
  }
}

class FileLines extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: lines', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final formats = actualArgs.isNotEmpty
        ? actualArgs.map((e) => (e as Value).raw.toString()).toList()
        : ["l"];

    final result = await extractLuaFile(file)!.lines(formats);
    return result;
  }
}

class FileSetvbuf extends BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: setvbuf', category: 'IO');
    if (args.isEmpty) {
      throw LuaError("got no value");
    }
    final file = args[0];
    if (!isLuaFile(file)) {
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

    final result = await extractLuaFile(file)!.setvbuf(mode, size);
    return Value.multi(result);
  }
}

// void defineIOLibrary - removed as part of migration to Library system
