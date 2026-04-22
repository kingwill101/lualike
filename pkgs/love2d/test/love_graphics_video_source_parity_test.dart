import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE graphics video source parity', () {
    test(
      'newVideo missing argument uses the normal argument-1 type error',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          () => luaCallList(runtime, const ['love', 'graphics', 'newVideo']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'love.graphics.newVideo expected filename, VideoStream, or File at argument 1',
              ),
            ),
          ),
        );
      },
    );

    test(
      '_newVideo mirrors the upstream low-level video constructor surface',
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
        final direct = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          <Object?>[stream],
        );
        final scaled = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          const <Object?>['videos/demo.ogv', 2.0],
        );

        expect(await luaCallMethodList(direct, 'type'), 'Video');
        expect(await luaCallMethodList(direct, 'getDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(await luaCallMethodList(direct, 'getSource'), isNull);
        expect(await luaCallMethodList(direct, 'getPixelDimensions'), <Object?>[
          320,
          180,
        ]);

        expect(await luaCallMethodList(scaled, 'getDimensions'), <Object?>[
          160,
          90,
        ]);
        expect(await luaCallMethodList(scaled, 'getPixelDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(await luaCallMethodList(scaled, 'getSource'), isNull);

        final explicitNilScale = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          <Object?>['videos/demo.ogv', null],
        );
        expect(
          await luaCallMethodList(explicitNilScale, 'getDimensions'),
          <Object?>[320, 180],
        );

        final zeroScale = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          <Object?>['videos/demo.ogv', 0.0],
        );
        expect(await luaCallMethodList(zeroScale, 'getDimensions'), <Object?>[
          320,
          180,
        ]);
        expect(
          await luaCallMethodList(zeroScale, 'getPixelDimensions'),
          <Object?>[320, 180],
        );

        final negativeScale = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          <Object?>['videos/demo.ogv', -2.0],
        );
        expect(
          await luaCallMethodList(negativeScale, 'getDimensions'),
          <Object?>[320, 180],
        );
        expect(
          await luaCallMethodList(negativeScale, 'getPixelDimensions'),
          <Object?>[320, 180],
        );
      },
    );

    test(
      'Video:_setSource matches the low-level wrapper by not changing stream sync',
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

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          const <Object?>['videos/demo.ogv'],
        );
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[88200, 22050, 16, 2],
        );
        final source = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'static'],
        );

        await luaCallMethodList(source, 'seek', const <Object?>[1.25]);
        await luaCallMethodList(video, '_setSource', <Object?>[source]);
        expect(await luaCallMethodList(video, 'getSource'), isNotNull);
        expect(await luaCallMethodList(video, 'tell'), closeTo(0.0, 0.0001));

        await luaCallMethodList(video, 'setSource', <Object?>[source]);
        expect(await luaCallMethodList(video, 'tell'), closeTo(1.25, 0.0001));

        await luaCallMethodList(video, '_setSource');
        expect(await luaCallMethodList(video, 'getSource'), isNull);
        await luaCallMethodList(source, 'seek', const <Object?>[1.75]);
        expect(await luaCallMethodList(video, 'tell'), closeTo(1.75, 0.0001));
      },
    );

    test(
      '_newVideo preserves the sync state of an input VideoStream',
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
          const <Object?>[88200, 22050, 16, 2],
        );
        final source = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'static'],
        );

        await luaCallMethodList(source, 'seek', const <Object?>[1.5]);
        await luaCallMethodList(stream, 'setSync', <Object?>[source]);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', '_newVideo'],
          <Object?>[stream],
        );

        expect(await luaCallMethodList(video, 'tell'), closeTo(1.5, 0.0001));
        await luaCallMethodList(source, 'seek', const <Object?>[3.0]);
        expect(await luaCallMethodList(video, 'tell'), closeTo(3.0, 0.0001));
        expect(await luaCallMethodList(stream, 'tell'), closeTo(3.0, 0.0001));
      },
    );

    test('Video source setters reject non-Source values', () async {
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

      final video = await luaCallList(
        runtime,
        const ['love', 'graphics', '_newVideo'],
        const <Object?>['videos/demo.ogv'],
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
    });

    test(
      '_newVideo reuses newVideoStream conversion errors for unsupported or missing inputs',
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
            const ['love', 'graphics', '_newVideo'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('expected filename, VideoStream, or File at argument 1'),
            ),
          ),
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', '_newVideo'],
            const <Object?>['videos/missing.ogv'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('File is not open and cannot be opened'),
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
