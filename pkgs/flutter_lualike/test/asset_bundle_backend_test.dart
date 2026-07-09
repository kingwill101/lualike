import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory [AssetBundle] for testing.
class _TestAssetBundle extends AssetBundle {
  final Map<String, String> _strings = {};
  final Map<String, Uint8List> _data = {};

  void addString(String key, String value) => _strings[key] = value;
  void addBytes(String key, List<int> bytes) => _data[key] = Uint8List.fromList(bytes);

  @override
  Future<ByteData> load(String key) async {
    final bytes = _data[key];
    if (bytes != null) return ByteData.view(bytes.buffer);
    final str = _strings[key];
    if (str != null) return ByteData.view(Uint8List.fromList(utf8.encode(str)).buffer);
    throw FlutterError('Asset not found: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final str = _strings[key];
    if (str != null) return str;
    throw FlutterError('Asset not found: $key');
  }

  @override
  Future<T> loadStructuredData<T>(String key, Future<T> Function(String) parser) async {
    final str = await loadString(key);
    return parser(str);
  }

  /// Simulates [AssetManifest.listAssets] behaviour.
  List<String> listAssets() => [..._strings.keys, ..._data.keys];
}

void main() {
  group('AssetBundleFileSystemBackend', () {
    late _TestAssetBundle bundle;
    late AssetBundleFileSystemBackend backend;

    setUp(() {
      bundle = _TestAssetBundle();
      backend = AssetBundleFileSystemBackend(bundle, assetRoot: 'assets');

      bundle.addString('assets/config.lua', 'return {debug = true}');
      bundle.addString('assets/plugins/hello/plugin.lua', '-- hello');
      bundle.addString('assets/plugins/hello/helper.lua', '-- helper');
      bundle.addBytes('assets/data.bin', [0, 1, 2, 255]);
    });

    test('fileExists returns true for existing files', () async {
      expect(await backend.fileExists('config.lua'), isTrue);
      expect(await backend.fileExists('plugins/hello/plugin.lua'), isTrue);
    });

    test('fileExists returns false for missing files', () async {
      expect(await backend.fileExists('nonexistent.lua'), isFalse);
    });

    test('fileExists resolves with assetRoot prefix', () async {
      expect(await backend.fileExists('config.lua'), isTrue);
    });

    test('directoryExists returns true when files exist under path', () async {
      expect(await backend.directoryExists('plugins/hello'), isTrue);
      expect(await backend.directoryExists('plugins'), isTrue);
    });

    test('directoryExists returns false for empty paths', () async {
      expect(await backend.directoryExists('empty'), isFalse);
    });

    test('readFileAsString returns file content', () async {
      final content = await backend.readFileAsString('config.lua');
      expect(content, equals('return {debug = true}'));
    });

    test('readFileAsString returns null for missing files', () async {
      final content = await backend.readFileAsString('missing.lua');
      expect(content, isNull);
    });

    test('readFileAsBytes returns file bytes', () async {
      final bytes = await backend.readFileAsBytes('data.bin');
      expect(bytes, equals([0, 1, 2, 255]));
    });

    test('readFileAsBytes returns null for missing files', () async {
      final bytes = await backend.readFileAsBytes('missing.bin');
      expect(bytes, isNull);
    });

    test('listDirectory returns files under a path', () async {
      final entries = await backend.listDirectory('plugins/hello');
      expect(entries, hasLength(2));
      expect(entries, contains('assets/plugins/hello/plugin.lua'));
      expect(entries, contains('assets/plugins/hello/helper.lua'));
    });

    test('listDirectory returns empty for unknown paths', () async {
      final entries = await backend.listDirectory('unknown');
      expect(entries, isEmpty);
    });

    test('fileSize returns length in bytes', () async {
      final size = await backend.fileSize('data.bin');
      expect(size, equals(4));
    });

    test('fileSize returns null for missing files', () async {
      final size = await backend.fileSize('missing.bin');
      expect(size, isNull);
    });

    test('getLastModified returns null', () async {
      expect(await backend.getLastModified('any'), isNull);
    });

    test('getCurrentDirectory returns assetRoot', () async {
      expect(backend.getCurrentDirectory(), equals('assets'));
    });

    test('write/delete/rename are no-ops', () async {
      await backend.writeFile('new.txt', 'content');
      expect(bundle.listAssets(), isNot(contains('assets/new.txt')));

      expect(await backend.createDirectory('/dir'), isFalse);
      expect(await backend.deletePath('/dir'), isFalse);
    });
  });

  group('AssetBundleFileSystemBackend without assetRoot', () {
    test('paths are used as-is when assetRoot is null', () async {
      final bundle = _TestAssetBundle();
      bundle.addString('data.txt', 'hello');
      final backend = AssetBundleFileSystemBackend(bundle);

      expect(await backend.fileExists('data.txt'), isTrue);
      expect(await backend.readFileAsString('data.txt'), equals('hello'));
    });
  });
}
