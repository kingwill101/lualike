import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.sound bindings', () {
    late LuaRuntime runtime;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime);
    });

    test(
      'newSoundData numeric constructor and sample access match LÖVE',
      () async {
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[3, 22050, 16, 2],
        );

        expect(await luaCallMethodList(soundData, 'type'), 'SoundData');
        expect(
          await luaCallMethodList(soundData, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(await luaCallMethodList(soundData, 'getSampleCount'), 3);
        expect(await luaCallMethodList(soundData, 'getSampleRate'), 22050);
        expect(await luaCallMethodList(soundData, 'getBitDepth'), 16);
        expect(await luaCallMethodList(soundData, 'getChannelCount'), 2);
        expect(
          await luaCallMethodList(soundData, 'getSample', const <Object?>[0]),
          0,
        );

        await luaCallMethodList(soundData, 'setSample', const <Object?>[
          1,
          2,
          -0.5,
        ]);
        expect(
          await luaCallMethodList(soundData, 'getSample', const <Object?>[
            1,
            2,
          ]),
          closeTo(-0.5, 0.0001),
        );

        final cloned = await luaCallMethodList(soundData, 'clone');
        expect(await luaCallMethodList(cloned, 'type'), 'SoundData');
        expect(
          await luaCallMethodList(cloned, 'getSample', const <Object?>[1, 2]),
          closeTo(-0.5, 0.0001),
        );
      },
    );

    test(
      'newSoundData numeric constructor surfaces raw validation errors',
      () async {
        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            const <Object?>[0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid sample count: 0',
            ),
          ),
        );
      },
    );

    test('8-bit SoundData uses unsigned byte sample conversion', () async {
      final soundData = await luaCallList(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[2, 11025, 8, 1],
      );

      expect(
        await luaCallList(
          runtime,
          const ['love', 'data', 'encode'],
          <Object?>['string', 'hex', soundData],
        ),
        '8080',
      );

      await luaCallMethodList(soundData, 'setSample', const <Object?>[0, -1.0]);
      await luaCallMethodList(soundData, 'setSample', const <Object?>[1, 1.0]);

      expect(
        await luaCallMethodList(soundData, 'getSample', const <Object?>[0]),
        closeTo(-1.0, 0.01),
      );
      expect(
        await luaCallMethodList(soundData, 'getSample', const <Object?>[1]),
        closeTo(1.0, 0.01),
      );
      expect(
        await luaCallList(
          runtime,
          const ['love', 'data', 'encode'],
          <Object?>['string', 'hex', soundData],
        ),
        '01ff',
      );
    });

    test(
      'newDecoder decodes chunked WAV PCM audio and supports clone/seek',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _pcm16StereoWave(
              sampleRate: 4,
              frames: const <List<int>>[
                <int>[0, 32767],
                <int>[-16384, 16384],
                <int>[8192, -8192],
              ],
            ),
            'fixture.wav',
          ],
        );

        final decoder = await luaCallList(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );

        expect(await luaCallMethodList(decoder, 'type'), 'Decoder');
        expect(
          await luaCallMethodList(decoder, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(await luaCallMethodList(decoder, 'getSampleRate'), 4);
        expect(await luaCallMethodList(decoder, 'getBitDepth'), 16);
        expect(await luaCallMethodList(decoder, 'getChannelCount'), 2);
        expect(
          await luaCallMethodList(decoder, 'getDuration'),
          closeTo(0.75, 0.0001),
        );

        final firstChunk = await luaCallMethodList(decoder, 'decode');
        expect(await luaCallMethodList(firstChunk, 'type'), 'SoundData');
        expect(await luaCallMethodList(firstChunk, 'getSampleCount'), 2);
        expect(
          await luaCallMethodList(firstChunk, 'getSample', const <Object?>[
            0,
            2,
          ]),
          closeTo(1.0, 0.0001),
        );
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', firstChunk],
          ),
          '0000ff7f00c00040',
        );

        final clone = await luaCallMethodList(decoder, 'clone');
        final clonedChunk = await luaCallMethodList(clone, 'decode');
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', clonedChunk],
          ),
          '0000ff7f00c00040',
        );

        await luaCallMethodList(decoder, 'seek', const <Object?>[0.5]);
        final tail = await luaCallMethodList(decoder, 'decode');
        expect(await luaCallMethodList(tail, 'getSampleCount'), 1);
        expect(
          await luaCallMethodList(tail, 'getSample', const <Object?>[0, 1]),
          closeTo(8192 / 32767.0, 0.0001),
        );
        expect(await luaCallMethodList(decoder, 'decode'), isNull);
      },
    );

    test(
      'newSoundData can drain decoders and resulting SoundData works as Data',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _pcm16StereoWave(
              sampleRate: 4,
              frames: const <List<int>>[
                <int>[0, 32767],
                <int>[-16384, 16384],
                <int>[8192, -8192],
              ],
            ),
            'fixture.wav',
          ],
        );

        final decoder = await luaCallList(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );
        await luaCallMethodList(decoder, 'seek', const <Object?>[0.25]);

        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          <Object?>[decoder],
        );

        expect(await luaCallMethodList(soundData, 'getSampleCount'), 2);
        expect(
          await luaCallList(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', soundData],
          ),
          '00c00040002000e0',
        );
        expect(
          await luaCallMethodList(soundData, 'getSample', const <Object?>[
            0,
            1,
          ]),
          closeTo(-16384 / 32767.0, 0.0001),
        );
      },
    );

    test(
      'newDecoder and newSoundData read mounted LOVE filesystem strings and reject missing filenames',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'sounds/theme.wav': _pcm16StereoWave(
                sampleRate: 4,
                frames: const <List<int>>[
                  <int>[0, 32767],
                  <int>[-16384, 16384],
                  <int>[8192, -8192],
                ],
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final decoder = await luaCallList(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          const <Object?>['sounds/theme.wav', 8],
        );
        expect(await luaCallMethodList(decoder, 'getSampleRate'), 4);
        expect(
          await luaCallMethodList(decoder, 'getDuration'),
          closeTo(0.75, 0.0001),
        );

        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>['sounds/theme.wav'],
        );
        expect(await luaCallMethodList(soundData, 'getSampleCount'), 3);
        expect(await luaCallMethodList(soundData, 'getSampleRate'), 4);

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            const <Object?>['sounds/missing.wav'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Could not open file sounds/missing.wav. Does not exist.',
              ),
            ),
          ),
        );
        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            const <Object?>['sounds/missing.wav'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Could not open file sounds/missing.wav. Does not exist.',
              ),
            ),
          ),
        );
      },
    );

    test(
      'newDecoder converts IEEE float WAV audio into 16-bit SoundData',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _float32StereoWave(
              sampleRate: 4,
              frames: const <List<double>>[
                <double>[0.0, 1.0],
                <double>[-0.5, 0.25],
              ],
            ),
            'fixture_float.wav',
          ],
        );

        final decoder = await luaCallList(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 16],
        );

        expect(await luaCallMethodList(decoder, 'getSampleRate'), 4);
        expect(await luaCallMethodList(decoder, 'getBitDepth'), 16);
        expect(await luaCallMethodList(decoder, 'getChannelCount'), 2);
        expect(
          await luaCallMethodList(decoder, 'getDuration'),
          closeTo(0.5, 0.0001),
        );

        final chunk = await luaCallMethodList(decoder, 'decode');
        expect(await luaCallMethodList(chunk, 'getSampleCount'), 2);
        expect(
          await luaCallMethodList(chunk, 'getSample', const <Object?>[0, 2]),
          closeTo(1.0, 0.0001),
        );
        expect(
          await luaCallMethodList(chunk, 'getSample', const <Object?>[1, 1]),
          closeTo(-0.5, 0.001),
        );
        expect(
          await luaCallMethodList(chunk, 'getSample', const <Object?>[1, 2]),
          closeTo(0.25, 0.001),
        );
      },
    );

    test(
      'newDecoder converts extensible 24-bit PCM WAV audio into 16-bit SoundData',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _extensiblePcm24MonoWave(
              sampleRate: 6,
              samples: const <int>[0, 8388607, -4194304],
            ),
            'fixture_extensible.wav',
          ],
        );

        final decoder = await luaCallList(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 12],
        );

        expect(await luaCallMethodList(decoder, 'getSampleRate'), 6);
        expect(await luaCallMethodList(decoder, 'getBitDepth'), 16);
        expect(await luaCallMethodList(decoder, 'getChannelCount'), 1);
        expect(
          await luaCallMethodList(decoder, 'getDuration'),
          closeTo(0.5, 0.0001),
        );

        final chunk = await luaCallMethodList(decoder, 'decode');
        expect(await luaCallMethodList(chunk, 'getSampleCount'), 3);
        expect(
          await luaCallMethodList(chunk, 'getSample', const <Object?>[0]),
          closeTo(0.0, 0.0001),
        );
        expect(
          await luaCallMethodList(chunk, 'getSample', const <Object?>[1]),
          closeTo(1.0, 0.0001),
        );
        expect(
          await luaCallMethodList(chunk, 'getSample', const <Object?>[2]),
          closeTo(-0.5, 0.001),
        );
      },
    );

    test(
      'unsupported sound containers report partial codec support clearly',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['not real audio', 'fixture.ogg'],
        );

        expect(
          luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Extension "ogg" not supported.'),
            ),
          ),
        );
      },
    );

    test(
      'decoder failures surface raw LOVE decode errors without binding prefixes',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['not a valid wave stream', 'broken.wav'],
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid WAV file.',
            ),
          ),
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid WAV file.',
            ),
          ),
        );
      },
    );

    test(
      'newDecoder and numeric newSoundData use Lua bad-argument text for numeric options',
      () async {
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _pcm16StereoWave(
              sampleRate: 4,
              frames: const <List<int>>[
                <int>[0, 32767],
                <int>[-16384, 16384],
              ],
            ),
            'fixture.wav',
          ],
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newDecoder'],
            <Object?>[fileData, false],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to 'newDecoder' (number expected, got boolean)",
            ),
          ),
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            const <Object?>[4, false],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #2 to 'newSoundData' (number expected, got boolean)",
            ),
          ),
        );
      },
    );

    test(
      'newDecoder and newSoundData use Lua bad-argument text for invalid arg 1',
      () async {
        await expectLater(
          () => luaCallList(runtime, const ['love', 'sound', 'newDecoder']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'newDecoder' "
                  '(filename, File, or FileData expected)',
            ),
          ),
        );

        await expectLater(
          () => luaCallList(runtime, const ['love', 'sound', 'newSoundData']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'newSoundData' "
                  '(filename, File, or FileData expected)',
            ),
          ),
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'sound', 'newSoundData'],
            const <Object?>[false],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'newSoundData' "
                  '(filename, File, or FileData expected)',
            ),
          ),
        );
      },
    );
  });
}

