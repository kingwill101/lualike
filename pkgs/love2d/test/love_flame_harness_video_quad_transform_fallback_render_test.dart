import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';
import 'package:love2d/src/runtime/flame/love_flame_live_video_overlay.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LoveFlameHarnessGame renders quad-transformed sampled video frames on the canvas path',
    () async {
      final provider = _PatternVideoFrameProvider();
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
local video = love.graphics.newVideo("videos/demo.ogv", {audio = false})
local quad = love.graphics.newQuad(4, 0, 4, 4, 8, 4)
local transform = love.math.newTransform(2, 0)

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.draw(video, quad, transform)
end
''', scriptPath: 'game/main.lua');

      runtime.context.beginDrawFrame();
      await runtime.callDrawIfDefined();

      expect(provider.snapshotCalls, 1);
      final snapshot = runtime.context.graphics.snapshotScreenSurface();
      expect(snapshot.clearColor, const LoveColor(0, 0, 0, 1));
      expect(snapshot.commands, hasLength(1));
      expect(snapshot.commands.single, isA<LoveImageCommand>());
      final imageCommand = snapshot.commands.single as LoveImageCommand;
      expect(imageCommand.quad, isNotNull);
      expect(imageCommand.drawTransform.storage[12], closeTo(2.0, 0.0001));
      expect(buildLoveFlameLiveVideoOverlayEntries(snapshot), isEmpty);

      game.host.windowMetrics = const LoveWindowMetrics(width: 8, height: 4);
      game.presentFrame(snapshot);
      game.onGameResize(Vector2(8, 4));

      final rendered = await _renderFrame(game, const ui.Size(8, 4));
      addTearDown(rendered.dispose);
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(data, isNotNull);
      final bytes = data!.buffer.asUint8List();

      final background = _pixelAt(bytes, width: 8, x: 1, y: 1);
      final drawn = _pixelAt(bytes, width: 8, x: 3, y: 1);

      expect(background.r, 0);
      expect(background.g, 0);
      expect(background.b, 0);
      expect(background.a, 255);

      expect(drawn.r, lessThan(40));
      expect(drawn.g, greaterThan(220));
      expect(drawn.b, lessThan(40));
      expect(drawn.a, 255);
    },
  );
}

final class _PatternVideoFrameProvider implements LoveVideoFrameProvider {
  int snapshotCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    snapshotCalls++;
    final bytes = Uint8List(8 * 4 * 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 8; x++) {
        final offset = ((y * 8) + x) * 4;
        final isRightHalf = x >= 4;
        bytes[offset] = isRightHalf ? 0x00 : 0xff;
        bytes[offset + 1] = isRightHalf ? 0xff : 0x00;
        bytes[offset + 2] = 0x00;
        bytes[offset + 3] = 0xff;
      }
    }

    return LoveVideoFrameSnapshot(
      width: 8,
      height: 4,
      bytes: bytes,
      pixelFormat: LoveVideoFramePixelFormat.rgba8888,
    );
  }
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
  required int x,
  required int y,
}) {
  final offset = ((y * width) + x) * 4;
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
