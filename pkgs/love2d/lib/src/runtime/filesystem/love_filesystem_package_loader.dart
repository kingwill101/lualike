/// Synchronizes Lua `package` searchers with the LOVE filesystem runtime.
library;

import 'package:lualike/lualike.dart'
    show LuaError, LuaRuntime, LuaString, Value, isLinux, isMacOS, isWindows;

import 'love_filesystem_runtime.dart';

/// Cached Lua source searchers installed for each runtime.
final Expando<Value> _loveFilesystemLuaSearcherCache = Expando<Value>(
  'love2dFilesystemLuaSearcher',
);

/// Cached native-module searchers installed for each runtime.
final Expando<Value> _loveFilesystemExtSearcherCache = Expando<Value>(
  'love2dFilesystemExtSearcher',
);

/// Updates `package.path`, `package.cpath`, and filesystem-backed searchers for
/// [runtime].
void syncLoveFilesystemPackageInterop(LuaRuntime runtime) {
  final packageValue = runtime.globals.get('package');
  if (packageValue is! Value || packageValue.raw is! Map) {
    return;
  }

  final state = LoveFilesystemState.attach(runtime);
  final packageTable = packageValue.raw as Map<dynamic, dynamic>;
  packageTable['path'] = Value(state.getRequirePathString());
  packageTable['cpath'] = Value(state.getCRequirePathString());

  final luaSearcher = _loveFilesystemLuaSearcherCache[runtime] ??=
      _createLoveFilesystemSearcher(runtime);
  final extSearcher = _loveFilesystemExtSearcherCache[runtime] ??=
      _createLoveFilesystemExtSearcher(runtime);

  final searchersEntry = packageTable['searchers'];
  if (searchersEntry case final Value wrapped when wrapped.raw is List) {
    final searchers = wrapped.raw as List<dynamic>;
    _syncSearcher(searchers, luaSearcher, targetIndex: 1);
    _syncSearcher(searchers, extSearcher, targetIndex: 2);
    packageTable['loaders'] = wrapped;
    return;
  }

  final searchersValue = Value(<Value>[luaSearcher, extSearcher]);
  packageTable['searchers'] = searchersValue;
  packageTable['loaders'] = searchersValue;
}

/// Creates the Lua-source package searcher for [runtime].
Value _createLoveFilesystemSearcher(LuaRuntime runtime) {
  return Value((List<Object?> args) async {
    final moduleName = _stringLike(_valueAt(args, 0));
    if (moduleName == null) {
      return Value('missing module name');
    }

    final state = LoveFilesystemState.of(runtime);
    final modulePath = moduleName.replaceAll('.', '/');

    for (final template in state.requirePath) {
      final logicalPath = template.replaceAll('?', modulePath);

      final info = await state.getInfo(logicalPath);
      if (info == null || info.type == LoveFilesystemNodeType.directory) {
        continue;
      }

      return <Object?>[
        Value((List<Object?> loaderArgs) async {
          try {
            final chunk = await state.loadChunk(runtime, logicalPath);
            if (chunk == null) {
              throw LuaError('unknown error');
            }

            return runtime.callFunction(
              chunk,
              loaderArgs,
              debugName: logicalPath,
              debugNameWhat: 'module',
            );
          } on StateError catch (error) {
            throw LuaError(
              "error loading module '$moduleName' from file '$logicalPath': "
              "${error.message}",
            );
          } on LuaError catch (error) {
            throw LuaError(
              "error loading module '$moduleName' from file '$logicalPath': "
              "${error.message}",
            );
          }
        }),
        Value(logicalPath),
      ];
    }

    return Value("\n\tno '$modulePath' in LOVE game directories.");
  });
}

/// Creates the native-extension package searcher for [runtime].
Value _createLoveFilesystemExtSearcher(LuaRuntime runtime) {
  return Value((List<Object?> args) async {
    final moduleName = _stringLike(_valueAt(args, 0));
    if (moduleName == null) {
      return Value('missing module name');
    }

    final state = LoveFilesystemState.of(runtime);
    final tokenizedName = moduleName.replaceAll('.', '/');

    for (final template in state.cRequirePath) {
      for (final logicalPath in _expandCLibraryCandidates(
        template,
        tokenizedName,
      )) {
        final info = await state.getInfo(logicalPath);
        if (info == null || info.type == LoveFilesystemNodeType.directory) {
          continue;
        }

        return <Object?>[
          Value((List<Object?> loaderArgs) async {
            throw LuaError("\n\tC library '$tokenizedName' is incompatible.");
          }),
          Value(logicalPath),
        ];
      }
    }

    return Value("\n\tno file '$tokenizedName' in LOVE paths.");
  });
}

/// Returns the argument at [index], if it was provided.
Object? _valueAt(List<Object?> args, int index) {
  return index < args.length ? args[index] : null;
}

/// Expands [template] into candidate native-library paths for [modulePath].
Iterable<String> _expandCLibraryCandidates(
  String template,
  String modulePath,
) sync* {
  if (template.contains('??')) {
    for (final extension in _nativeLibraryExtensions()) {
      yield template
          .replaceAll('??', '$modulePath$extension')
          .replaceAll('?', modulePath);
    }
    return;
  }

  yield template.replaceAll('?', modulePath);
}

/// The host-native library extensions searched for C modules.
List<String> _nativeLibraryExtensions() {
  if (isWindows) {
    return const <String>['.dll'];
  }
  if (isMacOS) {
    return const <String>['.dylib', '.so'];
  }
  if (isLinux) {
    return const <String>['.so'];
  }
  return const <String>['.so'];
}

/// Inserts or repositions [searcher] in [searchers] at [targetIndex].
void _syncSearcher(
  List<dynamic> searchers,
  Value searcher, {
  required int targetIndex,
}) {
  final existingIndex = searchers.indexWhere(
    (entry) =>
        identical(entry, searcher) ||
        (entry is Value && identical(entry.raw, searcher.raw)),
  );
  final clampedIndex = targetIndex.clamp(0, searchers.length);
  if (existingIndex < 0) {
    searchers.insert(clampedIndex, searcher);
    return;
  }
  if (existingIndex == clampedIndex) {
    return;
  }

  final existing = searchers.removeAt(existingIndex);
  final adjustedIndex = targetIndex.clamp(0, searchers.length);
  searchers.insert(adjustedIndex, existing);
}

/// Converts Lua values commonly used for path arguments to strings.
String? _stringLike(Object? value) {
  final raw = value is Value ? value.raw : value;
  return switch (raw) {
    final String stringValue => stringValue,
    final LuaString stringValue => stringValue.toString(),
    final num numberValue => numberValue.toString(),
    _ => null,
  };
}
