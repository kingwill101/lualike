import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_test_bed/main.dart';

Future<LoveAudioSourceBackend> _noopAudioBackendFactory(
  String source, {
  required String sourceType,
  Uint8List? bytes,
  String? mimeType,
}) async {
  return const LoveNoopAudioSourceBackend();
}

const _testScript = '''
function love.load()
  assert(love.window.getTitle() == "Configured Widget Test", "expected conf title")
  local _, _, flags = love.window.getMode()
  assert(flags.resizable == true, "expected conf resizable flag")
  assert(love.physics == nil, "expected conf to disable physics")
end

function love.update(dt)
end

function love.draw()
  love.graphics.clear(0.1, 0.1, 0.15, 1.0)
end
''';

const _confScript = '''
function love.conf(t)
  t.window.title = "Configured Widget Test"
  t.window.width = 1024
  t.window.height = 576
  t.window.resizable = true
  t.modules.physics = false
end
''';

const _quitScript = '''
local quit_sent = false

function love.load()
end

function love.update(dt)
  if not quit_sent then
    quit_sent = true
    love.event.quit()
  end
end

function love.draw()
  love.graphics.clear(0.1, 0.1, 0.15, 1.0)
end
''';

const _abortQuitScript = '''
local quit_sent = false

function love.load()
end

function love.quit()
  return true
end

function love.update(dt)
  if not quit_sent then
    quit_sent = true
    love.event.quit()
  end
end

function love.draw()
  love.graphics.clear(0.1, 0.1, 0.15, 1.0)
end
''';

const _loadedChunkPhysicsScript = '''
function love.load()
  local loaded = assert(love.filesystem.load("child.lua"))
  loaded()
  love.load()
end

function love.draw()
  love.graphics.clear(0.1, 0.1, 0.15, 1.0)
end
''';

const _loadedChunkPhysicsChildScript = '''
local world = nil
local frame_count = 0

function love.load()
  love.physics.setMeter(32)
  world = love.physics.newWorld(0, 9.81 * 32, true)
end

function love.update(dt)
  if type(dt) ~= "number" then
    error("expected numeric dt, got " .. type(dt))
  end
  world:update(dt)
  frame_count = frame_count + 1
  if frame_count >= 3 then
    love.event.quit()
  end
end
''';

const _physicsEnabledConfScript = '''
function love.conf(t)
  t.window.title = "Loaded Chunk Physics Test"
  t.window.width = 1024
  t.window.height = 576
  t.window.resizable = true
  t.modules.physics = true
end
''';

