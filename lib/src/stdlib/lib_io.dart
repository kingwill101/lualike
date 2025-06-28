import 'dart:io';
import 'dart:math';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/bytecode/vm.dart' show BytecodeVM;
import 'package:path/path.dart' as path;

import '../io/io_device.dart';
import '../io/lua_file.dart';
import '../value_class.dart';

class IOLib {
  // Singleton instances for standard devices
  static StdinDevice? _stdinDevice;
  static StdoutDevice? _stdoutDevice;
  static StdoutDevice? _stderrDevice;

  static LuaFile? _defaultInput;
  static LuaFile? _defaultOutput;

  // Get singleton instances
  static StdinDevice get stdinDevice => _stdinDevice ??= StdinDevice();
  static StdoutDevice get stdoutDevice =>
      _stdoutDevice ??= StdoutDevice(stdout, allowFlush: false);
  static StdoutDevice get stderrDevice =>
      _stderrDevice ??= StdoutDevice(stderr);

  static LuaFile get defaultInput {
    Logger.debug('Getting default input');
    _defaultInput ??= LuaFile(stdinDevice);
    return _defaultInput!;
  }

  static LuaFile get defaultOutput {
    Logger.debug('Getting default output');
    _defaultOutput ??= LuaFile(stdoutDevice);
    return _defaultOutput!;
  }

  static final ValueClass fileClass = ValueClass.create({
    "__gc": (List<Object?> args) async {
      Logger.debug('Garbage collecting file');
      final file = args[0] as Value;
      await (file.raw as LuaFile).close();
      return Value(null);
    },
    "__close": (List<Object?> args) async {
      Logger.debug('Closing file');
      final file = args[0] as Value;
      final result = await (file.raw as LuaFile).close();
      return Value.multi(result);
    },
    "__tostring": (List<Object?> args) {
      Logger.debug('Converting file to string');
      final file = args[0] as Value;
      return Value((file.raw as LuaFile).toString());
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
}

class IOClose implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO close');
    if (args.isEmpty) {
      Logger.debug('Closing default output');
      final result = await IOLib.defaultOutput.close();
      IOLib._defaultOutput = null;
      return Value.multi(result);
    }

    final file = args[0] as Value;
    if (file.raw is! LuaFile) {
      Logger.debug('Attempt to close non-file object');
      return Value.multi([null, "attempt to close a non-file object"]);
    }

    Logger.debug('Closing file');
    final result = await (file.raw as LuaFile).close();
    return Value.multi(result);
  }
}

class IOFlush implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO flush');
    final result = await IOLib.defaultOutput.flush();
    return Value.multi(result);
  }
}

class IOInput implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO input');
    if (args.isEmpty) {
      Logger.debug('Returning default input');
      return Value(IOLib.defaultInput, metatable: IOLib.fileClass.metamethods);
    }

    if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Setting default input to provided file');
      IOLib._defaultInput = (args[0] as Value).raw as LuaFile;
      return args[0];
    }

    final filename = (args[0] as Value).raw.toString();
    Logger.debug('Opening file for input: $filename');
    try {
      final device = await FileIODevice.open(filename, "r");
      final file = LuaFile(device);
      IOLib._defaultInput = file;
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error opening file: $e');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOLines implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO lines');
    LuaFile file;
    List<String> formats;

    if (args.isEmpty) {
      Logger.debug('Using default input for lines');
      file = IOLib.defaultInput;
      formats = ["l"];
    } else if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Using provided file for lines');
      file = (args[0] as Value).raw as LuaFile;
      formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
    } else {
      Logger.debug('Opening new file for lines');
      final filename = (args[0] as Value).raw.toString();
      try {
        final device = await FileIODevice.open(filename, "r");
        file = LuaFile(device);
        formats = args.skip(1).map((e) => (e as Value).raw.toString()).toList();
      } catch (e) {
        Logger.debug('Error opening file: $e');
        return Value.multi([null, e.toString()]);
      }
    }

    if (formats.isEmpty) formats = ["l"];
    Logger.debug('Reading lines with formats: $formats');
    return await file.lines(formats);
  }
}

