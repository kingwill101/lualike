// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/src/io/io_device_shared.dart';
import 'package:love2d/love2d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoveAssetBundleFilesystemAdapter', () {
    late LoveAssetBundleFilesystemAdapter adapter;

    setUp(() {
      adapter = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': Uint8List.fromList('return 1'.codeUnits),
          'assets/game/states/menu.lua': Uint8List.fromList(
            'return {}'.codeUnits,
          ),
          'assets/game/sprites/logo.png': <int>[0, 1, 2, 3],
        }),
        assetKeys: const <String>[
          'assets/game/main.lua',
          'assets/game/states/menu.lua',
          'assets/game/sprites/logo.png',
        ],
      );
    });

    test('reports bundled files and directories', () async {
      expect(await adapter.fileExists('assets/game/main.lua'), isTrue);
      expect(await adapter.fileExists('assets/game/missing.lua'), isFalse);

      expect(await adapter.directoryExists('assets/game'), isTrue);
      expect(await adapter.directoryExists('assets/game/states'), isTrue);
      expect(await adapter.directoryExists('assets/game/unknown'), isFalse);
    });

    test('reads bundled bytes and lists child entries', () async {
      final bytes = await adapter.readFileBytes('assets/game/main.lua');
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'return 1');

      final rootItems = await adapter.listDirectory('assets/game');
      expect(rootItems, containsAll(<String>['main.lua', 'sprites', 'states']));

      final stateItems = await adapter.listDirectory('assets/game/states');
      expect(stateItems, <String>['menu.lua']);
    });

    test(
      'missing bundled reads do not probe an implicit host fallback',
      () async {
        expect(
          await adapter
              .readFileBytes('assets/game/missing.lua')
              .timeout(const Duration(milliseconds: 100)),
          isNull,
        );
        expect(
          await adapter
              .readFileBytes('conf.lua')
              .timeout(const Duration(milliseconds: 100)),
          isNull,
        );
      },
    );

    test('opens bundled files as readable devices', () async {
      final device = await adapter.openFile('assets/game/main.lua', 'r');
      addTearDown(device.close);

      final read = await device.read('a');
      expect(read.isSuccess, isTrue);
      expect(String.fromCharCodes(read.value as List<int>), 'return 1');
    });

    test(
      'bundled readable devices tokenize numeric reads like standard IO',
      () async {
        final numericAdapter = LoveAssetBundleFilesystemAdapter(
          bundle: _MapAssetBundle(<String, List<int>>{
            'assets/game/numbers.txt': Uint8List.fromList(
              '123abc 0x1p+2X'.codeUnits,
            ),
          }),
          assetKeys: const <String>['assets/game/numbers.txt'],
        );

        final device = await numericAdapter.openFile(
          'assets/game/numbers.txt',
          'r',
        );
        addTearDown(device.close);

        final firstNumber = await device.read('n');
        expect(firstNumber.isSuccess, isTrue);
        expect(firstNumber.value, 123);

        final trailingCharacters = await device.read('3');
        expect(trailingCharacters.isSuccess, isTrue);
        expect(
          String.fromCharCodes(trailingCharacters.value! as List<int>),
          'abc',
        );

        final separator = await device.read('1');
        expect(separator.isSuccess, isTrue);
        expect(String.fromCharCodes(separator.value! as List<int>), ' ');

        final secondNumber = await device.read('n');
        expect(secondNumber.isSuccess, isTrue);
        expect((secondNumber.value as num).toDouble(), closeTo(4.0, 1.0e-9));

        final trailingMarker = await device.read('1');
        expect(trailingMarker.isSuccess, isTrue);
        expect(String.fromCharCodes(trailingMarker.value! as List<int>), 'X');
      },
    );

    test(
      'public LOVE filesystem binding can use a bundled .love archive as source',
      () async {
        final archiveAdapter = LoveAssetBundleFilesystemAdapter(
          bundle: _MapAssetBundle(<String, List<int>>{
            'assets/game.love': ZipEncoder().encodeBytes(
              Archive()
                ..add(ArchiveFile.string('main.lua', 'return "archive"'))
                ..add(
                  ArchiveFile.string(
                    'lib/tool.lua',
                    'return { answer = 55, label = "bundle" }',
                  ),
                ),
            ),
          }),
          assetKeys: const <String>['assets/game.love'],
        );
        final runtime = LoveScriptRuntime(filesystemAdapter: archiveAdapter);

        await runtime.execute('''
love.filesystem.setSource("assets/game.love")
local contents = love.filesystem.read("main.lua")
local tool, toolPath = require("lib.tool")
result = {
  contents = contents,
  answer = tool.answer,
  label = tool.label,
  toolPath = toolPath,
  realDir = love.filesystem.getRealDirectory("main.lua"),
  source = love.filesystem.getSource(),
  sourceBase = love.filesystem.getSourceBaseDirectory(),
}
''');

        final result = runtime.unwrapGlobalTable('result')!;
        expect(result['contents'], 'return "archive"');
        expect(result['answer'], 55);
        expect(result['label'], 'bundle');
        expect(result['toolPath'], 'lib/tool.lua');
        expect(result['realDir'], 'assets/game.love');
        expect(result['source'], 'assets/game.love');
        expect(result['sourceBase'], 'assets');
      },
    );

    test('explicit fallback is still used for non-bundled paths', () async {
      final adapterWithFallback = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': Uint8List.fromList('return 1'.codeUnits),
        }),
        assetKeys: const <String>['assets/game/main.lua'],
        fallback: _TestFallbackFilesystemAdapter(
          files: <String, List<int>>{
            '/save/config.lua': Uint8List.fromList('return 2'.codeUnits),
          },
        ),
      );

      expect(await adapterWithFallback.fileExists('/save/config.lua'), isTrue);
      final bytes = await adapterWithFallback.readFileBytes('/save/config.lua');
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'return 2');
    });

    test('relative bundled misses do not probe an explicit fallback', () async {
      final adapterWithFallback = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': Uint8List.fromList('return 1'.codeUnits),
        }),
        assetKeys: const <String>['assets/game/main.lua'],
        fallback: _HangingFallbackFilesystemAdapter(),
      );

      expect(
        await adapterWithFallback
            .readFileBytes('assets/game/conf.lua')
            .timeout(const Duration(milliseconds: 100)),
        isNull,
      );
      expect(
        await adapterWithFallback
            .readFileBytes('conf.lua')
            .timeout(const Duration(milliseconds: 100)),
        isNull,
      );
    });
  });
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, List<int>> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw StateError('Missing asset: $key');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _TestFallbackFilesystemAdapter implements LoveFilesystemAdapter {
  _TestFallbackFilesystemAdapter({required this.files});

  final Map<String, List<int>> files;

  @override
  String? get appdataDirectory => '/save';

  @override
  String? get executablePath => '/bin/love';

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;

  @override
  String? get userDirectory => '/home/tester';

  @override
  String? get workingDirectory => '/workspace';

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      false;

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<bool> directoryExists(String path) async => false;

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<int?> fileSize(String path) async => files[path]?.length;

  @override
  Future<List<String>> listDirectory(String path) async => const <String>[];

  @override
  Future<DateTime?> modified(String path) async => null;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final bytes = files[path];
    if (bytes == null || mode.contains('w') || mode.contains('a')) {
      throw UnsupportedError('Unsupported fallback file access for $path');
    }
    return _TestIODevice(bytes);
  }

  @override
  Future<List<int>?> readFileBytes(String path) async => files[path];
}