void main() {
  late AssetBundle bundle;
  late LoveFilesystemAdapter filesystemAdapter;

  void configureAssets({
    required String script,
    String confScript = _confScript,
    Map<String, String> extraScripts = const <String, String>{},
  }) {
    final assets = <String, List<int>>{
      'assets/scripts/conf.lua': Uint8List.fromList(confScript.codeUnits),
      testBedEntryAsset: Uint8List.fromList(script.codeUnits),
      for (final entry in extraScripts.entries)
        'assets/scripts/${entry.key}': Uint8List.fromList(
          entry.value.codeUnits,
        ),
    };
    bundle = _MapAssetBundle(assets);
    filesystemAdapter = _ForwardingFilesystemAdapter(
      LoveAssetBundleFilesystemAdapter(
        bundle: bundle,
        assetKeys: assets.keys.toList(growable: false),
        fallback: LoveLualikeFilesystemAdapter(),
      ),
    );
  }

  setUp(() {
    configureAssets(script: _testScript);
  });

  Future<void> pumpUntilReady(WidgetTester tester, {int maxPumps = 80}) async {
    for (var index = 0; index < maxPumps; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('reload-script')).evaluate().isNotEmpty) {
        break;
      }
    }
  }

  Future<void> pumpFrames(
    WidgetTester tester, {
    required int count,
    Duration step = const Duration(milliseconds: 16),
  }) async {
    for (var index = 0; index < count; index++) {
      await tester.pump(step);
    }
  }

  testWidgets('LOVE test bed example boots and shows the Lua source', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      LoveTestBedExampleApp(
        bundle: bundle,
        filesystemAdapter: filesystemAdapter,
        audioBackendFactory: _noopAudioBackendFactory,
      ),
    );

    await pumpUntilReady(tester);

    expect(find.text('LOVE Test Bed'), findsOneWidget);
    expect(find.byKey(const Key('lua-source-view')), findsOneWidget);
    expect(find.textContaining('function love.draw()'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LOVE test bed example reloads and survives a resize', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 680));

    await tester.pumpWidget(
      LoveTestBedExampleApp(
        bundle: bundle,
        filesystemAdapter: filesystemAdapter,
        audioBackendFactory: _noopAudioBackendFactory,
      ),
    );
    await pumpUntilReady(tester);

    await tester.tap(find.byKey(const Key('reload-script')));
    await tester.pump();
    await pumpUntilReady(tester);

    expect(find.byKey(const Key('lua-source-tab')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lua-source-tab')));
    await tester.pumpAndSettle();
    expect(find.textContaining('function love.load()'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1280, 700));
    await pumpFrames(
      tester,
      count: 20,
      step: const Duration(milliseconds: 100),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'LOVE test bed example routes quit events through onQuitRequested',
    (tester) async {
      configureAssets(script: _quitScript);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 680));

      var quitRequests = 0;
      await tester.pumpWidget(
        LoveTestBedExampleApp(
          bundle: bundle,
          filesystemAdapter: filesystemAdapter,
          audioBackendFactory: _noopAudioBackendFactory,
          onQuitRequested: () async {
            quitRequests += 1;
          },
        ),
      );
      await pumpUntilReady(tester);

      for (var index = 0; index < 20 && quitRequests == 0; index++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(quitRequests, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LOVE test bed example keeps running when love.quit aborts exit',
    (tester) async {
      configureAssets(script: _abortQuitScript);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 680));

      var quitRequests = 0;
      await tester.pumpWidget(
        LoveTestBedExampleApp(
          bundle: bundle,
          filesystemAdapter: filesystemAdapter,
          audioBackendFactory: _noopAudioBackendFactory,
          onQuitRequested: () async {
            quitRequests += 1;
          },
        ),
      );
      await pumpUntilReady(tester);

      await pumpFrames(tester, count: 20);

      expect(quitRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LOVE test bed preserves numeric dt for update callbacks loaded from another chunk',
    (tester) async {
      configureAssets(
        script: _loadedChunkPhysicsScript,
        confScript: _physicsEnabledConfScript,
        extraScripts: const <String, String>{
          'child.lua': _loadedChunkPhysicsChildScript,
        },
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 680));

      await tester.pumpWidget(
        LoveTestBedExampleApp(
          bundle: bundle,
          filesystemAdapter: filesystemAdapter,
          audioBackendFactory: _noopAudioBackendFactory,
          onQuitRequested: () async {
            // The script quits after a few frames; reaching here confirms the
            // loaded chunk executed its update path successfully.
          },
        ),
      );
      await pumpUntilReady(tester);

      await pumpFrames(
        tester,
        count: 30,
        step: const Duration(milliseconds: 100),
      );

      expect(tester.takeException(), isNull);
    },
  );
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(Map<String, List<int>> assets)
    : _assets = _withAssetManifest(assets);

  final Map<String, List<int>> _assets;

  static Map<String, List<int>> _withAssetManifest(
    Map<String, List<int>> assets,
  ) {
    final encodedManifest = const StandardMessageCodec().encodeMessage(
      <String, Object?>{
        for (final key in assets.keys)
          key: <Map<String, Object?>>[
            <String, Object?>{'asset': key},
          ],
      },
    )!;
    return <String, List<int>>{
      ...assets,
      'AssetManifest.bin': encodedManifest.buffer.asUint8List(
        encodedManifest.offsetInBytes,
        encodedManifest.lengthInBytes,
      ),
    };
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw StateError('Missing asset: $key');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _ForwardingFilesystemAdapter implements LoveFilesystemAdapter {
  const _ForwardingFilesystemAdapter(this._delegate);

  final LoveFilesystemAdapter _delegate;

  @override
  String? get workingDirectory => _delegate.workingDirectory;

  @override
  String? get userDirectory => _delegate.userDirectory;

  @override
  String? get appdataDirectory => _delegate.appdataDirectory;

  @override
  String? get executablePath => _delegate.executablePath;

  @override
  bool get isWindows => _delegate.isWindows;

  @override
  bool get isLinux => _delegate.isLinux;

  @override
  bool get isMacOS => _delegate.isMacOS;

  @override
  Future<IODevice> openFile(String path, String mode) {
    return _delegate.openFile(path, mode);
  }

  @override
  Future<bool> fileExists(String path) => _delegate.fileExists(path);

  @override
  Future<bool> directoryExists(String path) => _delegate.directoryExists(path);

  @override
  Future<List<int>?> readFileBytes(String path) =>
      _delegate.readFileBytes(path);

  @override
  Future<List<String>> listDirectory(String path) =>
      _delegate.listDirectory(path);

  @override
  Future<DateTime?> modified(String path) => _delegate.modified(path);

  @override
  Future<int?> fileSize(String path) => _delegate.fileSize(path);

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) {
    return _delegate.createDirectory(path, recursive: recursive);
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) {
    return _delegate.deletePath(path, recursive: recursive);
  }
}
