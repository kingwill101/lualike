import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d_test_bed/main_example_video.dart';

const _videoExampleScript = '''
local quit_sent = false

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

void main() {
  testWidgets(
    'LOVE video example boots the vendored sample through the runner',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(960, 640));

      final assets = <String, List<int>>{
        'assets/love_example_browser/conf.lua': Uint8List(0),
        'assets/love_example_browser/video_test_runner.lua': Uint8List.fromList(
          'love.filesystem.load("examples/video_test.lua")()\n'.codeUnits,
        ),
        'assets/love_example_browser/examples/video_test.lua':
            Uint8List.fromList(_videoExampleScript.codeUnits),
      };
      final bundle = _MapAssetBundle(assets);

      var quitCount = 0;
      await tester.pumpWidget(
        LoveExampleVideoApp(
          bundle: bundle,
          filesystemAdapter: LoveLualikeFilesystemAdapter(),
          onQuitRequested: () async {
            quitCount++;
          },
        ),
      );

      for (var index = 0; index < 60 && quitCount == 0; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('LOVE Video Example'), findsOneWidget);
      expect(quitCount, 1);
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