class _TestIODevice extends BaseIODevice {
  _TestIODevice(List<int> bytes)
    : _bytes = List<int>.unmodifiable(bytes),
      super('r') {
    isClosed = false;
  }

  final List<int> _bytes;
  int _position = 0;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> flush() async {
    checkOpen();
  }

  @override
  Future<int> getPosition() async {
    checkOpen();
    return _position;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    return _position >= _bytes.length;
  }

  @override
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    final normalizedFormat = normalizeReadFormat(format);
    if (normalizedFormat != 'a') {
      return ReadResult(null, 'Unsupported read format "$format"');
    }
    if (_position >= _bytes.length) {
      return ReadResult(const <int>[]);
    }
    final remaining = _bytes.sublist(_position);
    _position = _bytes.length;
    return ReadResult(remaining);
  }

  @override
  Future<int> seek(SeekWhence whence, int offset) async {
    checkOpen();
    switch (whence) {
      case SeekWhence.set:
        _position = offset.clamp(0, _bytes.length);
      case SeekWhence.cur:
        _position = (_position + offset).clamp(0, _bytes.length);
      case SeekWhence.end:
        _position = (_bytes.length + offset).clamp(0, _bytes.length);
    }
    return _position;
  }

  @override
  Future<WriteResult> write(String data) async {
    checkOpen();
    return WriteResult(false, 'File not open for writing');
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    return WriteResult(false, 'File not open for writing');
  }
}

class _HangingFallbackFilesystemAdapter implements LoveFilesystemAdapter {
  @override
  String? get appdataDirectory => '/save';

  @override
  String? get executablePath => '/bin/love';

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;

  @override
  String? get userDirectory => '/home/tester';

  @override
  String? get workingDirectory => '/workspace';

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      false;

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<bool> directoryExists(String path) => Completer<bool>().future;

  @override
  Future<bool> fileExists(String path) => Completer<bool>().future;

  @override
  Future<int?> fileSize(String path) => Completer<int?>().future;

  @override
  Future<List<String>> listDirectory(String path) =>
      Completer<List<String>>().future;

  @override
  Future<DateTime?> modified(String path) => Completer<DateTime?>().future;

  @override
  Future<IODevice> openFile(String path, String mode) =>
      Completer<IODevice>().future;

  @override
  Future<List<int>?> readFileBytes(String path) =>
      Completer<List<int>?>().future;
}
