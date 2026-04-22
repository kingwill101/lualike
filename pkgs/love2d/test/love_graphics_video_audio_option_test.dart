import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics newVideo audio semantics', () {
    test(
      'Theora-only videos leave source nil by default and explicit audio=true errors',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/no_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/no_audio.ogv'],
        );
        expect(await luaCallMethodList(video, 'getSource'), isNull);

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'newVideo'],
            const <Object?>[
              'videos/no_audio.ogv',
              <Object?, Object?>{'audio': true},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Video had no audio track'),
            ),
          ),
        );
      },
    );

    test(
      'non-boolean truthy audio flags attempt audio without requiring success',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/no_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/no_audio.ogv',
            <Object?, Object?>{'audio': 1},
          ],
        );

        expect(await luaCallMethodList(video, 'getSource'), isNull);
      },
    );

    test(
      'array-style settings tables ignore indexed truthy values like the vendored sample',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/no_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>[
            'videos/no_audio.ogv',
            <Object?, Object?>{1: true},
          ],
        );

        expect(await luaCallMethodList(video, 'getSource'), isNull);
      },
    );

    test(
      'newVideo detaches an input VideoStream when audio wiring is disabled',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/no_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final stream = await luaCallList(
          runtime,
          const ['love', 'video', 'newVideoStream'],
          const <Object?>['videos/no_audio.ogv'],
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

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          <Object?>[
            stream,
            <Object?, Object?>{'audio': false},
          ],
        );

        final detachedAt = await luaCallMethodList(video, 'tell');
        final detachedSeconds = detachedAt! as double;
        expect(await luaCallMethodList(video, 'getSource'), isNull);
        await luaCallMethodList(source, 'seek', const <Object?>[4.0]);
        expect(
          await luaCallMethodList(video, 'tell'),
          closeTo(detachedSeconds, 0.0001),
        );
        expect(
          await luaCallMethodList(stream, 'tell'),
          closeTo(detachedSeconds, 0.0001),
        );
      },
    );

    test(
      'default newVideo attaches a Source when the Ogg stream advertises Vorbis audio',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/with_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
                includeVorbisAudio: true,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/with_audio.ogv'],
        );
        final source = await luaCallMethodList(video, 'getSource');
        expect(source, isNotNull);
        expect(await luaCallMethodList(source, 'type'), 'Source');

        await luaCallMethodList(source, 'seek', const <Object?>[1.25]);
        expect(await luaCallMethodList(video, 'tell'), closeTo(1.25, 0.0001));
      },
    );

    test(
      'newVideo respects whether love.audio is loaded before wiring audio',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/with_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
                includeVorbisAudio: true,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final love = runtime.getCurrentEnv().get('love');
        expect(love, isA<Value>());
        final loveTable = (love! as Value).raw as Map<dynamic, dynamic>;
        loveTable.remove('audio');

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/with_audio.ogv'],
        );
        expect(await luaCallMethodList(video, 'getSource'), isNull);

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'newVideo'],
            const <Object?>[
              'videos/with_audio.ogv',
              <Object?, Object?>{'audio': true},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('love.audio was not loaded'),
            ),
          ),
        );
      },
    );

    test(
      'default newVideo detaches when audio backend setup throws a non-Exception error',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            audioBackendFactory:
                (source, {required sourceType, bytes, mimeType}) async {
                  throw UnsupportedError(
                    'simulated backend failure for $source',
                  );
                },
          ),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/with_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
                includeVorbisAudio: true,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/with_audio.ogv'],
        );

        expect(await luaCallMethodList(video, 'getSource'), isNull);
      },
    );

    test(
      'explicit audio=true wraps non-Exception backend failures as missing audio',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            audioBackendFactory:
                (source, {required sourceType, bytes, mimeType}) async {
                  throw UnsupportedError(
                    'simulated backend failure for $source',
                  );
                },
          ),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/with_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
                includeVorbisAudio: true,
              ),
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
              'videos/with_audio.ogv',
              <Object?, Object?>{'audio': true},
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Video had no audio track'),
            ),
          ),
        );
      },
    );

    test(
      'Video release stops the attached Source like the upstream destructor',
      () async {
        final backends = <_RecordingAudioBackend>[];
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(
            audioBackendFactory:
                (source, {required sourceType, bytes, mimeType}) async {
                  final backend = _RecordingAudioBackend();
                  backends.add(backend);
                  return backend;
                },
          ),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/with_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
                includeVorbisAudio: true,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final video = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          const <Object?>['videos/with_audio.ogv'],
        );
        final source = await luaCallMethodList(video, 'getSource');

        expect(source, isNotNull);
        expect(backends, hasLength(1));

        await luaCallMethodList(source, 'seek', const <Object?>[1.25]);
        expect(await luaCallMethodList(source, 'tell'), closeTo(1.25, 0.0001));

        expect(await luaCallMethodList(video, 'release'), isTrue);
        expect(await luaCallMethodList(video, 'release'), isFalse);

        expect(backends.single.stopCalls, 1);
        expect(await luaCallMethodList(source, 'isPlaying'), isFalse);
        expect(await luaCallMethodList(source, 'tell'), closeTo(0.0, 0.0001));
      },
    );

    test('newVideo accepts File inputs and rejects FileData inputs', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'videos/no_audio.ogv': _fakeTheoraOggBytes(width: 320, height: 180),
          }),
        ),
      );
      final filesystem = LoveFilesystemState.of(runtime);
      expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

      final file = await luaCallList(
        runtime,
        const ['love', 'filesystem', 'newFile'],
        const <Object?>['videos/no_audio.ogv'],
      );
      final fileData = await luaCallList(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        const <Object?>['videos/no_audio.ogv'],
      );

      final fromFile = await luaCallList(
        runtime,
        const ['love', 'graphics', 'newVideo'],
        <Object?>[
          file,
          <Object?, Object?>{'audio': false},
        ],
      );
      expect(await luaCallMethodList(fromFile, 'getDimensions'), <Object?>[
        320,
        180,
      ]);

      await expectLater(
        () => luaCallList(
          runtime,
          const ['love', 'graphics', 'newVideo'],
          <Object?>[
            fileData,
            <Object?, Object?>{'audio': false},
          ],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('expected filename, VideoStream, or File at argument 1'),
          ),
        ),
      );
    });

    test(
      'boolean second argument is rejected like the upstream wrapper',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'videos/no_audio.ogv': _fakeTheoraOggBytes(
                width: 320,
                height: 180,
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'graphics', 'newVideo'],
            const <Object?>['videos/no_audio.ogv', false],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('bad argument #2 to newVideo (expected table)'),
            ),
          ),
        );
      },
    );
  });
}

