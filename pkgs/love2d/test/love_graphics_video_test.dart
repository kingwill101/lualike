import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Video bindings', () {
    test('newVideo accepts filename and VideoStream inputs', () async {
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
      final stream = await luaCallMethodList(video, 'getStream');
      final scaledVideo = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        <Object?>[
          stream,
          <Object?, Object?>{'audio': false, 'dpiscale': 2.0},
        ],
      );

      expect(await luaCallMethodList(video, 'type'), 'Video');
      expect(
        await luaCallMethodList(video, 'typeOf', const <Object?>['Drawable']),
        isTrue,
      );
      expect(await luaCallMethodList(video, 'getDimensions'), <Object?>[
        320,
        180,
      ]);
      expect(await luaCallMethodList(video, 'getWidth'), 320);
      expect(await luaCallMethodList(video, 'getHeight'), 180);
      expect(await luaCallMethodList(stream, 'type'), 'VideoStream');
      expect(await luaCallMethodList(stream, 'getFilename'), 'videos/demo.ogv');

      expect(await luaCallMethodList(scaledVideo, 'getDimensions'), <Object?>[
        160,
        90,
      ]);
    });

    test(
      'newVideo reports the upstream file-open error for missing sources',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(const <String, List<int>>{}),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final file = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFile'],
          const <Object?>['videos/missing.ogv'],
        );

        Future<void> expectOpenError(Future<Object?> Function() call) async {
          await expectLater(
            call,
            throwsA(
              isA<LuaError>().having(
                (error) => error.message,
                'message',
                contains('File is not open and cannot be opened'),
              ),
            ),
          );
        }

        await expectOpenError(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'newVideo'],
            const <Object?>[
              'videos/missing.ogv',
              <Object?, Object?>{'audio': false},
            ],
          ),
        );
        await expectOpenError(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'newVideo'],
            <Object?>[
              file,
              <Object?, Object?>{'audio': false},
            ],
          ),
        );
      },
    );

    test(
      'Video source sync and filter control mirror the wrapped stream',
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
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[44100, 22050, 16, 2],
        );
        final source = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'static'],
        );

        await luaCallMethodList(source, 'seek', const <Object?>[1.5]);
        await luaCallMethodList(video, 'setSource', <Object?>[source]);

        final attachedSource = await luaCallMethodList(video, 'getSource');
        expect(await luaCallMethodList(attachedSource, 'type'), 'Source');
        expect(await luaCallMethodList(video, 'tell'), closeTo(1.5, 0.0001));

        await luaCallMethodList(source, 'play');
        expect(await luaCallMethodList(video, 'isPlaying'), isTrue);
        await luaCallMethodList(video, 'pause');
        expect(await luaCallMethodList(source, 'isPlaying'), isFalse);

        await luaCallMethodList(video, 'setFilter', const <Object?>['nearest']);
        expect(await luaCallMethodList(video, 'getFilter'), <Object?>[
          'nearest',
          'nearest',
          1.0,
        ]);

        final detachedAt = await luaCallMethodList(video, 'tell');
        await luaCallMethodList(video, 'setSource');
        expect(await luaCallMethodList(video, 'getSource'), isNull);
        await luaCallMethodList(source, 'seek', const <Object?>[3.0]);
        expect(
          await luaCallMethodList(video, 'tell'),
          closeTo(detachedAt! as double, 0.0001),
        );
      },
    );

    test(
      'Video seek mirrors upstream stream semantics for negative offsets',
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

        await luaCallMethodList(video, 'seek', const <Object?>[-0.5]);
        expect(await luaCallMethodList(video, 'tell'), closeTo(-0.5, 0.0001));
      },
    );

    test('Video:seek uses Lua bad-argument text for invalid offsets', () async {
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

      await expectLater(
        () => luaCallMethodList(video, 'seek', const <Object?>[false]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            "bad argument #2 to 'seek' (number expected, got boolean)",
          ),
        ),
      );
    });

    test(
      'Video setSource helpers reject non-Source values with LOVE type errors',
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

        await expectLater(
          () => luaCallMethodList(video, 'setSource', const <Object?>[123]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to 'setSource' (Source expected, got number)",
            ),
          ),
        );

        await expectLater(
          () => luaCallMethodList(video, '_setSource', const <Object?>[123]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to '_setSource' (Source expected, got number)",
            ),
          ),
        );
      },
    );

    test('Video release is idempotent and invalidates the wrapper', () async {
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

      expect(await luaCallMethodList(video, 'release'), isTrue);
      expect(await luaCallMethodList(video, 'release'), isFalse);
      await expectLater(
        () => luaCallMethodList(video, 'play'),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Cannot use object after it has been released.',
          ),
        ),
      );
      expect(await luaCallMethodList(video, 'type'), 'Video');
      expect(
        await luaCallMethodList(video, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
    });

    test(
      'Video:getStream rewraps a live stream after an older proxy is released',
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
        final firstStream = await luaCallMethodList(video, 'getStream');

        expect(await luaCallMethodList(firstStream, 'release'), isTrue);

        final replacementStream = await luaCallMethodList(video, 'getStream');
        expect(
          await luaCallMethodList(replacementStream, 'getFilename'),
          'videos/demo.ogv',
        );
        expect(await luaCallMethodList(replacementStream, 'release'), isTrue);
      },
    );

    test(
      'draw rejects Video objects when no frame provider is available',
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

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'draw'],
            <Object?>[video, 0.0, 0.0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('does not yet support drawing Video objects'),
            ),
          ),
        );
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
