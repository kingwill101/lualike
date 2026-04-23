import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:lualike/lualike.dart' show EngineMode, LuaString;
import 'package:lualike/src/io/io_device.dart';
import 'package:love2d/love2d.dart';
import 'package:path/path.dart' as path;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('LoveFlameHarness defaults to bytecode runtime mode', () {
    const harness = LoveFlameHarness(entryAsset: 'assets/game/main.lua');

    expect(harness.engineMode, EngineMode.luaBytecode);
    expect(harness.automaticGc, isFalse);
  });

  testWidgets(
    'LoveFlameHarness stays in Prewarming until startup warmup completes',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final warmupComplete = Completer<void>();
      var warmupCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: _scriptAdapter('function love.load() end'),
            onQuitRequested: () async {},
            debugImageWarmupOverride: (_, _) {
              warmupCalls++;
              return warmupComplete.future;
            },
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Prewarming');
      expect(warmupCalls, 1);
      expect(find.text('Prewarming LOVE assets...'), findsOneWidget);
      expect(find.text('Running'), findsNothing);

      warmupComplete.complete();
      await _pumpUntilStatus(tester, 'Running');
    },
  );

  testWidgets(
    'LoveFlameHarness dispatches love.resize on viewport changes without a synthetic startup callback',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(320, 240));

      const script = '''
function love.resize(width, height)
  if width == 640 and height == 360 then
    love.event.quit()
  end
end
''';
      final adapter = _scriptAdapter(script);

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      await binding.setSurfaceSize(const Size(640, 360));
      await tester.pump();
      await _pumpUntilStatus(tester, 'Quit');
    },
  );

  testWidgets(
    'LoveFlameHarness maps pointer input through the fitted LOVE window viewport',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(640, 480));

      const confScript = '''
function love.conf(t)
  t.window.width = 960
  t.window.height = 540
end
''';
      const mainScript = '''
function love.mousepressed(x, y)
  if math.abs(x - 480) < 0.01 and math.abs(y - 270) < 0.01 then
    love.event.quit()
    return
  end

  error(string.format("mousepressed:%0.3f:%0.3f", x, y))
end
''';
      final adapter = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/conf.lua': confScript.codeUnits,
          'assets/game/main.lua': mainScript.codeUnits,
        }),
        assetKeys: const <String>[
          'assets/game/conf.lua',
          'assets/game/main.lua',
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      await tester.tapAt(tester.getCenter(find.byType(LoveFlameHarness)));
      await tester.pump();
      await _pumpUntilStatus(tester, 'Quit');
    },
  );

  testWidgets(
    'LoveFlameHarness keeps the configured LOVE mode when the host viewport resizes',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(640, 480));

      const confScript = '''
function love.conf(t)
  t.window.width = 960
  t.window.height = 540
end
''';
      const mainScript = '''
function love.resize(width, height)
  local modeWidth, modeHeight = love.window.getMode()
  if modeWidth ~= 960 or modeHeight ~= 540 then
    error(string.format("mode:%d:%d resize:%d:%d", modeWidth, modeHeight, width, height))
  end

  if width == 800 and height == 480 then
    love.event.quit()
  end
end
''';
      final adapter = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/conf.lua': confScript.codeUnits,
          'assets/game/main.lua': mainScript.codeUnits,
        }),
        assetKeys: const <String>[
          'assets/game/conf.lua',
          'assets/game/main.lua',
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      await binding.setSurfaceSize(const Size(800, 480));
      await tester.pump();
      await _pumpUntilStatus(tester, 'Quit');
    },
  );

  testWidgets(
    'LoveFlameHarness dispatches love.visible on app visibility changes without a synthetic startup callback',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const script = '''
function love.visible(visible)
  if not visible and not love.window.isVisible() then
    love.event.quit()
  end
end
''';
      final adapter = _scriptAdapter(script);

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await _pumpUntilStatus(tester, 'Quit');
    },
  );

  testWidgets(
    'LoveFlameHarness dispatches love.lowmemory from Flutter memory pressure notifications',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const script = '''
function love.lowmemory()
  love.event.quit()
end
''';
      final adapter = _scriptAdapter(script);

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      binding.handleMemoryPressure();
      await _pumpUntilStatus(tester, 'Quit');
    },
  );

  testWidgets(
    'LoveFlameHarness aborts queued quits when love.quit returns true',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var quitRequests = 0;
      const script = '''
function love.load()
  love.event.quit()
end

function love.quit()
  return true
end
''';
      final adapter = _scriptAdapter(script);

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {
              quitRequests++;
            },
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      await tester.pump(const Duration(milliseconds: 48));
      expect(find.text('Running'), findsOneWidget);
      expect(quitRequests, 0);
    },
  );

  testWidgets(
    'LoveFlameHarness restarts when LOVE queues quit with restart status',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var quitRequests = 0;
      const entryAsset = '/virtual/game/main.lua';
      final adapter = _SequencedFilesystemAdapter(<String, List<List<int>>>{
        entryAsset: <List<int>>[
          'function love.load() love.event.quit("restart") end'.codeUnits,
          'function love.load() error("restarted runtime") end'.codeUnits,
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: entryAsset,
            filesystemAdapter: adapter,
            onQuitRequested: () async {
              quitRequests++;
            },
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Error');

      expect(adapter.loadCount(entryAsset), greaterThanOrEqualTo(2));
      expect(quitRequests, 0);
    },
  );

  testWidgets(
    'LoveFlameHarness resets the graphics origin before each draw frame',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await binding.setSurfaceSize(null);
      });
      await binding.setSurfaceSize(const Size(320, 240));

      const script = '''
function love.draw()
  love.graphics.translate(5, 6)
  love.graphics.rectangle("fill", 0, 0, 10, 10)
end
''';
      final adapter = _scriptAdapter(script);

      await tester.pumpWidget(
        MaterialApp(
          home: LoveFlameHarness(
            entryAsset: 'assets/game/main.lua',
            filesystemAdapter: adapter,
            onQuitRequested: () async {},
          ),
        ),
      );
      await _pumpUntilStatus(tester, 'Running');

      final gameFinder = find.byWidgetPredicate(
        (widget) => widget is GameWidget,
      );

      var gameWidget = tester.widget<GameWidget>(gameFinder);
      var game = gameWidget.game as dynamic;
      var rectangle =
          game.host.graphics.commands.single as LoveRectangleCommand;
      expect(rectangle.transform.storage[12], closeTo(5, 1e-9));
      expect(rectangle.transform.storage[13], closeTo(6, 1e-9));

      await tester.pump(const Duration(milliseconds: 48));

      gameWidget = tester.widget<GameWidget>(gameFinder);
      game = gameWidget.game as dynamic;
      rectangle = game.host.graphics.commands.single as LoveRectangleCommand;
      expect(rectangle.transform.storage[12], closeTo(5, 1e-9));
      expect(rectangle.transform.storage[13], closeTo(6, 1e-9));
    },
  );
}

