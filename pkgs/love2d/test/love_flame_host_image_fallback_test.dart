import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHost image loading falls back to mounted LOVE filesystem for nested asset paths',
    () async {
      final script = '''
local image = love.graphics.newImage("sprites/logo.png")
loaded_dimensions = string.format("%dx%d", image:getWidth(), image:getHeight())
''';
      final bundle = _MapAssetBundle(<String, List<int>>{
        'assets/game/main.lua': Uint8List.fromList(script.codeUnits),
        'assets/game/sprites/logo.png': _encodeTestPng(),
      });
      final adapter = LoveAssetBundleFilesystemAdapter(
        bundle: bundle,
        assetKeys: const <String>[
          'assets/game/main.lua',
          'assets/game/sprites/logo.png',
        ],
      );
      final host = LoveFlameHost(game: _TestGame(), assetBundle: bundle);

      final runtime = LoveScriptRuntime(host: host, filesystemAdapter: adapter);
      final filesystem = LoveFilesystemState.of(runtime.runtime);
      expect(filesystem.setSource('assets/game/main.lua'), isTrue);

      await runtime.execute(script, scriptPath: 'assets/game/main.lua');

      expect(runtime.unwrapGlobal('loaded_dimensions'), '2x2');
      expect(
        host.game.images.containsKey('assets/game/sprites/logo.png'),
        isTrue,
      );
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
      expect(host.game.images.containsKey('custom/sprite.png'), isTrue);
    },
  );

  test(
    'LoveFlameHost keeps source-backed images on the native-image rendering path',
    () async {
      final bundle = _MapAssetBundle(<String, List<int>>{
        'assets/game/main.lua': Uint8List(0),
        'assets/game/sprite.png': _encodeTestPng(),
      });
      final runtime = LoveScriptRuntime(
        host: LoveFlameHost(game: _TestGame(), assetBundle: bundle),
        filesystemAdapter: LoveAssetBundleFilesystemAdapter(
          bundle: bundle,
          assetKeys: const <String>[
            'assets/game/main.lua',
            'assets/game/sprite.png',
          ],
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime.runtime);
      expect(filesystem.setSource('assets/game/main.lua'), isTrue);

      await runtime.execute(r'''
image = love.graphics.newImage("sprite.png")
''');

      final image = _unwrapImage(runtime, 'image');
      expect(image.nativeImage, isNotNull);
      expect(image.preferImageDataRendering, isFalse);
    },
  );

  test(
    'LoveFlameHost refreshes native images for ImageData-backed newImage and replacePixels',
    () async {
      final runtime = LoveScriptRuntime(
        host: LoveFlameHost(
          game: _TestGame(),
          assetBundle: _MapAssetBundle({}),
        ),
      );

      await runtime.execute(r'''
local data = love.image.newImageData(2, 2)
data:setPixel(0, 0, 1, 0, 0, 1)
data:setPixel(1, 0, 0, 1, 0, 1)
data:setPixel(0, 1, 0, 0, 1, 1)
data:setPixel(1, 1, 1, 1, 1, 1)

image = love.graphics.newImage(data)

local patch = love.image.newImageData(1, 1)
patch:setPixel(0, 0, 1, 1, 0, 1)
image:replacePixels(patch, 1, 1, 1, 1, false)
''');

      final image = _unwrapImage(runtime, 'image');
      expect(image.nativeImage, isNotNull);
      expect(image.preferImageDataRendering, isFalse);
      expect(
        image.imageData!.getPixel(1, 1),
        const LoveColor(1.0, 1.0, 0.0, 1.0),
      );
    },
  );

  test(
    'LoveFlameHost keeps Canvas:newImageData pixel readback correct',
    () async {
      final runtime = LoveScriptRuntime(
        host: LoveFlameHost(
          game: _TestGame(),
          assetBundle: _MapAssetBundle({}),
        ),
      );

      await runtime.execute(r'''
local canvas = love.graphics.newCanvas(2, 2, {readable = true})

canvas:renderTo(function()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 1, 1)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.rectangle("fill", 1, 0, 1, 1)
  love.graphics.setColor(0, 0, 1, 1)
  love.graphics.rectangle("fill", 0, 1, 1, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 1, 1, 1, 1)
end)

snapshot = canvas:newImageData()
top_left = {snapshot:getPixel(0, 0)}
top_right = {snapshot:getPixel(1, 0)}
bottom_left = {snapshot:getPixel(0, 1)}
bottom_right = {snapshot:getPixel(1, 1)}
''');

      expect(runtime.unwrapGlobal('top_left'), <Object?, Object?>{
        1: 1.0,
        2: 0.0,
        3: 0.0,
        4: 1.0,
      });
      expect(runtime.unwrapGlobal('top_right'), <Object?, Object?>{
        1: 0.0,
        2: 1.0,
        3: 0.0,
        4: 1.0,
      });
      expect(runtime.unwrapGlobal('bottom_left'), <Object?, Object?>{
        1: 0.0,
        2: 0.0,
        3: 1.0,
        4: 1.0,
      });
      expect(runtime.unwrapGlobal('bottom_right'), <Object?, Object?>{
        1: 1.0,
        2: 1.0,
        3: 1.0,
        4: 1.0,
      });
    },
  );

  test(
    'LoveFlameHost can prewarm a bundled image into the Flame cache',
    () async {
      final host = LoveFlameHost(
        game: _TestGame(),
        assetBundle: _MapAssetBundle(<String, List<int>>{
          'assets/game/sprites/logo.png': _encodeTestPng(),
        }),
      );

      await host.prewarmImageAsset('assets/game/sprites/logo.png');
      expect(
        host.game.images.containsKey('assets/game/sprites/logo.png'),
        isTrue,
      );
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

LoveImage _unwrapImage(LoveScriptRuntime runtime, String globalName) {
  final wrapped = runtime.unwrapGlobal(globalName);
  expect(wrapped, isA<Map<dynamic, dynamic>>());
  final image = (wrapped! as Map<dynamic, dynamic>)['__love2d_image__'];
  expect(image, isA<LoveImage>());
  return image! as LoveImage;
}
