import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love2d/love2d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHost image loading falls back to mounted LOVE filesystem for nested asset paths',
    () async {
      final script = '''
love.filesystem.setSource("assets/game/main.lua")
local image = love.graphics.newImage("sprites/logo.png")
loaded_dimensions = string.format("%dx%d", image:getWidth(), image:getHeight())
''';
      final adapter = LoveAssetBundleFilesystemAdapter(
        bundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/main.lua': Uint8List.fromList(script.codeUnits),
          'assets/game/sprites/logo.png': _encodeTestPng(),
        }),
        assetKeys: const <String>[
          'assets/game/main.lua',
          'assets/game/sprites/logo.png',
        ],
      );

      final runtime = LoveScriptRuntime(
        host: LoveFlameHost(game: _TestGame()),
        filesystemAdapter: adapter,
      );

      await runtime.execute(script, scriptPath: 'assets/game/main.lua');

      expect(runtime.unwrapGlobal('loaded_dimensions'), '2x2');
    },
  );

  test(
    'LoveFlameHost uses its injected asset bundle for direct image loads',
    () async {
      final host = LoveFlameHost(
        game: _TestGame(),
        assetBundle: _MapAssetBundle(<String, List<int>>{
          'custom/sprite.png': _encodeTestPng(),
        }),
      );

      final image = await host.loadImage('custom/sprite.png');
      expect(image.width, 2);
      expect(image.height, 2);
    },
  );

  test(
    'LoveFlameHost reports LOVE filesystem missing-file errors for relative newImage and newImageData string sources',
    () async {
      final runtime = LoveScriptRuntime(
        host: LoveFlameHost(
          game: _TestGame(),
          assetBundle: _MapAssetBundle(<String, List<int>>{
            'custom/sprite.png': _encodeTestPng(),
          }),
        ),
      );

      await runtime.execute(r'''
local ok_image, err_image = pcall(function()
  return love.graphics.newImage("custom/sprite.png")
end)
local ok_imagedata, err_imagedata = pcall(function()
  return love.image.newImageData("custom/sprite.png")
end)

image_ok = ok_image
image_error = tostring(err_image)
imagedata_ok = ok_imagedata
imagedata_error = tostring(err_imagedata)
''');

      expect(runtime.unwrapGlobal('image_ok'), isFalse);
      expect(
        runtime.unwrapGlobal('image_error'),
        contains('Could not open file custom/sprite.png. Does not exist.'),
      );
      expect(runtime.unwrapGlobal('imagedata_ok'), isFalse);
      expect(
        runtime.unwrapGlobal('imagedata_error'),
        contains('Could not open file custom/sprite.png. Does not exist.'),
      );
    },
  );
}

class _TestGame extends FlameGame {}

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

List<int> _encodeTestPng() {
  final image = img.Image(width: 2, height: 2);
  image.setPixelRgba(0, 0, 255, 0, 64, 255);
  image.setPixelRgba(1, 0, 0, 255, 128, 255);
  image.setPixelRgba(0, 1, 32, 64, 255, 255);
  image.setPixelRgba(1, 1, 255, 255, 255, 255);
  return Uint8List.fromList(img.encodePng(image));
}
