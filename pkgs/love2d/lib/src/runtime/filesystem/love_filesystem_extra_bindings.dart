library;

import 'package:lualike/lualike.dart' show LuaError, LuaRuntime, Value;

import '../love_binding_helpers.dart';
import '../love_module_table_helpers.dart';
import 'love_filesystem_runtime.dart';

/// The largest integer that can be represented exactly in a Lua number.
const int _loveFilesystemLuaNumberLimit = 0x20000000000000;

/// Tracks which runtimes already have filesystem extra bindings installed.
final Expando<bool> _loveFilesystemExtrasInstalled = Expando<bool>(
  'love2dFilesystemExtrasInstalled',
);

/// Installs compatibility helpers and extra queries into `love.filesystem`.
void installLoveFilesystemExtraBindings(LuaRuntime runtime) {
  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveFilesystemExtrasInstalled,
    moduleName: 'filesystem',
    install: _installLoveFilesystemExtraBindings,
  );
}

void _installLoveFilesystemExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> filesystemTable,
) {
  final state = LoveFilesystemState.attach(runtime);
  final builder = loveBindingBuilder(runtime);

  filesystemTable['setFused'] = Value(
    builder.create((args) {
      state.setFused(_toBoolean(args, 0));
      return null;
    }),
    functionName: 'setFused',
  );

  filesystemTable['_setAndroidSaveExternal'] = Value(
    builder.create((args) {
      state.setAndroidSaveExternal(_optionalBool(args, 0, defaultValue: false));
      return null;
    }),
    functionName: '_setAndroidSaveExternal',
  );

  filesystemTable['getExecutablePath'] = Value(
    builder.create((args) => state.getExecutablePath()),
    functionName: 'getExecutablePath',
  );

  filesystemTable['exists'] = Value(
    builder.create((args) async {
      final info = await _filesystemInfoArgument(state, args, 'exists');
      return info != null;
    }),
    functionName: 'exists',
  );

  filesystemTable['isDirectory'] = Value(
    builder.create((args) async {
      final info = await _filesystemInfoArgument(state, args, 'isDirectory');
      return info?.type == LoveFilesystemNodeType.directory;
    }),
    functionName: 'isDirectory',
  );

  filesystemTable['isFile'] = Value(
    builder.create((args) async {
      final info = await _filesystemInfoArgument(state, args, 'isFile');
      return info?.type == LoveFilesystemNodeType.file;
    }),
    functionName: 'isFile',
  );

  filesystemTable['isSymlink'] = Value(
    builder.create((args) async {
      final info = await _filesystemInfoArgument(state, args, 'isSymlink');
      return info?.type == LoveFilesystemNodeType.symlink;
    }),
    functionName: 'isSymlink',
  );

  filesystemTable['getLastModified'] = Value(
    builder.create((args) async {
      final info = await _filesystemInfoArgument(
        state,
        args,
        'getLastModified',
      );
      if (info == null) {
        return _ioError('File does not exist');
      }
      if (!_hasKnownFilesystemNumber(info.modtime)) {
        return _ioError('Could not determine file modification date.');
      }
      return info.modtime;
    }),
    functionName: 'getLastModified',
  );

  filesystemTable['getSize'] = Value(
    builder.create((args) async {
      final info = await _filesystemInfoArgument(state, args, 'getSize');
      if (info == null) {
        return _ioError('File does not exist');
      }
      if (!_hasKnownFilesystemNumber(info.size)) {
        return _ioError('Could not determine file size.');
      }
      if (info.size! >= _loveFilesystemLuaNumberLimit) {
        return _ioError('Size too large to fit into a Lua number!');
      }
      return info.size;
    }),
    functionName: 'getSize',
  );
}

Future<LoveFilesystemInfo?> _filesystemInfoArgument(
  LoveFilesystemState state,
  List<Object?> args,
  String operation,
) {
  final symbol = 'love.filesystem.$operation';
  return state.getInfo(_requireString(args, 0, symbol));
}

/// Requires a string-like argument at [index] for [symbol].
String _requireString(List<Object?> args, int index, String symbol) {
  final value = loveStringLike(index < args.length ? args[index] : null);
  if (value != null) {
    return value;
  }

  throw LuaError('$symbol expected a string at argument ${index + 1}');
}

/// Converts [value] to a filesystem string when LOVE would accept it.

/// Returns an optional boolean argument or [defaultValue] when absent.
bool _optionalBool(
  List<Object?> args,
  int index, {
  required bool defaultValue,
}) {
  final raw = index < args.length ? args[index] : null;
  final unwrapped = loveRawValue(raw);
  if (unwrapped == null) {
    return defaultValue;
  }
  if (unwrapped is bool) {
    return unwrapped;
  }
  return defaultValue;
}

/// Converts a Lua argument to LOVE's boolean truthiness rules.
bool _toBoolean(List<Object?> args, int index) {
  final raw = index < args.length ? args[index] : null;
  final unwrapped = loveRawValue(raw);
  if (unwrapped == null) {
    return false;
  }
  if (unwrapped is bool) {
    return unwrapped;
  }
  return true;
}

/// Returns a LOVE-style `(nil, message)` IO error tuple.
Value _ioError(String message) {
  return Value.multi(<Object?>[null, message]);
}

/// Whether [value] is a non-negative filesystem number.
bool _hasKnownFilesystemNumber(int? value) => value != null && value >= 0;
