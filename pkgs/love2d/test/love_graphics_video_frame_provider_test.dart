import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Video frame providers', () {
    test('newVideo snapshots through a host-provided frame provider', () async {
      final provider = _FakeVideoFrameProvider();
      String? createdSource;
      Uint8List? createdBytes;
      LoveVideoMetadata? createdMetadata;

      final runtime = createLuaLikeTestRuntime();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            createdSource = source;
            createdBytes = bytes == null ? null : Uint8List.fromList(bytes);
            createdMetadata = metadata;
            return provider;
          },
        ),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final videoValue = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        const <Object?>[
          'videos/demo.ogv',
          <Object?, Object?>{'audio': false},
        ],
      );
      await luaCallMethodList(videoValue, 'seek', const <Object?>[1.25]);

      final video = _unwrapVideo(videoValue);
      final snapshot = await video.snapshotFrame();

      expect(createdSource, 'videos/demo.ogv');
      expect(createdBytes, isNotNull);
      expect(createdMetadata, isNotNull);
      expect(createdMetadata!.pixelWidth, 320);
      expect(createdMetadata!.pixelHeight, 180);
      expect(provider.positions, hasLength(1));
      expect(provider.positions.single, closeTo(1.25, 0.0001));
      expect(snapshot, isNotNull);
      expect(snapshot!.width, 4);
      expect(snapshot.height, 3);
      expect(snapshot.pixelFormat, LoveVideoFramePixelFormat.bgra8888);
      expect(snapshot.bytes, hasLength(4 * 3 * 4));

      expect(await luaCallMethodList(videoValue, 'release'), isTrue);
      expect(provider.disposed, isTrue);
      expect(provider.disposeCalls, 1);
    });

    test('Video release is idempotent for frame-backed providers', () async {
      final provider = _FakeVideoFrameProvider();

      final runtime = createLuaLikeTestRuntime();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(
          videoFrameProviderFactory: (source, {bytes, metadata}) async {
            return provider;
          },
        ),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final videoValue = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        const <Object?>[
          'videos/demo.ogv',
          <Object?, Object?>{'audio': false},
        ],
      );

      expect(await luaCallMethodList(videoValue, 'release'), isTrue);
      expect(await luaCallMethodList(videoValue, 'release'), isFalse);
      expect(provider.disposeCalls, 1);
    });

    test('Video snapshotFrame returns null without a frame provider', () async {
      final video = LoveVideo(
        stream: LoveVideoStream(
          filename: 'videos/demo.ogv',
          metadata: const LoveVideoMetadata(pixelWidth: 320, pixelHeight: 180),
        ),
        dpiScale: 1.0,
      );

      expect(await video.snapshotFrame(), isNull);
      expect(await video.snapshotFrameAt(2.0), isNull);
      expect(video.hasFrameProvider, isFalse);
    });

    test(
      'Video methods propagate playback state into live-backed providers',
      () async {
        final provider = _FakePlaybackVideoFrameProvider();

        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            videoFrameProviderFactory: (source, {bytes, metadata}) async {
              return provider;
            },
          ),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final videoValue = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );

        await luaCallMethodList(videoValue, 'play');
        await luaCallMethodList(videoValue, 'pause');
        await luaCallMethodList(videoValue, 'seek', const <Object?>[1.25]);
        await luaCallMethodList(videoValue, 'rewind');

        expect(provider.playCalls, 1);
        expect(provider.pauseCalls, 1);
        expect(provider.seekPositions, <double>[1.25, 0.0]);
      },
    );
  });
}

final class _FakeVideoFrameProvider implements LoveVideoFrameProvider {
  final List<double> positions = <double>[];
  bool disposed = false;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
  }

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    positions.add(positionSeconds);
    return LoveVideoFrameSnapshot(
      width: 4,
      height: 3,
      bytes: Uint8List(4 * 3 * 4),
    );
  }
}

final class _FakePlaybackVideoFrameProvider
    implements
        LoveVideoFrameProvider,
        LoveVideoLivePresentation,
        LoveVideoPlaybackController {
  int playCalls = 0;
  int pauseCalls = 0;
  final List<double> seekPositions = <double>[];

  @override
  final Object livePresentationHandle = Object();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pauseVideo() async {
    pauseCalls++;
  }

  @override
  Future<void> playVideo() async {
    playCalls++;
  }

  @override
  Future<void> seekVideo(double positionSeconds) async {
    seekPositions.add(positionSeconds);
  }

  @override
  Future<LoveVideoFrameSnapshot?> snapshotAt(double positionSeconds) async {
    return LoveVideoFrameSnapshot(
      width: 4,
      height: 3,
      bytes: Uint8List(4 * 3 * 4),
    );
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

LoveVideo _unwrapVideo(Object? value) {
  final table = value is Value ? value.raw : value;
  expect(table, isA<Map>());

  final videos = (table! as Map<dynamic, dynamic>).values
      .whereType<LoveVideo>()
      .toList(growable: false);
  expect(videos, hasLength(1));
  return videos.single;
}