List<int> _fakeTheoraOggBytes({
  required int width,
  required int height,
  bool includeVorbisAudio = false,
}) {
  final bytes = <int>[
    ..._fakeOggPage(
      serial: 1,
      sequence: 0,
      packet: _fakeTheoraIdentificationPacket(width: width, height: height),
    ),
  ];

  if (includeVorbisAudio) {
    bytes.addAll(
      _fakeOggPage(
        serial: 2,
        sequence: 0,
        packet: _fakeVorbisIdentificationPacket(),
      ),
    );
  }

  return bytes;
}

List<int> _fakeOggPage({
  required int serial,
  required int sequence,
  required List<int> packet,
  bool beginningOfStream = true,
}) {
  if (packet.length > 255) {
    throw ArgumentError('Test packet too large for a single-page Ogg helper');
  }

  return <int>[
    ...'OggS'.codeUnits,
    0x00,
    beginningOfStream ? 0x02 : 0x00,
    ...List<int>.filled(8, 0),
    serial & 0xff,
    (serial >> 8) & 0xff,
    (serial >> 16) & 0xff,
    (serial >> 24) & 0xff,
    sequence & 0xff,
    (sequence >> 8) & 0xff,
    (sequence >> 16) & 0xff,
    (sequence >> 24) & 0xff,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    packet.length,
    ...packet,
  ];
}

List<int> _fakeTheoraIdentificationPacket({
  required int width,
  required int height,
}) {
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
  return packet;
}

List<int> _fakeVorbisIdentificationPacket() {
  final packet = Uint8List(30);
  packet[0] = 0x01;
  const signature = 'vorbis';
  for (var index = 0; index < signature.length; index++) {
    packet[index + 1] = signature.codeUnitAt(index);
  }
  return packet;
}

final class _RecordingAudioBackend implements LoveAudioSourceBackend {
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<Duration> seekOffsets = <Duration>[];

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekOffsets.add(position);
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
