import 'dart:collection';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/utils/io_abstractions.dart' as io_abs;
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/utils/type.dart' show getLuaType;
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
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => null;

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final interpreter = context.interpreter;
    if (interpreter == null) {
      throw StateError('IO library requires interpreter instance');
    }

    // Register all IO functions directly with interpreter reference
    context.define("close", IOClose(interpreter));
    context.define("flush", IOFlush(interpreter));
    context.define("input", IOInput(interpreter));
    context.define("lines", IOLines(interpreter));
    context.define("open", IOOpen(interpreter));
    context.define("output", IOOutput(interpreter));
    context.define("popen", IOPopen(interpreter));
    context.define("read", IORead(interpreter));
    context.define("tmpfile", IOTmpfile(interpreter));
    context.define("type", IOType(interpreter));
    context.define("write", IOWrite(interpreter));

    // Add standard streams
    context.define(
      "stdin",
      IOLib._stdinValue = createLuaFile(
        IOLib.stdinDevice,
        isStandardFile: true,
        interpreter: context.interpreter,
      ),
    );
    context.define(
      "stdout",
      IOLib._stdoutValue = createLuaFile(
        IOLib.stdoutDevice,
        isStandardFile: true,
        interpreter: context.interpreter,
      ),
    );
    context.define(
      "stderr",
      createLuaFile(
        IOLib.stderrDevice,
        isStandardFile: true,
        interpreter: context.interpreter,
      ),
    );
  }
}

String _ioString(Object? value) => rawLuaSlot(value).toString();

List<String> _ioStringList(Iterable<Object?> values) =>
    values.map(_ioString).toList();

bool _isIOString(Object? value) {
  final raw = rawLuaSlot(value);
  return raw is String || raw is LuaString;
}

LuaFile? extractLuaFile(dynamic value) {
  final raw = rawLuaSlot(value);
  return raw is LuaFile ? raw : null;
}

/// Helper function to check if a value represents a LuaFile
bool isLuaFile(dynamic value) => extractLuaFile(value) != null;

bool _isLuaFileWrapperFor(Value? value, LuaFile file) =>
    identical(extractLuaFile(value), file);

class IOLib {
  // Singleton instances for standard devices
  static StdinDevice? _stdinDevice;
  static StdoutDevice? _stdoutDevice;
  static StdoutDevice? _stderrDevice;
  static Value? _stdinValue;
  static Value? _stdoutValue;

  // File system provider - defaults to local file system
  static FileSystemProvider? _fileSystemProvider;

  static Value? _defaultInput;
  static Value? _defaultOutput;
  static bool _defaultOutputExplicitlyClosed = false;

  static final Set<Value> _openFiles = HashSet<Value>(
    equals: identical,
    hashCode: identityHashCode,
  );

  static void _debugOpenFileLog(String message) {
    if (platform.getEnvironmentVariable('LUALIKE_DEBUG_FILE_OPS') == '1') {
      io_abs.stderr.writeln('[file-debug] $message');
    }
  }

  static List<Object?> get gcRoots {
    final roots = <Object?>[];
    final seen = Expando<bool>('ioGcRootsSeen');

    void add(Value? value) {
      if (value == null) return;
      if (seen[value] == true) return;
      seen[value] = true;
      roots.add(value);
    }

    add(_stdinValue);
    add(_stdoutValue);
    add(_defaultInput);
    add(_defaultOutput);
    return roots;
  }

  static void registerOpenFile(Value fileValue) {
    final luaFile = extractLuaFile(fileValue);
    if (luaFile != null) {
      if (!luaFile.isStandardFile) {
        _openFiles.add(fileValue);
        _debugOpenFileLog(
          'register fileValue=${identityHashCode(fileValue)} '
          'raw=${identityHashCode(luaFile)} '
          'device=${identityHashCode(luaFile.device)} '
          'openCount=${_openFiles.length}',
        );
      }
    }
  }

  static void unregisterOpenFile(Value fileValue) {
    if (extractLuaFile(fileValue) case final LuaFile luaFile) {
      _debugOpenFileLog(
        'unregister fileValue=${identityHashCode(fileValue)} '
        'raw=${identityHashCode(luaFile)} '
        'device=${identityHashCode(luaFile.device)} '
        'before=${_openFiles.length}',
      );
    }
    _openFiles.remove(fileValue);
  }