Uint8List _pcm16StereoWave({
  required int sampleRate,
  required List<List<int>> frames,
}) {
  final pcm = BytesBuilder(copy: false);
  for (final frame in frames) {
    expect(frame, hasLength(2));
    final sampleData = ByteData(4)
      ..setInt16(0, frame[0], Endian.little)
      ..setInt16(2, frame[1], Endian.little);
    pcm.add(sampleData.buffer.asUint8List());
  }

  final pcmBytes = pcm.toBytes();
  final buffer = BytesBuilder(copy: false);
  final fileSize = 36 + pcmBytes.length;
  final header = ByteData(44)
    ..setUint32(4, fileSize, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 4, Endian.little)
    ..setUint16(32, 4, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, pcmBytes.length, Endian.little);

  final bytes = header.buffer.asUint8List();
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bytes.setRange(36, 40, 'data'.codeUnits);
  buffer.add(bytes);
  buffer.add(pcmBytes);
  return buffer.toBytes();
}

Uint8List _float32StereoWave({
  required int sampleRate,
  required List<List<double>> frames,
}) {
  final pcm = BytesBuilder(copy: false);
  for (final frame in frames) {
    expect(frame, hasLength(2));
    final sampleData = ByteData(8)
      ..setFloat32(0, frame[0], Endian.little)
      ..setFloat32(4, frame[1], Endian.little);
    pcm.add(sampleData.buffer.asUint8List());
  }

  final pcmBytes = pcm.toBytes();
  final header = ByteData(44)
    ..setUint32(4, 36 + pcmBytes.length, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 3, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 8, Endian.little)
    ..setUint16(32, 8, Endian.little)
    ..setUint16(34, 32, Endian.little)
    ..setUint32(40, pcmBytes.length, Endian.little);

  final bytes = header.buffer.asUint8List();
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bytes.setRange(36, 40, 'data'.codeUnits);

  final buffer = BytesBuilder(copy: false)
    ..add(bytes)
    ..add(pcmBytes);
  return buffer.toBytes();
}

