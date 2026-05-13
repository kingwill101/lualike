library;

import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart'
    show LuaError, LuaRuntime, LuaString, Value;

import 'love_filesystem_runtime.dart';

/// The largest integer that can be represented exactly in a Lua number.
const int _loveFilesystemLuaNumberLimit = 0x20000000000000;

/// Tracks which runtimes already have filesystem extra bindings installed.
final Expando<bool> _loveFilesystemExtrasInstalled = Expando<bool>(
  'love2dFilesystemExtrasInstalled',
);

/// Installs compatibility helpers and extra queries into `love.filesystem`.
void installLoveFilesystemExtraBindings(LuaRuntime runtime) {
  if (_loveFilesystemExtrasInstalled[runtime] == true) {
    return;
  }

  final filesystemTable = _filesystemTable(runtime);
  if (filesystemTable == null) {
    return;
  }

  final state = LoveFilesystemState.attach(runtime);
  final builder = BuiltinFunctionBuilder(
    LibraryContext(environment: runtime.getCurrentEnv(), interpreter: runtime),
  );

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
      final info = await state.getInfo(
        _requireString(args, 0, 'love.filesystem.exists'),
      );
      return info != null;
    }),
    functionName: 'exists',
  );

  filesystemTable['isDirectory'] = Value(
    builder.create((args) async {
      final info = await state.getInfo(
        _requireString(args, 0, 'love.filesystem.isDirectory'),
      );
      return info?.type == LoveFilesystemNodeType.directory;
    }),
    functionName: 'isDirectory',
  );

  filesystemTable['isFile'] = Value(
    builder.create((args) async {
      final info = await state.getInfo(
        _requireString(args, 0, 'love.filesystem.isFile'),
      );
      return info?.type == LoveFilesystemNodeType.file;
    }),
    functionName: 'isFile',
  );

  filesystemTable['isSymlink'] = Value(
    builder.create((args) async {
      final info = await state.getInfo(
        _requireString(args, 0, 'love.filesystem.isSymlink'),
      );
      return info?.type == LoveFilesystemNodeType.symlink;
    }),
    functionName: 'isSymlink',
  );

  filesystemTable['getLastModified'] = Value(
    builder.create((args) async {
      final info = await state.getInfo(
        _requireString(args, 0, 'love.filesystem.getLastModified'),
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
      final info = await state.getInfo(
        _requireString(args, 0, 'love.filesystem.getSize'),
      );
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

  _loveFilesystemExtrasInstalled[runtime] = true;
}

/// The `love.filesystem` module table from the current runtime environment.
Map<dynamic, dynamic>? _filesystemTable(LuaRuntime runtime) {
  final love = runtime.getCurrentEnv().get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final filesystem = loveTable['filesystem'];
  final filesystemTable = filesystem is Value ? filesystem.raw : filesystem;
  if (filesystemTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return filesystemTable;
}

/// Requires a string-like argument at [index] for [symbol].
String _requireString(List<Object?> args, int index, String symbol) {
  final value = _stringLike(index < args.length ? args[index] : null);
  if (value != null) {
    return value;
  }

  throw LuaError('$symbol expected a string at argument ${index + 1}');
}

/// Converts [value] to a filesystem string when LOVE would accept it.
String? _stringLike(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString stringValue => stringValue.toString(),
    final num numberValue => numberValue.toString(),
    _ => null,
  };
}

/// Returns an optional boolean argument or [defaultValue] when absent.
bool _optionalBool(
  List<Object?> args,
  int index, {
  required bool defaultValue,
}) {
  final raw = index < args.length ? args[index] : null;
  final unwrapped = raw is Value ? raw.unwrap() : raw;
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
  final unwrapped = raw is Value ? raw.unwrap() : raw;
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
