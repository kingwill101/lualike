import 'dart:convert' as convert;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d_test_bed/main_pong.dart';

Future<LoveAudioSourceBackend> _noopAudioBackendFactory(
  String source, {
  required String sourceType,
  Uint8List? bytes,
  String? mimeType,
}) async {
  return const LoveNoopAudioSourceBackend();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Modern Pong asset-bundle startup works under bytecode',
    (tester) async {
      final host = LoveHeadlessHost(
        audioBackendFactory: _noopAudioBackendFactory,
      );
      final runtime = LoveScriptRuntime(
        engineMode: EngineMode.luaBytecode,
        host: host,
        filesystemAdapter: await LoveAssetBundleFilesystemAdapter.load(
          bundle: rootBundle,
          fallback: LoveLualikeFilesystemAdapter(),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime.runtime);

      expect(filesystem.setSource(modernPongEntryAsset), isTrue);
      await runtime.loadConfIfPresent();
      final entryData = await filesystem.readFileData(
        'main.lua',
        filename: modernPongEntryAsset,
      );

      expect(entryData, isNotNull);
      final data = entryData!;
      await runtime
          .execute(convert.utf8.decode(data.bytes), scriptPath: data.filename)
          .timeout(const Duration(seconds: 10));
      await runtime.callLoadIfDefined().timeout(const Duration(seconds: 10));

      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined().timeout(const Duration(seconds: 10));

      expect(runtime.context.graphics.commands, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 35)),
  );
}
