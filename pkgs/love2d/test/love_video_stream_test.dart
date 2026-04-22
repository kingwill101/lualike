import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.video VideoStream bindings', () {
    test(
      'newVideoStream missing argument uses the normal argument-1 type error',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          () => luaCallList(runtime, const ['love', 'video', 'newVideoStream']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.video.newVideoStream expected filename or File at argument 1',
              ),
            ),
          ),
        );
      },
    );

    test('newVideoStream supports filename and File inputs', () async {
      final runtime = Interpreter();
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

      final fromFilename = await luaCallList(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/demo.ogv'],
      );
      final file = await luaCallList(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['videos/demo.ogv'],
      );
      final fromFile = await luaCallList(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        <Object?>[file],
      );

      expect(await luaCallMethodList(fromFilename, 'type'), 'VideoStream');
      expect(
        await luaCallMethodList(fromFilename, 'typeOf', const <Object?>[
          'Object',
        ]),
        isTrue,
      );
      expect(
        await luaCallMethodList(fromFilename, 'typeOf', const <Object?>[
          'Stream',
        ]),
        isTrue,
      );
      expect(
        await luaCallMethodList(fromFilename, 'getFilename'),
        'videos/demo.ogv',
      );
      expect(
        await luaCallMethodList(fromFile, 'getFilename'),
        'videos/demo.ogv',
      );
    });

    test(
      'newVideoStream reports the upstream file-open error for missing sources',
      () async {
        final runtime = Interpreter();
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
            const ['love', 'video', 'newVideoStream'],
            const <Object?>['videos/missing.ogv'],
          ),
        );
        await expectOpenError(
          () => luaCallList(
            runtime,
            const ['love', 'video', 'newVideoStream'],
            <Object?>[file],
          ),
        );
      },
    );

    test('playback controls update tell and preserve pause state', () async {
      final runtime = Interpreter();
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

      final stream = await luaCallList(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/demo.ogv'],
      );

      expect(await luaCallMethodList(stream, 'isPlaying'), isFalse);
      expect(await luaCallMethodList(stream, 'tell'), 0.0);

      await luaCallMethodList(stream, 'play');
      expect(await luaCallMethodList(stream, 'isPlaying'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final playingPosition = await luaCallMethodList(stream, 'tell');
      expect(playingPosition, isA<double>());
      expect(playingPosition! as double, greaterThan(0.0));

      await luaCallMethodList(stream, 'pause');
      final pausedPosition = await luaCallMethodList(stream, 'tell');
      expect(pausedPosition, isA<double>());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final pausedAgain = await luaCallMethodList(stream, 'tell');
      expect(pausedAgain, closeTo((pausedPosition! as double), 0.01));

      await luaCallMethodList(stream, 'seek', const <Object?>[1.25]);
      expect(await luaCallMethodList(stream, 'tell'), closeTo(1.25, 0.0001));

      await luaCallMethodList(stream, 'rewind');
      expect(await luaCallMethodList(stream, 'tell'), closeTo(0.0, 0.0001));
    });

    test(
      'VideoStream:seek uses Lua bad-argument text for invalid offsets',
      () async {
        final runtime = Interpreter();
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

        final stream = await luaCallList(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/demo.ogv'],
        );

        await expectLater(
          () => luaCallMethodList(stream, 'seek', const <Object?>[false]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to 'seek' (number expected, got boolean)",
            ),
          ),
        );
      },
    );

    test('setSync shares and detaches timing state across streams', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/a.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
            'videos/b.ogv': _fakeTheoraOggBytes(width: 160, height: 90),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final leader = await luaCallList(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/a.ogv'],
      );
      final follower = await luaCallList(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/b.ogv'],
      );

      await luaCallMethodList(leader, 'play');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await luaCallMethodList(follower, 'setSync', <Object?>[leader]);

      final leaderTell = await luaCallMethodList(leader, 'tell');
      final followerTell = await luaCallMethodList(follower, 'tell');
      expect(followerTell, isA<double>());
      expect(followerTell! as double, closeTo((leaderTell! as double), 0.01));

      await luaCallMethodList(follower, 'pause');
      expect(await luaCallMethodList(leader, 'isPlaying'), isFalse);

      final detachedAt = await luaCallMethodList(follower, 'tell');
      await luaCallMethodList(follower, 'setSync');
      await luaCallMethodList(leader, 'seek', const <Object?>[5.0]);
      expect(
        await luaCallMethodList(follower, 'tell'),
        closeTo(detachedAt! as double, 0.01),
      );
    });

    test(
      'setSync accepts Source inputs and detaches back to independent timing',
      () async {
        final runtime = Interpreter();
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

        final stream = await luaCallList(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/demo.ogv'],
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
        await luaCallMethodList(stream, 'setSync', <Object?>[source]);

        expect(await luaCallMethodList(stream, 'tell'), closeTo(1.5, 0.0001));
        expect(await luaCallMethodList(stream, 'isPlaying'), isFalse);

        await luaCallMethodList(source, 'play');
        expect(await luaCallMethodList(stream, 'isPlaying'), isTrue);

        await luaCallMethodList(source, 'pause');
        expect(await luaCallMethodList(stream, 'isPlaying'), isFalse);

        final detachedAt = await luaCallMethodList(stream, 'tell');
        await luaCallMethodList(stream, 'setSync');
        await luaCallMethodList(source, 'seek', const <Object?>[3.0]);
        expect(
          await luaCallMethodList(stream, 'tell'),
          closeTo(detachedAt! as double, 0.0001),
        );
      },
    );

    test('setSync rejects unsupported sync targets', () async {
      final runtime = Interpreter();
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

      final stream = await luaCallList(
        runtime,
        const ['love', 'video', 'newVideoStream'],
        const <Object?>['videos/demo.ogv'],
      );

      await expectLater(
        () => luaCallMethodList(stream, 'setSync', const <Object?>[123]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            "bad argument #2 to 'setSync' "
                "(Source or VideoStream or nil expected, got number)",
          ),
        ),
      );
    });

    test('newVideoStream rejects non-Theora inputs', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/invalid.ogv': <int>[1, 2, 3, 4],
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      await expectLater(
        () => luaCallList(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/invalid.ogv'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('video is not theora'),
          ),
        ),
      );
    });

    test(
      'newVideoStream rejects FileData inputs to match the source wrapper',
      () async {
        final runtime = Interpreter();
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

        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['videos/demo.ogv'],
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'video', 'newVideoStream'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('expected filename or File at argument 1'),
            ),
          ),
        );
      },
    );

    test(
      'Theora metadata parsing keeps the encoded frame rate when present',
      () {
        final stream = LoveVideoStream.encoded(
          filename: 'videos/demo.ogv',
          bytes: _fakeTheoraOggBytes(
            width: 320,
            height: 180,
            frameRateNumerator: 30000,
            frameRateDenominator: 1001,
          ),
        );

        expect(stream.metadata, isNotNull);
        expect(stream.metadata!.pixelWidth, 320);
        expect(stream.metadata!.pixelHeight, 180);
        expect(stream.metadata!.frameRate, closeTo(30000 / 1001, 0.0001));
      },
    );

    test(
      'VideoStream release is idempotent and invalidates the wrapper',
      () async {
        final runtime = Interpreter();
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

        final stream = await luaCallList(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/demo.ogv'],
        );

        expect(await luaCallMethodList(stream, 'release'), isTrue);
        expect(await luaCallMethodList(stream, 'release'), isFalse);
        await expectLater(
          () => luaCallMethodList(stream, 'play'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );
        expect(await luaCallMethodList(stream, 'type'), 'VideoStream');
        expect(
          await luaCallMethodList(stream, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}

List<int> _fakeTheoraOggBytes({
  required int width,
  required int height,
  int? frameRateNumerator,
  int? frameRateDenominator,
}) {
  final includeFrameRate =
      frameRateNumerator != null && frameRateDenominator != null;
  final packet = Uint8List(includeFrameRate ? 30 : 22);
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
  if (includeFrameRate) {
    packet[22] = (frameRateNumerator >> 24) & 0xff;
    packet[23] = (frameRateNumerator >> 16) & 0xff;
    packet[24] = (frameRateNumerator >> 8) & 0xff;
    packet[25] = frameRateNumerator & 0xff;
    packet[26] = (frameRateDenominator >> 24) & 0xff;
    packet[27] = (frameRateDenominator >> 16) & 0xff;
    packet[28] = (frameRateDenominator >> 8) & 0xff;
    packet[29] = frameRateDenominator & 0xff;
  }

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
