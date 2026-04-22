import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'package:love2d/src/runtime/flame/love_flame_live_video_overlay.dart';

import 'test_support/memory_filesystem_test_support.dart';

const String _videoTextureShaderSource = '''
// LOVE2D_FLUTTER_FRAGMENT_ASSET: test_assets/shaders/runtime_effect_uniform_texture.frag
extern Image uTexture;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  return Texel(uTexture, vec2(0.5, 0.5));
}
''';

const String _desaturationTintShaderSource = '''
extern vec4 tint;
extern number strength;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
{
  color = Texel(texture, tc);
  number luma = dot(vec3(0.299f, 0.587f, 0.114f), color.rgb);
  return mix(color, tint * luma, strength);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame renders shader-bound video through sampled image fallback',
    () async {
      final provider = _FakeLiveVideoFrameProvider();
      final game = LoveFlameHarnessGame(
        videoFrameProviderFactory: (source, {bytes, metadata}) async =>
            provider,
      );
      final runtime = LoveScriptRuntime(
        host: game.host,
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime.runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      await runtime.execute('''
local shader = love.graphics.newShader([[
$_videoTextureShaderSource
]])
local video = love.graphics.newVideo("videos/demo.ogv", {audio = false})

function love.draw()
  love.graphics.setShader(shader)
  love.graphics.draw(video, 0, 0)
  love.graphics.setShader()
end
''', scriptPath: 'game/main.lua');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      expect(provider.snapshotCalls, 1);
      final snapshot = runtime.context.graphics.snapshotScreenSurface();
      expect(snapshot.commands, hasLength(1));
      expect(snapshot.commands.single, isA<LoveImageCommand>());
      expect(buildLoveFlameLiveVideoOverlayEntries(snapshot), isEmpty);

      game.host.windowMetrics = const LoveWindowMetrics(width: 8, height: 4);
      game.presentFrame(snapshot);
      game.onGameResize(Vector2(32, 16));

      final pixel = await _renderUntil(
        game,
        size: const ui.Size(32, 16),
        predicate: (pixel) => pixel.r > 220 && pixel.g < 40 && pixel.b < 40,
      );

      expect(pixel.r, greaterThan(220));
      expect(pixel.g, lessThan(40));
      expect(pixel.b, lessThan(40));
      expect(pixel.a, 255);
    },
  );

  test(
    'LoveFlameHarnessGame renders supported LOVE video shaders through sampled image fallback',
    () async {
      final provider = _FakeLiveVideoFrameProvider();
      final game = LoveFlameHarnessGame(
        videoFrameProviderFactory: (source, {bytes, metadata}) async =>
            provider,
      );
      final runtime = LoveScriptRuntime(
        host: game.host,
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime.runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      await runtime.execute('''
local shader = love.graphics.newShader([[
$_desaturationTintShaderSource
]])
shader:send("tint", {1, 1, 1, 1 / 0.299})
shader:send("strength", 1.0)

local video = love.graphics.newVideo("videos/demo.ogv", {audio = false})

function love.draw()
  love.graphics.setShader(shader)
  love.graphics.draw(video, 0, 0)
  love.graphics.setShader()