  static void unregisterOpenFileForLuaFile(LuaFile file) {
    _openFiles.removeWhere((value) => _isLuaFileWrapperFor(value, file));
  }

  static Value? trackedOpenFileWrapper(LuaFile file) {
    for (final value in _openFiles) {
      if (_isLuaFileWrapperFor(value, file)) {
        _debugOpenFileLog(
          'tracked-hit fileValue=${identityHashCode(value)} '
          'raw=${identityHashCode(file)} '
          'device=${identityHashCode(file.device)}',
        );
        return value;
      }
    }
    _debugOpenFileLog(
      'tracked-miss raw=${identityHashCode(file)} '
      'device=${identityHashCode(file.device)} '
      'openCount=${_openFiles.length}',
    );
    return null;
  }

  static bool isCurrentDefaultFile(LuaFile file) {
    return _isLuaFileWrapperFor(_defaultInput, file) ||
        _isLuaFileWrapperFor(_defaultOutput, file);
  }

  // Get singleton instances
  static StdinDevice get stdinDevice {
    Logger.debugLazy(() => 'Getting stdinDevice', category: 'IO');
    Logger.debugLazy(
      () => 'Current _stdinDevice: $_stdinDevice',
      category: 'IO',
    );
    if (_stdinDevice == null) {
      Logger.debugLazy(() => 'Creating new StdinDevice', category: 'IO');
      _stdinDevice = StdinDevice();
      Logger.debugLazy(
        () => 'Created StdinDevice: $_stdinDevice',
        category: 'IO',
      );
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
    Logger.debugLazy(
      () => 'Setting file system provider to: ${provider.providerName}',
      category: 'FileSystem',
    );
    _fileSystemProvider = provider;
  }

  // Setters to allow custom devices (similar to what you mentioned exists for stdio)
  static set stdinDevice(StdinDevice device) {
    _stdinDevice = device;
    _stdinValue = null;
  }

  static set stdoutDevice(StdoutDevice device) {
    _stdoutDevice = device;
    _stdoutValue = null;
  }

  static set stderrDevice(StdoutDevice device) {
    _stderrDevice = device;
  }

  static Value get defaultInput {
    Logger.debugLazy(() => 'Getting default input', category: 'IO');
    Logger.debugLazy(
      () => 'Current _defaultInput: $_defaultInput',
      category: 'IO',
    );
    if (_defaultInput == null) {
      Logger.debugLazy(
        () => 'Creating new default input with stdinDevice',
        category: 'IO',
      );
      _defaultInput =
          _stdinValue ?? createLuaFile(stdinDevice, isStandardFile: true);
      Logger.debugLazy(
        () => 'Created default input: $_defaultInput',
        category: 'IO',
      );
    } else {
      Logger.debugLazy(
        () => 'Using existing default input: $_defaultInput',
        category: 'IO',
      );
    }
    return _defaultInput!;
  }

  static set defaultInput(Value? file) {
    _defaultInput = file;
  }

  static Value get defaultOutput {
    Logger.debugLazy(() => 'Getting default output');
    // Note: interpreter is set when initially registering stdout with the library
    _defaultOutput ??=
        _stdoutValue ?? createLuaFile(stdoutDevice, isStandardFile: true);
    return _defaultOutput!;
  }

  static set defaultOutput(Value? file) {
    _defaultOutput = file;
  }

  static Future<void> reset() async {
    final defaultInputFile = extractLuaFile(_defaultInput);
    if (defaultInputFile != null) {
      final luaFile = defaultInputFile;
      if (luaFile.device is! StdinDevice) {
        await luaFile.close();
        IOLib.unregisterOpenFileForLuaFile(luaFile);
      }
    }
    _defaultInput = null;

    final defaultOutputFile = extractLuaFile(_defaultOutput);
    if (defaultOutputFile != null) {
      final luaFile = defaultOutputFile;
      if (luaFile.device is! StdoutDevice) {
        await luaFile.close();
        IOLib.unregisterOpenFileForLuaFile(luaFile);
      }
    }
    _defaultOutput = null;
    _defaultOutputExplicitlyClosed = false;
    _stdinValue = null;
    _stdoutValue = null;
  }
}

class IOClose extends BuiltinFunction {
  IOClose([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO close', category: 'IO');
    if (args.isEmpty) {
      Logger.debugLazy(() => 'Closing default output', category: 'IO');
      final defaultOutput = IOLib.defaultOutput;
      final luaFile = extractLuaFile(defaultOutput)!;
      final result = await luaFile.close();
      IOLib._defaultOutputExplicitlyClosed = true;
      Logger.debugLazy(
        () => 'Set _defaultOutputExplicitlyClosed to true',
        category: 'IO',
      );
      IOLib._defaultOutput = null; // Reset to stdout on next access
      if (result.isNotEmpty && result[0] == true) {
        IOLib.unregisterOpenFileForLuaFile(luaFile);
      }
      return LuaResults(result);
    }

    final file = args[0];
    if (!isLuaFile(file)) {
      Logger.debugLazy(
        () => 'Attempt to close non-file object',
        category: 'IO',
      );
      return LuaResults([null, "attempt to close a non-file object"]);
    }

    Logger.debugLazy(() => 'Closing file', category: 'IO');
    final luaFile = extractLuaFile(file)!;

    // Check if this is a standard file (stdin, stdout, stderr)
    if (luaFile.isStandardFile) {
      Logger.debugLazy(() => 'Cannot close standard file', category: 'IO');
      return primitiveValue(false); // Standard files cannot be closed
    }

    // Check if file is already closed
    if (luaFile.isClosed) {
      Logger.debugLazy(() => 'File is already closed', category: 'IO');

      // Special handling for default input/output files
      // If this is the default input or output file that was closed (e.g., by GC),
      // we should return success rather than throwing an error
      if (IOLib.isCurrentDefaultFile(luaFile)) {
        Logger.debugLazy(
          () => 'Default input/output file already closed, returning success',
          category: 'IO',
        );
        return LuaResults([true]);
      }

      // For other files, throw an error as expected
      throw LuaError("closed file");
    }

    final result = await luaFile.close();
    if (result.isNotEmpty && result[0] == true) {
      IOLib.unregisterOpenFileForLuaFile(luaFile);
    }
    if (result.isNotEmpty && result[0] == true) {
      IOLib.unregisterOpenFileForLuaFile(luaFile);
    }
    if (_isLuaFileWrapperFor(IOLib._defaultOutput, luaFile)) {
      // When closing the current output file, revert to stdout
      Logger.debugLazy(
        () => 'Resetting default output to stdout',
        category: 'IO',
      );
      IOLib._defaultOutput = null;
    }

    // Note: We don't reset _defaultInput to null here because we want
    // subsequent io.read calls to detect the closed file and throw an error
    return LuaResults(result);
  }
}

class IOFlush extends BuiltinFunction {
  IOFlush([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO flush', category: 'IO');
    final defaultOutput = IOLib.defaultOutput;
    final luaFile = extractLuaFile(defaultOutput)!;
    final result = await luaFile.flush();
    return LuaResults(result);
  }
}

class IOInput extends BuiltinFunction {
  IOInput([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO input', category: 'IO');
    if (args.isEmpty) {
      Logger.debugLazy(() => 'Returning default input', category: 'IO');
      return IOLib.defaultInput;
    }

    Value? newFile;
    Object? result;

    if (isLuaFile(args[0])) {
      Logger.debugLazy(
        () => 'Setting default input to provided file',
        category: 'IO',
      );
      newFile = args[0] as Value;
      result = args[0];
    } else {
      final argument = args[0] as Value;
      if (!_isIOString(argument)) {
        throw LuaError.typeError(
          "bad argument #1 to 'input' (FILE* expected, got ${getLuaType(argument)})",
        );
      }
      final filename = _ioString(argument);
      Logger.debugLazy(
        () => 'Opening file for input: $filename',
        category: 'IO',
      );
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        newFile = createLuaFile(device, interpreter: interpreter);
        result = newFile;
      } catch (e) {
        Logger.debugLazy(() => 'Error opening file: $e', category: 'IO');
        // Match Lua's behavior: throw an error instead of returning error values
        throw LuaError("cannot open file '$filename' ($e)");
      }
    }

    // Do not auto-close the previous default input (matches Lua semantics),
    // but once it is no longer the default handle it should not stay pinned as
    // an interpreter-global GC root solely through _openFiles.
    final previousDefault = IOLib._defaultInput;
    if (!identical(previousDefault, newFile)) {
      if (previousDefault != null) {
        IOLib.unregisterOpenFile(previousDefault);
      }
      IOLib._defaultInput = newFile;
    }
    return result;
  }
}

class IOLines extends BuiltinFunction {
  IOLines([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(
      () => 'Executing IO lines with ${args.length} args',
      category: 'IO',
    );

    // Log the arguments
    for (int i = 0; i < args.length; i++) {
      final arg = args[i] as Value;
      final rawArg = rawLuaSlot(arg);
      Logger.debugLazy(
        () => 'Arg $i: $rawArg (type: ${rawArg.runtimeType})',
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
      Logger.debugLazy(
        () => 'Using default input for lines (no args)',
        category: 'IO',
      );
      Logger.debugLazy(() => 'About to get defaultInput...', category: 'IO');
      fileValue = IOLib.defaultInput;
      Logger.debugLazy(() => 'Got defaultInput: $fileValue', category: 'IO');
      formats = ["l"];
      Logger.debugLazy(() => 'About to call file.lines()...', category: 'IO');
      final luaFile = extractLuaFile(fileValue)!;
      return await luaFile.lines(formats, false, fileValue);
    } else if (isLuaFile(args[0])) {
      Logger.debugLazy(() => 'Using provided file for lines', category: 'IO');
      fileValue = args[0] as Value;
      final luaFile = extractLuaFile(fileValue)!;
      formats = _ioStringList(args.skip(1));
      if (formats.isEmpty) formats = ["l"];
      return await luaFile.lines(formats, false, fileValue);
    } else if (rawLuaSlot(args[0]) != null) {
      Logger.debugLazy(() => 'Opening new file for lines', category: 'IO');
      final filename = _ioString(args[0]);
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        final luaFile = LuaFile(device);
        formats = _ioStringList(args.skip(1));
        if (formats.isEmpty) formats = ["l"];
        final toClose = wrapLuaFileValue(luaFile);
        final iterator = await luaFile.lines(
          formats,
          true,
          toClose,
        ); // closeOnEof = true for io.lines(filename)
        return LuaResults([
          iterator,
          primitiveValue(null),
          primitiveValue(null),
          toClose,
        ]);
      } catch (e) {
        Logger.debugLazy(() => 'Error opening file: $e', category: 'IO');
        throw LuaError(e.toString());
      }
    } else {
      // First argument is nil, use default input
      Logger.debugLazy(
        () => 'Using default input for lines (nil argument)',
        category: 'IO',
      );
      Logger.debugLazy(
        () => 'About to get defaultInput for nil case...',
        category: 'IO',
      );
      fileValue = IOLib.defaultInput;
      Logger.debugLazy(
        () => 'Got defaultInput for nil case: $fileValue',
        category: 'IO',
      );
      final luaFile = extractLuaFile(fileValue)!;
      formats = _ioStringList(args.skip(1));
      if (formats.isEmpty) formats = ["l"];
      Logger.debugLazy(
        () =>
            'About to call file.lines() for nil case with formats: $formats...',
        category: 'IO',
      );
      return await luaFile.lines(formats, false, fileValue);
    }
  }
}

class IOOpen extends BuiltinFunction {
  IOOpen([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO open', category: 'IO');
    if (args.isEmpty) {
      Logger.debugLazy(() => 'Missing filename', category: 'IO');
      return LuaResults([null, "missing filename"]);
    }

    final filename = _ioString(args[0]);
    final mode = args.length > 1 ? _ioString(args[1]) : "r";
    Logger.debugLazy(
      () => 'Opening file: $filename with mode: $mode',
      category: 'IO',
    );

    try {
      final device = await IOLib.fileSystemProvider.openFile(filename, mode);
      return createLuaFile(device, interpreter: interpreter);
    } catch (e) {
      Logger.debugLazy(() => 'Error opening file: $e', category: 'IO');

      // Invalid mode should throw (not return tuple)
      if (e is LuaError && e.message == "invalid mode") {
        rethrow;
      }

      // File system errors should return tuple
      final errno = io_abs.extractOsErrorCode(e);
      return LuaResults([null, e.toString(), errno]);
    }
  }
}

class IOOutput extends BuiltinFunction {
  IOOutput([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'IOOutput.call() started', category: 'IO');
    if (args.isEmpty) {
      Logger.debugLazy(
        () => 'No args - returning default output',
        category: 'IO',
      );
      return IOLib.defaultOutput;
    }

    Logger.debugLazy(
      () => 'IOOutput.call() processing arguments',
      category: 'IO',
    );
    Value? newFile;

    if (isLuaFile(args[0])) {
      Logger.debugLazy(
        () => 'Arg is LuaFile - setting as output',
        category: 'IO',
      );
      newFile = args[0] as Value;
    } else {
      final argument = args[0] as Value;
      if (!_isIOString(argument)) {
        throw LuaError.typeError(
          "bad argument #1 to 'output' (FILE* expected, got ${getLuaType(argument)})",
        );
      }
      final filename = _ioString(argument);
      Logger.debugLazy(
        () => 'Arg is filename: $filename - opening file',
        category: 'IO',
      );

      Logger.debugLazy(
        () => 'About to call fileSystemProvider.openFile',
        category: 'IO',
      );
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "w");
        Logger.debugLazy(
          () => 'fileSystemProvider.openFile succeeded',
          category: 'IO',
        );

        Logger.debugLazy(() => 'Creating LuaFile wrapper', category: 'IO');
        newFile = createLuaFile(device, interpreter: interpreter);
        Logger.debugLazy(() => 'File opening complete', category: 'IO');
      } catch (e) {
        Logger.debugLazy(() => 'File opening failed: $e', category: 'IO');
        rethrow;
      }
    }

