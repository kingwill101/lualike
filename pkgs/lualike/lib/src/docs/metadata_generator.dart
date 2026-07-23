/// File generation for lualike library documentation metadata.
///
/// Use [generateMetadata] when documentation should be written to disk. For
/// in-memory rendering, use the functions exported by `package:lualike/docs.dart`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../interop.dart' show LuaLike;
import '../stdlib/library.dart' show Library;
import 'metadata_format.dart';
import 'renderer.dart';

extension _MetadataFormatExt on MetadataFormat {
  String get extension => switch (this) {
    MetadataFormat.html => 'html',
    MetadataFormat.json => 'json',
    MetadataFormat.luals => 'lua',
  };
}

/// Generates documentation files for libraries registered on [lua].
///
/// ```dart
/// final lua = LuaLike();
/// lua.vm.libraryRegistry.register(MyLibrary());
///
/// await generateMetadata(
///   lua,
///   outputDir: 'doc/api',
///   formats: {MetadataFormat.json, MetadataFormat.luals},
///   includeStdlib: false,
/// );
/// ```
///
/// [formats] selects HTML, JSON, LuaLS output, or any combination. When
/// [includeStdlib] is `false`, only libraries added to [lua] by the embedding
/// application are emitted.
///
/// When [split] is `false` (the default), one file per format is written using
/// [packageName] as the filename. When [split] is `true`, each documented
/// library gets its own file named `<library_name>.<ext>`.
///
/// [packageName] and [packageVersion] are auto-detected from the nearest
/// `pubspec.yaml` when omitted. Missing output directories are created
/// recursively. No files are written when [formats] is empty or no selected
/// libraries expose documentation.
Future<void> generateMetadata(
  LuaLike lua, {
  required String outputDir,
  Set<MetadataFormat> formats = const {
    MetadataFormat.html,
    MetadataFormat.json,
    MetadataFormat.luals,
  },
  bool includeStdlib = true,
  bool split = false,
  String? packageName,
  String? packageVersion,
  DocPageOptions? pageOptions,
}) async {
  if (formats.isEmpty) return;

  final resolved = _resolvePackageInfo(
    packageName: packageName,
    packageVersion: packageVersion,
  );
  final resolvedName = resolved.$1;
  final resolvedVersion = resolved.$2;

  final allLibraries = documentedLibrariesForRuntime(lua.vm);
  final libraries = includeStdlib
      ? allLibraries
      : _filterUserLibraries(allLibraries);

  if (libraries.isEmpty) return;

  final dir = Directory(outputDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  if (split) {
    await _writeSplit(
      dir,
      libraries,
      formats,
      resolvedName,
      resolvedVersion,
      pageOptions,
    );
  } else {
    await _writeCombined(
      dir,
      libraries,
      formats,
      resolvedName,
      resolvedVersion,
      pageOptions,
    );
  }
}

List<Library> _filterUserLibraries(List<Library> all) {
  final tmp = LuaLike();
  final stdlibTypes = <Type>{};
  for (final lib in documentedLibrariesForRuntime(tmp.vm)) {
    stdlibTypes.add(lib.runtimeType);
  }
  return all.where((lib) => !stdlibTypes.contains(lib.runtimeType)).toList();
}

Future<void> _writeCombined(
  Directory dir,
  List<Library> libraries,
  Set<MetadataFormat> formats,
  String packageName,
  String? packageVersion,
  DocPageOptions? pageOptions,
) async {
  for (final format in formats) {
    final content = _render(
      format,
      libraries,
      packageName: packageName,
      packageVersion: packageVersion,
      pageOptions: pageOptions,
    );
    final file = File(p.join(dir.path, '$packageName.${format.extension}'));
    await file.writeAsString(content);
  }
}

Future<void> _writeSplit(
  Directory dir,
  List<Library> libraries,
  Set<MetadataFormat> formats,
  String packageName,
  String? packageVersion,
  DocPageOptions? pageOptions,
) async {
  for (final lib in libraries) {
    final docs = lib.getDocs();
    if (docs.isEmpty) continue;

    final libName = lib.name.isEmpty ? 'base' : lib.name;
    final singleList = [lib];

    for (final format in formats) {
      final content = _render(
        format,
        singleList,
        packageName: packageName,
        packageVersion: packageVersion,
        pageOptions: pageOptions,
      );
      final file = File(p.join(dir.path, '$libName.${format.extension}'));
      await file.writeAsString(content);
    }
  }
}

String _render(
  MetadataFormat format,
  List<Library> libraries, {
  required String packageName,
  String? packageVersion,
  DocPageOptions? pageOptions,
}) {
  return switch (format) {
    MetadataFormat.html => renderDocsPage(
      libraries,
      options: pageOptions ?? const DocPageOptions(),
    ),
    MetadataFormat.json => renderDocsJson(
      libraries,
      packageName: packageName,
      packageVersion: packageVersion,
    ),
    MetadataFormat.luals => renderLuaLsAnnotations(
      libraries,
      packageName: packageName,
      packageVersion: packageVersion,
    ),
  };
}

(String name, String? version) _resolvePackageInfo({
  String? packageName,
  String? packageVersion,
}) {
  if (packageName != null && packageVersion != null) {
    return (packageName, packageVersion);
  }

  final pubspec = _findPubspec();
  if (pubspec == null) {
    return (packageName ?? 'unknown', packageVersion);
  }

  final name = packageName ?? pubspec['name'] as String? ?? 'unknown';
  final version = packageVersion ?? pubspec['version'] as String?;
  return (name, version);
}

Map<String, dynamic>? _findPubspec() {
  var dir = Directory.current;
  for (var i = 0; i < 20; i++) {
    final file = File(p.join(dir.path, 'pubspec.yaml'));
    if (file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final parsed = loadYaml(content);
        if (parsed is Map) {
          return parsed.cast<String, dynamic>();
        }
      } catch (_) {
        // Ignore parse errors; fall through to parent.
      }
      return null;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