LoveAssetBundleFilesystemAdapter _scriptAdapter(String script) {
  return LoveAssetBundleFilesystemAdapter(
    bundle: _MapAssetBundle(<String, List<int>>{
      'assets/game/main.lua': script.codeUnits,
    }),
    assetKeys: const <String>['assets/game/main.lua'],
  );
}

Future<void> _pumpUntilStatus(
  WidgetTester tester,
  String status, {
  Duration step = const Duration(milliseconds: 16),
  int maxPumps = 120,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(step);
    if (find.text(status).evaluate().isNotEmpty) {
      return;
    }
  }

  final statusFinder = find.byKey(const Key('status-label'));
  final errorFinder = find.byKey(const Key('error-message'));
  final currentStatus = statusFinder.evaluate().isEmpty
      ? null
      : tester.widget<Text>(statusFinder).data;
  final errorMessage = errorFinder.evaluate().isEmpty
      ? null
      : tester.widget<Text>(errorFinder).data;

  fail(
    'Expected status "$status". Current status: '
    '${currentStatus ?? '<missing>'}. '
    'Error: ${errorMessage ?? '<none>'}',
  );
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, List<int>> _assets;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return _assetManifestDataForKeys(_assets.keys);
    }

    final bytes = _assets[key];
    if (bytes == null) {
      throw StateError('Missing asset: $key');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

ByteData _assetManifestDataForKeys(Iterable<String> keys) {
  final manifest = <String, List<Map<String, Object?>>>{
    for (final key in keys)
      key: <Map<String, Object?>>[
        <String, Object?>{'asset': key},
      ],
  };
  return const StandardMessageCodec().encodeMessage(manifest)!;
}

class _SequencedFilesystemAdapter implements LoveFilesystemAdapter {
  _SequencedFilesystemAdapter(Map<String, List<List<int>>> files)
    : _files = files.map(
        (key, values) => MapEntry(
          _normalizePath(key),
          values.map(Uint8List.fromList).toList(growable: false),
        ),
      );

  final Map<String, List<Uint8List>> _files;
  final Map<String, int> _loadCounts = <String, int>{};

  int loadCount(String key) => _loadCounts[key] ?? 0;

  @override
  String? get appdataDirectory => null;

  @override
  String? get executablePath => null;

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => true;

  @override
  bool get isMacOS => false;

  @override
  String? get userDirectory => null;

  @override
  String? get workingDirectory => null;

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      true;

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<bool> directoryExists(String path) async {
    final normalized = _normalizePath(path);
    final normalizedPath = normalized.endsWith('/')
        ? normalized
        : '$normalized/';
    return _files.keys.any((key) => key.startsWith(normalizedPath));
  }

  @override
  Future<bool> fileExists(String path) async =>
      _files.containsKey(_normalizePath(path));

  @override
  Future<int?> fileSize(String path) async =>
      _currentBytes(_normalizePath(path))?.length;

  @override
  Future<List<String>> listDirectory(String path) async {
    final normalized = _normalizePath(path);
    final normalizedPath = normalized.endsWith('/')
        ? normalized
        : '$normalized/';
    final entries = <String>{};
    for (final key in _files.keys) {
      if (!key.startsWith(normalizedPath)) {
        continue;
      }

      final remainder = key.substring(normalizedPath.length);
      if (remainder.isEmpty) {
        continue;
      }

      final separatorIndex = remainder.indexOf('/');
      entries.add(
        separatorIndex < 0 ? remainder : remainder.substring(0, separatorIndex),
      );
    }

    return entries.toList()..sort();
  }

  @override
  Future<DateTime?> modified(String path) async => null;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final bytes = await readFileBytes(_normalizePath(path));
    if (mode == 'r' && bytes != null) {
      return _MemoryReadIODevice(bytes);
    }

    throw UnsupportedError('openFile only supports read mode in this test');
  }

  @override
  Future<List<int>?> readFileBytes(String path) async =>
      _nextBytes(_normalizePath(path));

  Uint8List? _currentBytes(String path) {
    final versions = _files[path];
    if (versions == null || versions.isEmpty) {
      return null;
    }

    final count = _loadCounts[path] ?? 0;
    final index = count == 0 ? 0 : count - 1;
    return versions[index < versions.length ? index : versions.length - 1];
  }

  Uint8List? _nextBytes(String path) {
    final versions = _files[path];
    if (versions == null || versions.isEmpty) {
      return null;
    }

    final count = (_loadCounts[path] ?? 0) + 1;
    _loadCounts[path] = count;
    final index = count - 1;
    return versions[index < versions.length ? index : versions.length - 1];
  }

  static String _normalizePath(String value) {
    final normalized = path.posix.normalize(value.replaceAll('\\', '/'));
    return normalized == '.' ? '' : normalized;
  }
}