    Logger.debugLazy(
      () => 'About to handle current default output',
      category: 'IO',
    );
    // Avoid hanging - just set the new output without closing problematic files
    final previousDefault = IOLib._defaultOutput;
    final currentFile = extractLuaFile(previousDefault);
    if (currentFile != null) {
      if (currentFile.device is! StdoutDevice) {
        Logger.debugLazy(
          () => 'Closing previous default output before replacement',
          category: 'IO',
        );
        await currentFile.close();
        IOLib.unregisterOpenFileForLuaFile(currentFile);
      }
    }

    if (previousDefault != null && !identical(previousDefault, newFile)) {
      IOLib.unregisterOpenFile(previousDefault);
    }

    Logger.debugLazy(() => 'Setting new default output', category: 'IO');
    IOLib._defaultOutput = newFile;
    IOLib._defaultOutputExplicitlyClosed =
        false; // Reset the flag when setting new output
    Logger.debugLazy(
      () => 'Reset _defaultOutputExplicitlyClosed to false',
      category: 'IO',
    );
    Logger.debugLazy(() => 'IOOutput.call() completed', category: 'IO');
    return newFile;
  }
}

class IOPopen extends BuiltinFunction {
  IOPopen([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO popen', category: 'IO');
    if (args.isEmpty) {
      throw LuaError.typeError("io.popen requires a command string");
    }

    final cmd = _ioString(args[0]);
    var mode = args.length > 1 ? _ioString(args[1]) : 'r';

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
      return wrapLuaFileValue(file, interpreter: interpreter);
    } catch (e) {
      Logger.debugLazy(
        () => 'Error starting popen process: $e',
        category: 'IO',
      );
      return LuaResults([null, e.toString()]);
    }
  }
}

class IORead extends BuiltinFunction {
  IORead([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO read', category: 'IO');

    final formats = args.isEmpty ? ["l"] : _ioStringList(args);
    Logger.debugLazy(() => 'Reading with formats: $formats', category: 'IO');
    final results = <Object?>[];
    bool encounteredFailure = false;

    for (final format in formats) {
      if (encounteredFailure) {
        // If any previous read failed, all subsequent reads return nil
        results.add(null);
        continue;
      }

      Logger.debugLazy(() => 'Reading format: $format', category: 'IO');

      try {
        final defaultInput = IOLib.defaultInput;
        final luaFile = extractLuaFile(defaultInput)!;
        final result = await luaFile.read(format);
        if (format == '1') {
          final v = result.isNotEmpty ? result[0] : null;
          if (v is LuaString) {
            Logger.debugLazy(
              () =>
                  'IORead(1): byte=${v.bytes.isNotEmpty ? v.bytes[0] : 'nil'}',
              category: 'IO',
            );
          } else {
            Logger.debugLazy(
              () => 'IORead(1): non-LuaString value=$v',
              category: 'IO',
            );
          }
        }

        // Check if this is an error or EOF condition
        if (result[0] == null && result.length > 1 && result[1] != null) {
          // This is an error
          Logger.debugLazy(
            () => 'Error reading format: ${result[1]}',
            category: 'IO',
          );
          return LuaResults(result);
        }

        if (result[0] == null) {
          // This read failed (EOF or parse error), mark failure for subsequent reads
          encounteredFailure = true;
        }

        // Even if null (EOF), add it to results
        results.add(result[0]);
      } catch (e) {
        // Catch device-level errors and convert to expected error message
        Logger.debugLazy(
          () => 'IORead caught exception: ${e.toString()}',
          category: 'IO',
        );
        if (e.toString().contains("attempt to use a closed file")) {
          Logger.debugLazy(
            () => 'Converting closed file error to input file closed',
            category: 'IO',
          );
          throw LuaError(" input file is closed");
        }
        // Re-throw other errors as-is
        Logger.debugLazy(() => 'Re-throwing exception as-is', category: 'IO');
        rethrow;
      }
    }

    return LuaResults(results);
  }
}

class IOTmpfile extends BuiltinFunction {
  IOTmpfile([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO tmpfile', category: 'IO');
    try {
      final device = await IOLib.fileSystemProvider.createTempFile('lua_temp');
      return createLuaFile(device, interpreter: interpreter);
    } catch (e) {
      Logger.debugLazy(
        () => 'Error creating temporary file: $e',
        category: 'IO',
      );
      return LuaResults([null, e.toString()]);
    }
  }
}

class IOType extends BuiltinFunction {
  IOType([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO type', category: 'IO');
    if (args.isEmpty) return primitiveValue(null);

    final obj = args[0];
    if (!isLuaFile(obj)) return primitiveValue(null);

    final file = extractLuaFile(obj)!;
    final type = file.isClosed ? "closed file" : "file";
    Logger.debugLazy(() => 'File type: $type', category: 'IO');
    return dartStringValue(type);
  }
}

class IOWrite extends BuiltinFunction {
  IOWrite([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'Executing IO write', category: 'IO');

    // Check if default output was explicitly closed
    Logger.debugLazy(
      () =>
          'Checking _defaultOutputExplicitlyClosed: ${IOLib._defaultOutputExplicitlyClosed}',
      category: 'IO',
    );
    if (IOLib._defaultOutputExplicitlyClosed) {
      Logger.debugLazy(
        () => 'Default output was explicitly closed, throwing error',
        category: 'IO',
      );
      throw LuaError(" output file is closed");
    }

    if (args.isEmpty) {
      Logger.debugLazy(() => 'No arguments to write', category: 'IO');
      return LuaResults([true]);
    }

    for (final arg in args) {
      final val = arg as Value;
      final rawVal = rawLuaSlot(val);
      try {
        final defaultOutput = IOLib.defaultOutput;
        final luaFile = extractLuaFile(defaultOutput)!;
        if (rawVal is LuaString) {
          final bytes = rawVal.bytes;
          Logger.debugLazy(
            () => 'Writing ${bytes.length} raw bytes',
            category: 'IO',
          );
          final result = await luaFile.writeBytes(bytes);
          if (result[0] == null) {
            Logger.debugLazy(
              () => 'Error writing raw bytes: ${result[1]}',
              category: 'IO',
            );
            return LuaResults(result);
          }
        } else if (rawVal is String || rawVal is num || rawVal is BigInt) {
          final str = rawVal.toString();
          Logger.debugLazy(() => 'Writing string: $str', category: 'IO');
          final result = await luaFile.write(str);
          if (result[0] == null) {
            Logger.debugLazy(
              () => 'Error writing: ${result[1]}',
              category: 'IO',
            );
            return LuaResults(result);
          }
        } else {
          throw LuaError.typeError(
            "bad argument #1 to 'io.write' (string expected, got ${getLuaType(val)})",
          );
        }
      } catch (e) {
        // Catch device-level errors and convert to expected error message
        Logger.debugLazy(
          () => 'IOWrite caught exception: ${e.toString()}',
          category: 'IO',
        );
        if (e.toString().contains("attempt to use a closed file")) {
          Logger.debugLazy(
            () => 'Converting closed file error to output file closed',
            category: 'IO',
          );
          throw LuaError(" output file is closed");
        }
        // Re-throw other errors as-is
        Logger.debugLazy(() => 'Re-throwing exception as-is', category: 'IO');
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
  FileClose([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: close', category: 'IO');

    if (args.isEmpty) {
      throw LuaError("got no value");
    }

    final file = args[0];
    if (!isLuaFile(file)) {
      Logger.debugLazy(
        () =>
            'Attempt to close non-file object file type: ${file.runtimeType} and value: $file',
        category: 'IO',
      );
      throw LuaError.typeError("file expected");
    }

    final luaFile = extractLuaFile(file)!;

    // Check if this is a standard file (stdin, stdout, stderr)
    if (luaFile.isStandardFile) {
      Logger.debugLazy(() => 'Cannot close standard file', category: 'IO');
      return primitiveValue(false); // Standard files cannot be closed
    }

    final result = await luaFile.close();

    // If this file was the current default output, reset it to stdout
    if (_isLuaFileWrapperFor(IOLib._defaultOutput, luaFile)) {
      Logger.debugLazy(
        () => 'Resetting default output to stdout after file close',
        category: 'IO',
      );
      IOLib._defaultOutput = null;
      IOLib._defaultOutputExplicitlyClosed = false; // Reset the flag
    }

    // Similarly for default input
    if (_isLuaFileWrapperFor(IOLib._defaultInput, luaFile)) {
      Logger.debugLazy(
        () => 'Resetting default input to stdin after file close',
        category: 'IO',
      );
      IOLib._defaultInput = null;
    }

    return LuaResults(result);
  }
}

class FileFlush extends BuiltinFunction {
  FileFlush([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: flush', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }
    final result = await extractLuaFile(file)!.flush();
    return LuaResults(result);
  }
}

class FileRead extends BuiltinFunction {
  FileRead([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: read', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final formats = actualArgs.isNotEmpty ? _ioStringList(actualArgs) : ["l"];

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
        return LuaResults(result);
      }

      if (result[0] == null) {
        // This read failed (EOF or parse error), mark failure for subsequent reads
        encounteredFailure = true;
      }

      results.add(result[0]);
    }

    return LuaResults(results);
  }
}

class FileWrite extends BuiltinFunction {
  FileWrite([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: write', category: 'IO');
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
      final rawVal = rawLuaSlot(val);
      List<Object?> result;
      if (rawVal is LuaString) {
        final bytes = rawVal.bytes;
        Logger.debugLazy(
          () => 'File:write raw ${bytes.length} bytes',
          category: 'IO',
        );
        result = await luaFile.writeBytes(bytes);
      } else {
        final str = rawVal.toString();
        result = await luaFile.write(str);
      }
      if (result[0] == null) {
        // On failure, propagate the (nil, errmsg[, errno]) tuple.
        return LuaResults(result);
      }
    }
    // Success: return the file handle (self) for chaining.
    return file;
  }
}

class FileSeek extends BuiltinFunction {
  FileSeek([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: seek', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final whence = actualArgs.isNotEmpty ? _ioString(actualArgs[0]) : "cur";
    final offset = actualArgs.length > 1 ? rawLuaSlot(actualArgs[1]) as int : 0;

    final result = await extractLuaFile(file)!.seek(whence, offset);
    return LuaResults(result);
  }
}

class FileLines extends BuiltinFunction {
  FileLines([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: lines', category: 'IO');
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip the self parameter
    final actualArgs = args.skip(1).toList();
    final formats = actualArgs.isNotEmpty ? _ioStringList(actualArgs) : ["l"];

    final result = await extractLuaFile(
      file,
    )!.lines(formats, false, file as Value);
    return result;
  }
}

class FileSetvbuf extends BuiltinFunction {
  FileSetvbuf([super.interpreter]);

  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debugLazy(() => 'File method: setvbuf', category: 'IO');
    if (args.isEmpty) {
      throw LuaError("got no value");
    }
    final file = args[0];
    if (!isLuaFile(file)) {
      throw LuaError.typeError("file expected");
    }

    // Skip self parameter
    final actualArgs = args.skip(1).toList();
    final mode = actualArgs.isNotEmpty ? _ioString(actualArgs[0]) : 'full';
    final size = actualArgs.length > 1
        ? NumberUtils.toInt(rawLuaSlot(actualArgs[1]))
        : null;

    final result = await extractLuaFile(file)!.setvbuf(mode, size);
    return LuaResults(result);
  }
}

// void defineIOLibrary - removed as part of migration to Library system
