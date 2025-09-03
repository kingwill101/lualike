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
  static LuaFile? _defaultOutput;

  // Get singleton instances
  static StdinDevice get stdinDevice => _stdinDevice ??= StdinDevice();

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
    Logger.debug('Getting default input');
    _defaultInput ??= LuaFile(stdinDevice);
    return _defaultInput!;
  }

  static set defaultInput(LuaFile? file) {
    _defaultInput = file;
  }

  static LuaFile get defaultOutput {
    Logger.debug('Getting default output');
    _defaultOutput ??= LuaFile(stdoutDevice);
    return _defaultOutput!;
  }

  static set defaultOutput(LuaFile? file) {
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
  };

  static final ValueClass fileClass = ValueClass.create({
    "__gc": (List<Object?> args) async {
      Logger.debug('Garbage collecting file', category: 'IO');
      final file = args[0];
      if (file is! Value) {
        throw LuaError.typeError("file expected");
      }
      await (file.raw as LuaFile).close();
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

          // Return a function that will be called later
          return Value((callArgs) {
            Logger.debug(
              'File method ${key.raw} called with ${callArgs.length} arguments',
              category: 'IO',
            );

            // Include the file object as the first argument if not already present
            if (callArgs.isNotEmpty && callArgs.first == file) {
              return method.call(callArgs);
            }

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

    if (_defaultOutput?.device is! StdoutDevice) {
      await _defaultOutput?.close();
    }
    _defaultOutput = null;
  }
}

class IOClose implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO close', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Closing default output', category: 'IO');
      final result = await IOLib.defaultOutput.close();
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
    final result = await luaFile.close();
    if (luaFile == IOLib._defaultOutput) {
      // When closing the current output file, revert to stdout
      IOLib._defaultOutput = null;
    }
    return Value.multi(result);
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

    if (IOLib._defaultInput?.device is! StdinDevice) {
      await IOLib._defaultInput?.close();
    }
    IOLib._defaultInput = newFile;
    return result;
  }
}

class IOLines implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO lines', category: 'IO');
    LuaFile file;
    List<String> formats;

    if (args.isEmpty) {
      Logger.debug('Using default input for lines', category: 'IO');
      file = IOLib.defaultInput;
      formats = ["l"];
    } else if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Using provided file for lines', category: 'IO');
      file = (args[0] as Value).raw as LuaFile;
      formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
    } else {
      Logger.debug('Opening new file for lines', category: 'IO');
      final filename = (args[0] as Value).raw.toString();
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "r");
        file = LuaFile(device);
        formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
      } catch (e) {
        Logger.debug('Error opening file: $e', category: 'IO');
        return Value.multi([null, e.toString()]);
      }
    }

    if (formats.isEmpty) formats = ["l"];
    Logger.debug('Reading lines with formats: $formats', category: 'IO');
    return await file.lines(formats);
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
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOOutput implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO output', category: 'IO');
    if (args.isEmpty) {
      Logger.debug('Returning default output', category: 'IO');
      return Value(IOLib.defaultOutput, metatable: IOLib.fileClass.metamethods);
    }

    LuaFile? newFile;
    Value? result;

    if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Setting default output to provided file', category: 'IO');
      newFile = (args[0] as Value).raw as LuaFile;
      result = args[0] as Value;
    } else {
      final filename = (args[0] as Value).raw.toString();
      Logger.debug('Opening file for output: $filename', category: 'IO');
      try {
        final device = await IOLib.fileSystemProvider.openFile(filename, "w");
        newFile = LuaFile(device);
        result = Value(newFile, metatable: IOLib.fileClass.metamethods);
      } catch (e, s) {
        throw LuaError(
          "cannot open file '$filename' (No such file or directory)",
          stackTrace: s,
        );
      }
    }

    if (IOLib._defaultOutput?.device is! StdoutDevice) {
      await IOLib._defaultOutput?.close();
    }
    IOLib._defaultOutput = newFile;
    return result;
  }
}

class IOPopen implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO popen (not supported)', category: 'IO');
    return Value.multi([null, "popen not supported"]);
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

    for (final format in formats) {
      Logger.debug('Reading format: $format', category: 'IO');
      final result = await IOLib.defaultInput.read(format);

      // Check if this is an error or EOF condition
      if (result[0] == null && result.length > 1 && result[1] != null) {
        // This is an error
        Logger.debug('Error reading format: ${result[1]}', category: 'IO');
        return Value.multi(result);
      }

      // Even if null (EOF), add it to results
      results.add(result[0]);
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
    if (args.isEmpty) {
      Logger.debug('No arguments to write', category: 'IO');
      return Value.multi([true]);
    }

    for (final arg in args) {
      final str = (arg as Value).raw.toString();
      Logger.debug('Writing string: $str', category: 'IO');
      final result = await IOLib.defaultOutput.write(str);
      if (result[0] == null) {
        Logger.debug('Error writing: ${result[1]}', category: 'IO');
        return Value.multi(result);
      }
    }

    return Value.multi([true]);
  }
}

// File method implementations that work on LuaFile objects
class FileClose implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('File method: close', category: 'IO');
    final file = args[0];
    if (file is! Value || file.raw is! LuaFile) {
      throw LuaError.typeError("file expected");
    }
    final result = await (file.raw as LuaFile).close();
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

    for (final format in formats) {
      final result = await luaFile.read(format);
      if (result[0] == null && result.length > 1 && result[1] != null) {
        return Value.multi(result);
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
    if (actualArgs.isEmpty) {
      return Value.multi([true]);
    }

    final luaFile = file.raw as LuaFile;
    for (final arg in actualArgs) {
      final str = (arg as Value).raw.toString();
      final result = await luaFile.write(str);
      if (result[0] == null) {
        return Value.multi(result);
      }
    }

    return Value.multi([true]);
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
