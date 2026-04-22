import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics draw(Video)', () {
    test(
      'queues an image command when a frame provider is available',
      () async {
        final provider = _FakeVideoFrameProvider();
        final runtime = Interpreter();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRaw(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRaw(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveImageCommand;
        expect(command.image.nativeImage, isA<ui.Image>());
        expect(command.image.imageData, isNull);
        expect(command.image.preferImageDataRendering, isFalse);
        expect(command.image.width, 8);
        expect(command.image.height, 4);
        expect(command.drawTransform.storage[0], closeTo(0.5, 0.0001));
        expect(command.drawTransform.storage[5], closeTo(0.5, 0.0001));
        expect(command.drawTransform.storage[12], closeTo(10.0, 0.0001));
        expect(command.drawTransform.storage[13], closeTo(20.0, 0.0001));
      },
    );

    test(
      'reuses the decoded native image when the provider returns the same snapshot',
      () async {
        final provider = _StickyVideoFrameProvider();
        final runtime = Interpreter();
        final host = LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        );
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 8, height: 4),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallRaw(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCallRaw(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 10.0, 20.0],
        );
        await luaCallRaw(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[video, 20.0, 30.0],
        );

        expect(provider.snapshotCalls, 2);
        expect(host.graphics.commands, hasLength(2));
        final first = host.graphics.commands.first as LoveImageCommand;
        final second = host.graphics.commands.last as LoveImageCommand;
        expect(second.image, same(first.image));
        expect(first.image.nativeImage, isA<ui.Image>());
        expect(second.image.nativeImage, same(first.image.nativeImage));
      },
    );
  });
}

final class _FakeVideoFrameProvider implements LoveVideoFrameProvider {
  @override
  Future<void> dispose() async {}

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    return LoveVideoFrameSnapshot(
      width: 8,
      height: 4,
      bytes: Uint8List.fromList(<int>[
        0x30,
        0x20,
        0x10,
        0xff,
        ...List<int>.filled((8 * 4 * 4) - 4, 0),
      ]),
    );
  }
}

final class _StickyVideoFrameProvider implements LoveVideoFrameProvider {
  _StickyVideoFrameProvider()
    : _snapshot = LoveVideoFrameSnapshot(
        width: 8,
        height: 4,
        bytes: Uint8List.fromList(<int>[
          0x30,
          0x20,
          0x10,
          0xff,
          ...List<int>.filled((8 * 4 * 4) - 4, 0),
        ]),
      );

  final LoveVideoFrameSnapshot _snapshot;
  int snapshotCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    snapshotCalls++;
    return _snapshot;
  }
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