end
''', scriptPath: 'game/main.lua');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      expect(provider.snapshotCalls, 1);
      final snapshot = runtime.context.graphics.snapshotScreenSurface();
      expect(snapshot.commands, hasLength(1));
      expect(snapshot.commands.single, isA<LoveImageCommand>());
      final command = snapshot.commands.single as LoveImageCommand;
      expect(command.shader, isNotNull);
      expect(command.shader!.kind, LoveShaderKind.desaturationTint);
      expect(buildLoveFlameLiveVideoOverlayEntries(snapshot), isEmpty);

      game.host.windowMetrics = const LoveWindowMetrics(width: 8, height: 4);
      game.presentFrame(snapshot);
      game.onGameResize(Vector2(32, 16));

      final pixel = await _renderUntil(
        game,
        size: const ui.Size(32, 16),
        predicate: (pixel) =>
            pixel.r >= 72 &&
            pixel.r <= 82 &&
            pixel.g >= 72 &&
            pixel.g <= 82 &&
            pixel.b >= 72 &&
            pixel.b <= 82,
      );

      expect(pixel.r, inInclusiveRange(72, 82));
      expect(pixel.g, inInclusiveRange(72, 82));
      expect(pixel.b, inInclusiveRange(72, 82));
      expect(pixel.a, 255);
    },
  );
}

final class _FakeLiveVideoFrameProvider
    implements LoveVideoFrameProvider, LoveVideoLivePresentation {
  @override
  final Object livePresentationHandle = Object();

  int snapshotCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    snapshotCalls++;
    final bytes = Uint8List(8 * 4 * 4);
    for (var offset = 0; offset < bytes.length; offset += 4) {
      bytes[offset] = 0xff;
      bytes[offset + 1] = 0x00;
      bytes[offset + 2] = 0x00;
      bytes[offset + 3] = 0xff;
    }
    return LoveVideoFrameSnapshot(
      width: 8,
      height: 4,
      bytes: bytes,
      pixelFormat: LoveVideoFramePixelFormat.rgba8888,
    );
  }
}

Future<({int r, int g, int b, int a})> _renderUntil(
  LoveFlameHarnessGame game, {
  required bool Function(({int r, int g, int b, int a}) pixel) predicate,
  required ui.Size size,
  int maxFrames = 20,
}) async {
  ({int r, int g, int b, int a})? lastPixel;
  for (var frame = 0; frame < maxFrames; frame++) {
    final rendered = await _renderFrame(game, size);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    rendered.dispose();
    expect(data, isNotNull);
    final pixel = _pixelAt(
      data!.buffer.asUint8List(),
      width: size.width.round(),
      height: size.height.round(),
    );
    lastPixel = pixel;
    if (predicate(pixel)) {
      return pixel;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  return lastPixel!;
}

Future<ui.Image> _renderFrame(LoveFlameHarnessGame game, ui.Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  game.render(canvas);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.round(), size.height.round());
  } finally {
    picture.dispose();
  }
}

({int r, int g, int b, int a}) _pixelAt(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  final sampleX = width ~/ 2;
  final sampleY = height ~/ 2;
  final offset = ((sampleY * width) + sampleX) * 4;
  return (
    r: pixels[offset],
    g: pixels[offset + 1],
    b: pixels[offset + 2],
    a: pixels[offset + 3],
  );
}

List<int> _fakeTheoraOggBytes({required int width, required int height}) {
  final packet = Uint8List(22);
  packet[0] = 0x80;
  const signature = 'theora';
  for (var index = 0; index < signature.length; index++) {
    packet[index + 1] = signature.codeUnitAt(index);
  }

  packet[7] = 3;
  packet[8] = 2;
  packet[9] = 1;

  final macroBlockWidth = ((width + 15) ~/ 16).clamp(0, 0xffff);
  final macroBlockHeight = ((height + 15) ~/ 16).clamp(0, 0xffff);
  packet[10] = (macroBlockWidth >> 8) & 0xff;
  packet[11] = macroBlockWidth & 0xff;
  packet[12] = (macroBlockHeight >> 8) & 0xff;
  packet[13] = macroBlockHeight & 0xff;
  packet[14] = (width >> 16) & 0xff;
  packet[15] = (width >> 8) & 0xff;
  packet[16] = width & 0xff;
  packet[17] = (height >> 16) & 0xff;
  packet[18] = (height >> 8) & 0xff;
  packet[19] = height & 0xff;

  return <int>[
    ...'OggS'.codeUnits,
    0x00,
    0x02,
    ...List<int>.filled(8, 0),
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    packet.length,
    ...packet,
  ];
}
