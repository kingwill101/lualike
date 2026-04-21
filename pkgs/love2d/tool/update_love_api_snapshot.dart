import 'dart:convert';
import 'dart:io';

import 'package:lualike/lualike.dart';
import 'package:path/path.dart' as p;

const _expectedVersion = '11.5';
const _loveApiRepo = 'https://github.com/love2d-community/love-api.git';

Future<void> main() async {
  final packageRoot = p.normalize(
    p.dirname(p.dirname(Platform.script.toFilePath())),
  );
  final outputFile = File(
    p.join(packageRoot, 'lib', 'src', 'generated', 'love_api.love_api.json'),
  );
  final vendoredRepoDir = Directory(
    p.join(packageRoot, 'third_party', 'love-api'),
  );
  Directory? tempRoot;
  late final Directory repoDir;
  final usingVendoredRepo = _hasLoveApiInputs(vendoredRepoDir);

  try {
    if (usingVendoredRepo) {
      repoDir = vendoredRepoDir;
    } else {
      tempRoot = await Directory.systemTemp.createTemp('love_api_');
      repoDir = Directory(p.join(tempRoot.path, 'love-api'));

      final cloneResult = await Process.run('git', <String>[
        'clone',
        '--depth',
        '1',
        _loveApiRepo,
        repoDir.path,
      ]);
      if (cloneResult.exitCode != 0) {
        stderr
          ..writeln('Failed to clone love-api repository.')
          ..writeln(cloneResult.stderr);
        exit(cloneResult.exitCode);
      }
    }

    final sourceCommit = await _resolveSourceCommit(
      repoDir,
      usingVendoredRepo: usingVendoredRepo,
      fallbackSnapshot: outputFile,
    );

    final loveApiSource = await File(
      p.join(repoDir.path, 'love_api.lua'),
    ).readAsString();
    final extraSource = await File(
      p.join(repoDir.path, 'extra.lua'),
    ).readAsString();

    final lua = LuaLike();
    final loveApiTable = await _executeLuaChunk(
      lua,
      source: loveApiSource,
      scriptPath: p.join(repoDir.path, 'love_api.lua'),
      moduleArg: 'love_api',
    );
    final extraFunction = await _executeLuaChunk(
      lua,
      source: extraSource,
      scriptPath: p.join(repoDir.path, 'extra.lua'),
      moduleArg: 'extra',
    );
    final normalized = Value.wrap(
      await lua.vm.callFunction(extraFunction, <Object?>[loveApiTable]),
    );

    final snapshot = _buildSnapshot(
      normalized,
      expectedVersion: _expectedVersion,
      sourceCommit: sourceCommit,
    );

    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot),
    );
    stdout.writeln('Wrote ${outputFile.path}');
  } finally {
    if (tempRoot != null) {
      await tempRoot.delete(recursive: true);
    }
  }
}

bool _hasLoveApiInputs(Directory repoDir) {
  return File(p.join(repoDir.path, 'love_api.lua')).existsSync() &&
      File(p.join(repoDir.path, 'extra.lua')).existsSync();
}

Future<String> _resolveSourceCommit(
  Directory repoDir, {
  required bool usingVendoredRepo,
  required File fallbackSnapshot,
}) async {
  final commitResult = await Process.run('git', <String>[
    '-C',
    repoDir.path,
    'rev-parse',
    'HEAD',
  ]);
  if (commitResult.exitCode == 0) {
    return (commitResult.stdout as String).trim();
  }

  if (!usingVendoredRepo) {
    stderr
      ..writeln('Failed to resolve love-api commit.')
      ..writeln(commitResult.stderr);
    exit(commitResult.exitCode);
  }

  final fallbackCommit = await _readSnapshotSourceCommit(fallbackSnapshot);
  if (fallbackCommit != null && fallbackCommit.isNotEmpty) {
    return fallbackCommit;
  }

  return 'vendored';
}

