import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Video pixel dimensions', () {
    test(
      'Video pixel-dimension methods expose source-backed wrapper parity',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false},
          ],
        );
        final scaledVideo = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
          ],
        );

        expect(await luaCallMethodList(video, 'getDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(await luaCallMethodList(video, 'getPixelDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(await luaCallMethodList(video, 'getPixelWidth'), 320);
        expect(await luaCallMethodList(video, 'getPixelHeight'), 180);

        expect(await luaCallMethodList(scaledVideo, 'getDimensions'), <Object?>[
          160,
          90,
        ]);
        expect(
          await luaCallMethodList(scaledVideo, 'getPixelDimensions'),
          <Object?>[320, 180],
        );
        expect(await luaCallMethodList(scaledVideo, 'getPixelWidth'), 320);
        expect(await luaCallMethodList(scaledVideo, 'getPixelHeight'), 180);
      },
    );

    test(
      'newVideo defaults dpiscale to 1.0 like the vendored wrapper path',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            windowMetrics: const LoveWindowMetrics(dpiScale: 2.0),
          ),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final defaultVideo = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/demo.ogv'],
        );
        final emptySettingsVideo = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/demo.ogv', <Object?, Object?>{}],
        );
        final scaledVideo = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'dpiscale': 2.0},
          ],
        );

        expect(
          await luaCallMethodList(defaultVideo, 'getDimensions'),
          <Object?>[320, 180],
        );
        expect(
          await luaCallMethodList(emptySettingsVideo, 'getDimensions'),
          <Object?>[320, 180],
        );
        expect(await luaCallMethodList(scaledVideo, 'getDimensions'), <Object?>[
          160,
          90,
        ]);
      },
    );

    test(
      'newVideo logical dimensions truncate after dpiscale like Video.cpp',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/odd.ogv': _fakeTheoraOggBytes(width: 3, height: 5),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final scaledVideo = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/odd.ogv',
            <Object?, Object?>{'dpiscale': 2.0},
          ],
        );

        expect(await luaCallMethodList(scaledVideo, 'getDimensions'), <Object?>[
          1,
          2,
        ]);
        expect(
          await luaCallMethodList(scaledVideo, 'getPixelDimensions'),
          <Object?>[3, 5],
        );
      },
    );

    test(
      'newVideo rejects non-numeric dpiscale values like the low-level wrapper path',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'newVideo'],
            const <Object?>[
              'videos/demo.ogv',
              <Object?, Object?>{'dpiscale': false},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to '_newVideo' (number expected, got boolean)",
            ),
          ),
        );
      },
    );

    test(
      'newVideo accepts zero dpiscale and preserves pixel dimensions',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': 0.0},
          ],
        );

        expect(await luaCallMethodList(video, 'getDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(await luaCallMethodList(video, 'getPixelDimensions'), <Object?>[
          320,
          180,
        ]);
      },
    );

    test(
      'newVideo accepts negative dpiscale and preserves pixel dimensions',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/demo.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/demo.ogv',
            <Object?, Object?>{'audio': false, 'dpiscale': -2.0},
          ],
        );

        expect(await luaCallMethodList(video, 'getDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(await luaCallMethodList(video, 'getPixelDimensions'), <Object?>[
          320,
          180,
        ]);
      },
    );
  });
}

List<int> _fakeTheoraOggBytes({required int width, required int height}) {
  final packet = Uint8List(22);
  packet[0] = 0x80;
  final signature = 'theora';
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