class _MemoryReadIODevice extends BaseIODevice {
  _MemoryReadIODevice(List<int> bytes)
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
  Future<ReadResult> read([String format = 'l']) async {
    checkOpen();
    validateReadFormat(format);

    final normalized = normalizeReadFormat(format);
    if (normalized == 'a') {
      final chunk = _bytes.sublist(_position.clamp(0, _bytes.length));
      _position = _bytes.length;
      return ReadResult(LuaString.fromBytes(chunk));
    }

    if (normalized == 'l' || normalized == 'L') {
      if (_position >= _bytes.length) {
        return ReadResult(null);
      }

      var end = _position;
      while (end < _bytes.length && _bytes[end] != 10) {
        end++;
      }

      final includeTerminator = normalized == 'L' && end < _bytes.length;
      final line = _bytes.sublist(_position, includeTerminator ? end + 1 : end);
      _position = end < _bytes.length ? end + 1 : _bytes.length;
      return ReadResult(LuaString.fromBytes(line));
    }

    if (normalized == 'n') {
      return ReadResult(null, 'number reads are not supported in this test');
    }

    final count = int.parse(normalized);
    if (_position >= _bytes.length) {
      return ReadResult(null);
    }

    final end = (_position + count).clamp(0, _bytes.length);
    final chunk = _bytes.sublist(_position, end);
    _position = end;
    return ReadResult(LuaString.fromBytes(chunk));
  }

  @override
  Future<WriteResult> write(String data) async =>
      WriteResult(false, 'File not open for writing');

  @override
  Future<WriteResult> writeBytes(List<int> bytes) async =>
      WriteResult(false, 'File not open for writing');

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
  Future<void> setBuffering(BufferMode mode, [int? size]) async {}

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
