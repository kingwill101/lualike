// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/src/io/io_device_shared.dart';
import 'package:love2d/love2d.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  group('LoveFlutterFilesystemAdapter', () {
    late PathProviderPlatform originalPathProviderPlatform;

    setUp(() {
      originalPathProviderPlatform = PathProviderPlatform.instance;
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProviderPlatform;
    });

    test(
      'exposes explicit Flutter directories and delegates filesystem IO',
      () async {
        final delegate = _FakeFilesystemAdapter(
          files: <String, List<int>>{'/save/config.lua': 'return 1'.codeUnits},
          directories: <String, List<String>>{
            '/save': <String>['config.lua'],
          },
        );
        final adapter = LoveFlutterFilesystemAdapter(
          delegate: delegate,
          workingDirectory: '/tmp/work',
          userDirectory: '/tmp/user',
          appdataDirectory: '/tmp/appdata',
          executablePath: '/tmp/bin/app',
        );

        expect(adapter.workingDirectory, '/tmp/work');
        expect(adapter.userDirectory, '/tmp/user');
        expect(adapter.appdataDirectory, '/tmp/appdata');
        expect(adapter.executablePath, '/tmp/bin/app');

        expect(await adapter.fileExists('/save/config.lua'), isTrue);
        expect(await adapter.directoryExists('/save'), isTrue);
        expect(
          String.fromCharCodes(
            (await adapter.readFileBytes('/save/config.lua'))!,
          ),
          'return 1',
        );
        expect(await adapter.listDirectory('/save'), <String>['config.lua']);
        expect(await adapter.fileSize('/save/config.lua'), 8);

        final device = await adapter.openFile('/save/config.lua', 'r');
        addTearDown(device.close);
        final read = await device.read('a');
        expect(read.isSuccess, isTrue);
        expect(String.fromCharCodes(read.value! as List<int>), 'return 1');

        expect(await adapter.createDirectory('/save/subdir'), isTrue);
        expect(await adapter.deletePath('/save/config.lua'), isTrue);
        expect(delegate.createdDirectories, <String>['/save/subdir']);
        expect(delegate.deletedPaths, <String>['/save/config.lua']);
      },
    );

    test(
      'load accepts explicit directory overrides without plugin state',
      () async {
        final adapter = await LoveFlutterFilesystemAdapter.load(
          delegate: _FakeFilesystemAdapter(),
          workingDirectory: '/work',
          userDirectory: '/user',
          appdataDirectory: '/appdata',
          executablePath: '/app/bin/love',
        ).timeout(const Duration(milliseconds: 100));

        expect(adapter.workingDirectory, '/work');
        expect(adapter.userDirectory, '/user');
        expect(adapter.appdataDirectory, '/appdata');
        expect(adapter.executablePath, '/app/bin/love');
      },
    );

    test('load resolves directories from the Flutter path provider', () async {
      final adapter = await LoveFlutterFilesystemAdapter.load(
        delegate: _FakeFilesystemAdapter(),
        pathProviderPlatform: _FakePathProviderPlatform(
          appSupportPath: '/flutter/app_support',
          documentsPath: '/flutter/documents',
          temporaryPath: '/flutter/temporary',
        ),
      );

      expect(adapter.appdataDirectory, '/flutter/app_support');
      expect(adapter.userDirectory, '/flutter/documents');
      expect(adapter.workingDirectory, '/flutter/temporary');
    });
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    this.appSupportPath,
    this.documentsPath,
    this.temporaryPath,
  });

  final String? appSupportPath;
  final String? documentsPath;
  final String? temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async => appSupportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

class _FakeFilesystemAdapter implements LoveFilesystemAdapter {
  _FakeFilesystemAdapter({
    Map<String, List<int>>? files,
    Map<String, List<String>>? directories,
  }) : files = files ?? <String, List<int>>{},
       directories = directories ?? <String, List<String>>{};

  final Map<String, List<int>> files;
  final Map<String, List<String>> directories;
  final List<String> createdDirectories = <String>[];
  final List<String> deletedPaths = <String>[];

  @override
  String? get appdataDirectory => '/delegate/appdata';

  @override
  String? get executablePath => '/delegate/bin/love';

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;

  @override
  String? get userDirectory => '/delegate/user';

  @override
  String? get workingDirectory => '/delegate/work';

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async {
    createdDirectories.add(path);
    directories.putIfAbsent(path, () => <String>[]);
    return true;
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async {
    deletedPaths.add(path);
    return files.remove(path) != null || directories.remove(path) != null;
  }

  @override
  Future<bool> directoryExists(String path) async =>
      directories.containsKey(path);

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<int?> fileSize(String path) async => files[path]?.length;

  @override
  Future<List<String>> listDirectory(String path) async =>
      List<String>.from(directories[path] ?? const <String>[]);

  @override
  Future<DateTime?> modified(String path) async => null;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final bytes = files[path];
    if (bytes == null) {
      throw StateError('Missing file: $path');
    }
    return _FakeIODevice(bytes, mode);
  }

  @override
  Future<List<int>?> readFileBytes(String path) async => files[path];
}

class _FakeIODevice extends BaseIODevice {
  _FakeIODevice(List<int> bytes, super.mode)
    : _bytes = List<int>.unmodifiable(bytes) {
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
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    if (normalizeReadFormat(format) != 'a') {
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
  Future<WriteResult> write(String data) async {
    checkOpen();
    return WriteResult(false, 'File not open for writing');
  }

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async {
    checkOpen();
    return WriteResult(false, 'File not open for writing');
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
  Future<int> getPosition() async {
    checkOpen();
    return _position;
  }

  @override
  Future<bool> isEOF() async {
    checkOpen();
    return _position >= _bytes.length;
  }
}