class IOOpen implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO open');
    if (args.isEmpty) {
      Logger.debug('Missing filename');
      return Value.multi([null, "missing filename"]);
    }

    final filename = (args[0] as Value).raw.toString();
    final mode = args.length > 1 ? (args[1] as Value).raw.toString() : "r";
    Logger.debug('Opening file: $filename with mode: $mode');

    try {
      final device = await FileIODevice.open(filename, mode);
      final file = LuaFile(device);
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error opening file: $e');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOOutput implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO output');
    if (args.isEmpty) {
      Logger.debug('Returning default output');
      return Value(IOLib.defaultOutput, metatable: IOLib.fileClass.metamethods);
    }

    if (args[0] is Value && (args[0] as Value).raw is LuaFile) {
      Logger.debug('Setting default output to provided file');
      IOLib._defaultOutput = (args[0] as Value).raw as LuaFile;
      return args[0];
    }

    final filename = (args[0] as Value).raw.toString();
    Logger.debug('Opening file for output: $filename');
    try {
      final device = await FileIODevice.open(filename, "w");
      final file = LuaFile(device);
      IOLib._defaultOutput = file;
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error opening file: $e');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOPopen implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO popen (not supported)');
    return Value.multi([null, "popen not supported"]);
  }
}

class IORead implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO read');
    final formats =
    args.isEmpty
        ? ["l"]
        : args.map((e) => (e as Value).raw.toString()).toList();
    Logger.debug('Reading with formats: $formats');
    final results = <Object?>[];

    for (final format in formats) {
      Logger.debug('Reading format: $format');
      final result = await IOLib.defaultInput.read(format);

      // Check if this is an error or EOF condition
      if (result[0] == null && result.length > 1 && result[1] != null) {
        // This is an error
        Logger.debug('Error reading format: ${result[1]}');
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
    Logger.debug('Executing IO tmpfile');
    try {
      final tempDir = Directory.systemTemp;
      final random = Random();
      final tempFile = File(
        path.join(tempDir.path, 'lua_temp_${random.nextInt(1000000)}.tmp'),
      );
      Logger.debug('Creating temporary file: ${tempFile.path}');

      final device = await FileIODevice.open(tempFile.path, "w+");
      final file = LuaFile(device);
      return Value(file, metatable: IOLib.fileClass.metamethods);
    } catch (e) {
      Logger.debug('Error creating temporary file: $e');
      return Value.multi([null, e.toString()]);
    }
  }
}

class IOType implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO type');
    if (args.isEmpty) return Value(null);

    final obj = args[0] as Value;
    if (obj.raw is! LuaFile) return Value(null);

    final file = obj.raw as LuaFile;
    final type = file.isClosed ? "closed file" : "file";
    Logger.debug('File type: $type');
    return Value(type);
  }
}

class IOWrite implements BuiltinFunction {
  @override
  Future<Object?> call(List<Object?> args) async {
    Logger.debug('Executing IO write');
    if (args.isEmpty) {
      Logger.debug('No arguments to write');
      return Value.multi([true]);
    }

    for (final arg in args) {
      final str = (arg as Value).raw.toString();
      Logger.debug('Writing string: $str');
      final result = await IOLib.defaultOutput.write(str);
      if (result[0] == null) {
        Logger.debug('Error writing: ${result[1]}');
        return Value.multi(result);
      }
    }

    return Value.multi([true]);
  }
}

void defineIOLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  Logger.debug('Defining IO library');
  final ioTable = <String, dynamic>{};
  IOLib.functions.forEach((key, value) {
    Logger.debug('Adding IO function: $key');
    ioTable[key] = value;
  });

  Logger.debug('Adding standard streams');
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
  Logger.debug('IO library defined');
}