Uint8List _extensiblePcm24MonoWave({
  required int sampleRate,
  required List<int> samples,
}) {
  final pcm = BytesBuilder(copy: false);
  for (final sample in samples) {
    final clamped = sample.clamp(-8388608, 8388607);
    pcm.add(<int>[
      clamped & 0xFF,
      (clamped >> 8) & 0xFF,
      (clamped >> 16) & 0xFF,
    ]);
  }

  final pcmBytes = pcm.toBytes();
  final header = ByteData(68)
    ..setUint32(4, 60 + pcmBytes.length, Endian.little)
    ..setUint32(16, 40, Endian.little)
    ..setUint16(20, 0xFFFE, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 3, Endian.little)
    ..setUint16(32, 3, Endian.little)
    ..setUint16(34, 24, Endian.little)
    ..setUint16(36, 22, Endian.little)
    ..setUint16(38, 24, Endian.little)
    ..setUint32(40, 0, Endian.little)
    ..setUint16(44, 1, Endian.little)
    ..setUint16(46, 0, Endian.little)
    ..setUint16(48, 0, Endian.little)
    ..setUint16(50, 0x0010, Endian.little)
    ..setUint8(52, 0x80)
    ..setUint8(53, 0x00)
    ..setUint8(54, 0x00)
    ..setUint8(55, 0xAA)
    ..setUint8(56, 0x00)
    ..setUint8(57, 0x38)
    ..setUint8(58, 0x9B)
    ..setUint8(59, 0x71)
    ..setUint32(64, pcmBytes.length, Endian.little);

  final bytes = header.buffer.asUint8List();
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bytes.setRange(60, 64, 'data'.codeUnits);

  final buffer = BytesBuilder(copy: false)
    ..add(bytes)
    ..add(pcmBytes);
  return buffer.toBytes();
}