Future<String?> _readSnapshotSourceCommit(File snapshotFile) async {
  if (!await snapshotFile.exists()) {
    return null;
  }

  try {
    final decoded = jsonDecode(await snapshotFile.readAsString());
    if (decoded is Map<String, Object?>) {
      final sourceCommit = decoded['sourceCommit'];
      if (sourceCommit is String) {
        return sourceCommit;
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}

Future<Value> _executeLuaChunk(
  LuaLike lua, {
  required String source,
  required String scriptPath,
  required String moduleArg,
}) async {
  final wrappedSource =
      '''
local __lualike_chunk = function(...)
$source
end

return __lualike_chunk(${jsonEncode(moduleArg)})
''';

  return Value.wrap(await lua.execute(wrappedSource, scriptPath: scriptPath));
}

Map<String, Object?> _buildSnapshot(
  Value api, {
  required String expectedVersion,
  required String sourceCommit,
}) {
  final version = _scalarString(_field(api, 'version'));
  if (version != expectedVersion) {
    throw StateError(
      'Expected LOVE API version $expectedVersion but fetched $version',
    );
  }

  final modules = _luaSequence(
    _field(api, 'modules'),
  ).map(_moduleSnapshot).toList(growable: false);

  final symbols = <Map<String, Object?>>[];
  final typeSnapshots = <Map<String, Object?>>[];
  final enumSnapshots = <Map<String, Object?>>[];

  for (final module in _luaSequence(_field(api, 'modules'))) {
    final moduleSymbol = _scalarString(_field(module, 'fullname'));

    for (final function in _luaSequence(_field(module, 'functions'))) {
      symbols.add(_symbolSnapshot(function, module: moduleSymbol));
    }

    for (final type in _luaSequence(_field(module, 'types'))) {
      final methodSymbols = <String>[];
      for (final method in _luaSequence(_field(type, 'functions'))) {
        final methodSnapshot = _symbolSnapshot(
          method,
          module: moduleSymbol,
          container: _scalarString(_field(type, 'fullname')),
        );
        methodSymbols.add(methodSnapshot['symbol']! as String);
        symbols.add(methodSnapshot);
      }

      typeSnapshots.add(<String, Object?>{
        'symbol': _scalarString(_field(type, 'fullname')),
        'module': moduleSymbol,
        'name': _scalarString(_field(type, 'name')),
        'description': _descriptionFor(type),
        'supertypes': _luaSequence(_field(type, 'supertypes'))
            .map((supertype) => _scalarString(_field(supertype, 'fullname')))
            .toList(growable: false),
        'methodSymbols': methodSymbols,
        'wikiPath':
            'https://www.love2d.org/wiki/${_scalarString(_field(type, 'fullname'))}',
      });
    }

    for (final enumValue in _luaSequence(_field(module, 'enums'))) {
      enumSnapshots.add(<String, Object?>{
        'symbol': _scalarString(_field(enumValue, 'fullname')),
        'module': moduleSymbol,
        'name': _scalarString(_field(enumValue, 'name')),
        'description': _descriptionFor(enumValue),
        'constants': _luaSequence(_field(enumValue, 'constants'))
            .map(
              (constant) => <String, Object?>{
                'name': _scalarString(_field(constant, 'name')),
                'description': _descriptionFor(constant),
              },
            )
            .toList(growable: false),
        'wikiPath':
            'https://www.love2d.org/wiki/${_scalarString(_field(enumValue, 'fullname'))}',
      });
    }
  }

  return <String, Object?>{
    'version': version,
    'sourceCommit': sourceCommit,
    'modules': modules,
    'symbols': symbols,
    'types': typeSnapshots,
    'enums': enumSnapshots,
  };
}

Map<String, Object?> _moduleSnapshot(Object? module) {
  final symbol = _scalarString(_field(module, 'fullname'));
  return <String, Object?>{
    'symbol': symbol,
    'name': _scalarString(_field(module, 'name')),
    'description': _descriptionFor(module),
    'wikiPath': 'https://www.love2d.org/wiki/$symbol',
  };
}

Map<String, Object?> _symbolSnapshot(
  Object? symbol, {
  required String module,
  String? container,
}) {
  final symbolName = _scalarString(_field(symbol, 'fullname'));
  return <String, Object?>{
    'symbol': symbolName,
    'module': module,
    'name': _scalarString(_field(symbol, 'name')),
    'kind': _scalarString(_field(symbol, 'what')),
    'description': _descriptionFor(symbol),
    ...?switch (container) {
      final String value => <String, Object?>{'container': value},
      null => null,
    },
    'variants': _luaSequence(_field(symbol, 'variants'))
        .map(
          (variant) => <String, Object?>{
            'arguments': _luaSequence(_field(variant, 'arguments'))
                .map(
                  (argument) => <String, Object?>{
                    'name': _scalarString(_field(argument, 'name')),
                    'type': _scalarString(_field(argument, 'type')),
                    'description': _descriptionFor(argument),
                    ...?switch (_optionalScalarString(
                      _field(argument, 'default'),
                    )) {
                      final String value => <String, Object?>{
                        'defaultValue': value,
                      },
                      null => null,
                    },
                  },
                )
                .toList(growable: false),
            'returns': _luaSequence(_field(variant, 'returns'))
                .map(
                  (result) => <String, Object?>{
                    'name': _scalarString(_field(result, 'name')),
                    'type': _scalarString(_field(result, 'type')),
                    'description': _descriptionFor(result),
                  },
                )
                .toList(growable: false),
          },
        )
        .toList(growable: false),
    'wikiPath': 'https://www.love2d.org/wiki/$symbolName',
  };
}

String _descriptionFor(Object? value) {
  final description = _optionalScalarString(_field(value, 'description'));
  if (description != null && description.trim().isNotEmpty) {
    return _normalizeWhitespace(description);
  }
  final mini = _optionalScalarString(_field(value, 'minidescription'));
  return _normalizeWhitespace(mini ?? '');
}

String _normalizeWhitespace(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed.split('\n').map((line) => line.trim()).join('\n');
}

Object? _field(Object? table, Object key) {
  final map = _asTable(table);
  for (final entry in map.entries) {
    final normalizedKey = _normalizeValue(entry.key);
    if (normalizedKey == key) {
      return entry.value;
    }
  }
  return null;
}

List<Object?> _luaSequence(Object? table) {
  final map = _asTable(table);
  final indexed = <int, Object?>{};
  for (final entry in map.entries) {
    final normalizedKey = _normalizeValue(entry.key);
    if (normalizedKey is int) {
      indexed[normalizedKey] = entry.value;
    }
  }
  final keys = indexed.keys.toList()..sort();
  return <Object?>[for (final key in keys) indexed[key]];
}

Map<Object?, Object?> _asTable(Object? value) {
  final normalized = value is Value ? value.raw : value;
  if (normalized is Map<Object?, Object?>) {
    return normalized;
  }
  if (normalized is Map) {
    return normalized.cast<Object?, Object?>();
  }
  return const <Object?, Object?>{};
}

Object? _normalizeValue(Object? value) {
  var current = value;
  while (current is Value) {
    current = current.raw;
  }
  return switch (current) {
    final LuaString luaString => luaString.toString(),
    _ => current,
  };
}

String _scalarString(Object? value) {
  final normalized = _normalizeValue(value);
  return normalized?.toString() ?? '';
}

String? _optionalScalarString(Object? value) {
  final normalized = _normalizeValue(value);
  return normalized?.toString();
}
