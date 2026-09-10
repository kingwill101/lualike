import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoveFlameHarness filesystem integration', () {
    late PathProviderPlatform originalPathProviderPlatform;
    late Directory tempRoot;
    late Directory appSupportDirectory;
    late Directory documentsDirectory;
    late Directory temporaryDirectory;

    setUp(() async {
      originalPathProviderPlatform = PathProviderPlatform.instance;
      tempRoot = await Directory.systemTemp.createTemp(
        'love-flame-harness-filesystem-',
      );
      appSupportDirectory = await Directory(
        path.join(tempRoot.path, 'app_support'),
      ).create(recursive: true);
      documentsDirectory = await Directory(
        path.join(tempRoot.path, 'documents'),
      ).create(recursive: true);
      temporaryDirectory = await Directory(
        path.join(tempRoot.path, 'temporary'),
      ).create(recursive: true);

      PathProviderPlatform.instance = _FakePathProviderPlatform(
        appSupportPath: appSupportDirectory.path,
        documentsPath: documentsDirectory.path,
        temporaryPath: temporaryDirectory.path,
      );
    });

    tearDown(() async {
      PathProviderPlatform.instance = originalPathProviderPlatform;
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
      'wraps direct asset adapters with a writable Flutter save-path fallback',
      () async {
        const script = '''
function love.load()
  love.filesystem.setIdentity("harness-save-test")
  assert(love.filesystem.write("state.txt", "saved payload"))
  local contents = love.filesystem.read("state.txt")
  assert(contents == "saved payload")
  love.event.quit()
end
''';
        final bundle = _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': script.codeUnits,
        });
        final sourceAdapter = LoveAssetBundleFilesystemAdapter(
          bundle: bundle,
          assetKeys: const <String>['assets/game/main.lua'],
        );
        final adapter = await resolveLoveFlameHarnessFilesystemAdapter(
          bundle: bundle,
          filesystemAdapter: sourceAdapter,
        );
        final runtime = LoveScriptRuntime(
          host: LoveFlameHarnessGame().host,
          filesystemAdapter: adapter,
        );
        final filesystem = LoveFilesystemState.of(runtime.runtime);

        expect(filesystem.setSource('assets/game/main.lua'), isTrue);
        await runtime.loadConfIfPresent();

        final entryData = await filesystem.readFileData(
          'main.lua',
          filename: 'assets/game/main.lua',
        );
        expect(entryData, isNotNull);

        await runtime.execute(
          String.fromCharCodes(entryData!.bytes),
          scriptPath: entryData.filename,
        );
        await runtime.callLoadIfDefined();
        runtime.context.beginDrawFrame();
        await runtime.callDrawIfDefined();

        LoveEventMessage? quitMessage;
        while (true) {
          final message = runtime.context.events.poll();
          if (message == null) {
            break;
          }
          if (message.name == 'quit' || message.name == 'q') {
            quitMessage ??= message;
          }
        }

        final saveFilePath = path.join(
          appSupportDirectory.path,
          'love',
          'harness-save-test',
          'state.txt',
        );
        expect(quitMessage, isNotNull);
        expect(await File(saveFilePath).exists(), isTrue);
        expect(await File(saveFilePath).readAsString(), 'saved payload');
      },
    );

    test(
      'can skip the implicit Flutter save-path fallback for asset-only sources',
      () async {
        final bundle = _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': 'return 1'.codeUnits,
        });
        final sourceAdapter = LoveAssetBundleFilesystemAdapter(
          bundle: bundle,
          assetKeys: const <String>['assets/game/main.lua'],
        );

        final adapter = await resolveLoveFlameHarnessFilesystemAdapter(
          bundle: bundle,
          filesystemAdapter: sourceAdapter,
          useFlutterFilesystemFallback: false,
        );

        expect(adapter, isA<LoveAssetBundleFilesystemAdapter>());
        expect(adapter.workingDirectory, isNull);
        expect(adapter.userDirectory, isNull);
        expect(adapter.appdataDirectory, isNull);
        expect(await adapter.fileExists('assets/game/main.lua'), isTrue);
      },
    );
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
