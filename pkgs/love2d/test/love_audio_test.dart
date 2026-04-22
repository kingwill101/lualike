import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.audio bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('listener state and module queries follow LÖVE defaults', () async {
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getPosition']),
        <Object?>[0.0, 0.0, 0.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getVelocity']),
        <Object?>[0.0, 0.0, 0.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getOrientation']),
        <Object?>[0.0, 0.0, -1.0, 0.0, 1.0, 0.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getDistanceModel']),
        'inverseclamped',
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getDopplerScale']),
        1.0,
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getVolume']),
        1.0,
      );
      expect(
        await luaCallList(runtime, const [
          'love',
          'audio',
          'getActiveSourceCount',
        ]),
        0,
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getActiveEffects']),
        isEmpty,
      );
      expect(
        await luaCallList(runtime, const [
          'love',
          'audio',
          'getRecordingDevices',
        ]),
        isEmpty,
      );
      expect(
        await luaCallList(runtime, const [
          'love',
          'audio',
          'getMaxSceneEffects',
        ]),
        64,
      );
      expect(
        await luaCallList(runtime, const [
          'love',
          'audio',
          'getMaxSourceEffects',
        ]),
        64,
      );
      expect(
        await luaCallList(runtime, const [
          'love',
          'audio',
          'isEffectsSupported',
        ]),
        isTrue,
      );

      await luaCallList(
        runtime,
        const ['love', 'audio', 'setPosition'],
        const <Object?>[4.0, 5.0],
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setVelocity'],
        const <Object?>[6.0, 7.0, 8.0],
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setOrientation'],
        const <Object?>[1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setDopplerScale'],
        const <Object?>[2.5],
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setDistanceModel'],
        const <Object?>['linear'],
      );
      expect(
        await luaCallList(
          runtime,
          const ['love', 'audio', 'setMixWithSystem'],
          const <Object?>[true],
        ),
        isTrue,
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setVolume'],
        const <Object?>[0.4],
      );

      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getPosition']),
        <Object?>[4.0, 5.0, 0.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getVelocity']),
        <Object?>[6.0, 7.0, 8.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getOrientation']),
        <Object?>[1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getDopplerScale']),
        2.5,
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setDopplerScale'],
        const <Object?>[-1.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getDopplerScale']),
        2.5,
      );
      await luaCallList(
        runtime,
        const ['love', 'audio', 'setDopplerScale'],
        const <Object?>[0.0],
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getDopplerScale']),
        0.0,
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getDistanceModel']),
        'linear',
      );
      expect(
        await luaCallList(runtime, const ['love', 'audio', 'getVolume']),
        0.4,
      );
    });

    test('setMixWithSystem returns the host result', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(
          audioMixWithSystemHandler: (mix) async => mix == false,
        ),
      );

      expect(
        await luaCallList(
          runtime,
          const ['love', 'audio', 'setMixWithSystem'],
          const <Object?>[true],
        ),
        isFalse,
      );
      expect(LoveRuntimeContext.of(runtime).audio.mixWithSystem, isTrue);

      expect(
        await luaCallList(
          runtime,
          const ['love', 'audio', 'setMixWithSystem'],
          const <Object?>[false],
        ),
        isTrue,
      );
      expect(LoveRuntimeContext.of(runtime).audio.mixWithSystem, isFalse);
    });

    test('audio enum validation uses LOVE enum error text', () async {
      final soundData = await luaCallList(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[8, 22050, 16, 2],
      );
      final source = await luaCallList(
        runtime,
        const ['love', 'audio', 'newSource'],
        <Object?>[soundData, 'stream'],
      );

      expect(
        luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'bogus'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              "Invalid source type 'bogus', expected one of: 'static', 'stream', 'queue'",
            ),
          ),
        ),
      );

      expect(
        luaCallMethodList(source, 'tell', const <Object?>['bogus']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              "Invalid time unit 'bogus', expected one of: 'seconds', 'samples'",
            ),
          ),
        ),
      );

      expect(
        luaCallList(
          runtime,
          const ['love', 'audio', 'setDistanceModel'],
          const <Object?>['bogus'],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains(
              "Invalid distance model 'bogus', expected one of: 'none', 'inverse', 'inverseclamped', 'linear', 'linearclamped', 'exponent', 'exponentclamped'",
            ),
          ),
        ),
      );
    });

    test('Source state, clone, and time units mirror LÖVE behavior', () async {
      final soundData = await luaCallList(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[8, 22050, 16, 2],
      );

      final source = await luaCallList(
        runtime,
        const ['love', 'audio', 'newSource'],
        <Object?>[soundData, 'stream'],
      );

      expect(await luaCallMethodList(source, 'type'), 'Source');
      expect(await luaCallMethodList(source, 'getType'), 'static');
      expect(
        await luaCallMethodList(source, 'getDuration'),
        closeTo(8 / 22050, 1e-12),
      );
      expect(
        await luaCallMethodList(source, 'getDuration', const <Object?>[
          'samples',
        ]),
        closeTo(8.0, 1e-12),
      );
      expect(await luaCallMethodList(source, 'getChannelCount'), 2);
      expect(await luaCallMethodList(source, 'getFreeBufferCount'), 0);
      expect(await luaCallMethodList(source, 'getActiveEffects'), isEmpty);

      await luaCallMethodList(source, 'setDirection', const <Object?>[
        1.0,
        2.0,
      ]);
      await luaCallMethodList(source, 'setPosition', const <Object?>[3.0, 4.0]);
      await luaCallMethodList(source, 'setVelocity', const <Object?>[
        5.0,
        6.0,
        7.0,
      ]);
      await luaCallMethodList(source, 'setCone', const <Object?>[
        0.25,
        0.5,
        0.75,
        0.9,
      ]);
      await luaCallMethodList(
        source,
        'setAttenuationDistances',
        const <Object?>[2.0, 20.0],
      );
      await luaCallMethodList(source, 'setVolumeLimits', const <Object?>[
        0.2,
        0.9,
      ]);
      await luaCallMethodList(source, 'setAirAbsorption', const <Object?>[0.1]);
      await luaCallMethodList(source, 'setRolloff', const <Object?>[0.5]);
      await luaCallMethodList(source, 'setPitch', const <Object?>[1.25]);
      await luaCallMethodList(source, 'seek', const <Object?>[4.0, 'samples']);

      expect(await luaCallMethodList(source, 'getDirection'), <Object?>[
        1.0,
        2.0,
        0.0,
      ]);
      expect(await luaCallMethodList(source, 'getPosition'), <Object?>[
        3.0,
        4.0,
        0.0,
      ]);
      expect(await luaCallMethodList(source, 'getVelocity'), <Object?>[
        5.0,
        6.0,
        7.0,
      ]);
      expect(await luaCallMethodList(source, 'getCone'), <Object?>[
        0.25,
        0.5,
        0.75,
        0.9,
      ]);
      expect(
        await luaCallMethodList(source, 'getAttenuationDistances'),
        <Object?>[2.0, 20.0],
      );
      expect(await luaCallMethodList(source, 'getVolumeLimits'), <Object?>[
        0.2,
        0.9,
      ]);
      expect(await luaCallMethodList(source, 'getAirAbsorption'), 0.1);
      expect(await luaCallMethodList(source, 'getRolloff'), 0.5);
      expect(await luaCallMethodList(source, 'getPitch'), 1.25);
      expect(
        await luaCallMethodList(source, 'tell', const <Object?>['samples']),
        closeTo(4.0, 1e-12),
      );
      expect(
        await luaCallMethodList(source, 'tell'),
        closeTo(4 / 22050, 1e-12),
      );

      final clone = await luaCallMethodList(source, 'clone');
      expect(await luaCallMethodList(clone, 'getType'), 'static');
      expect(await luaCallMethodList(clone, 'isPlaying'), isFalse);
      expect(
        await luaCallMethodList(clone, 'tell', const <Object?>['samples']),
        closeTo(0.0, 1e-12),
      );
      expect(await luaCallMethodList(clone, 'getDirection'), <Object?>[
        1.0,
        2.0,
        0.0,
      ]);
      expect(await luaCallMethodList(clone, 'getCone'), <Object?>[
        0.25,
        0.5,
        0.75,
        0.9,
      ]);
      expect(
        await luaCallMethodList(clone, 'getAttenuationDistances'),
        <Object?>[2.0, 20.0],
      );
      expect(await luaCallMethodList(clone, 'getVolumeLimits'), <Object?>[
        0.2,
        0.9,
      ]);

      expect(
        luaCallMethodList(source, 'seek', const <Object?>[-1.0]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("can't seek to a negative position"),
          ),
        ),
      );
      expect(
        luaCallMethodList(source, 'setPitch', <Object?>[double.nan]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Pitch cannot be NaN.'),
          ),
        ),
      );
      expect(
        luaCallMethodList(source, 'setPitch', <Object?>[0.0]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Pitch has to be non-zero, positive, finite number.'),
          ),
        ),
      );
      expect(
        luaCallMethodList(source, 'setPitch', <Object?>[double.infinity]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Pitch has to be non-zero, positive, finite number.'),
          ),
        ),
      );
    });

    test(
      'newSource uses the upstream bad-argument path for invalid argument 1 values',
      () async {
        expect(
          luaCallList(runtime, const ['love', 'audio', 'newSource']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'newSource' "
                  "(filename, File, FileData, Decoder, or SoundData expected, got nil)",
            ),
          ),
        );

        expect(
          luaCallList(
            runtime,
            const ['love', 'audio', 'newSource'],
            const <Object?>[123],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'newSource' "
                  "(filename, File, FileData, Decoder, or SoundData expected, got number)",
            ),
          ),
        );
      },
    );

    test(
      'newSource accepts Decoder and file inputs and transport works',
      () async {
        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[1024, 22050, 16, 1],
        );
        final fileData = await luaCallList(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[
            _pcm16StereoWave(
              sampleRate: 4,
              frames: const <List<int>>[
                <int>[0, 0],
                <int>[8192, -8192],
                <int>[16384, -16384],
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

        final sourceFromData = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'stream'],
        );
        final sourceFromDecoder = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[decoder],
        );
        final sourceFromFile = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[fileData, 'stream'],
        );

        expect(await luaCallMethodList(sourceFromData, 'getType'), 'static');
        expect(await luaCallMethodList(sourceFromDecoder, 'getType'), 'stream');
        expect(await luaCallMethodList(sourceFromFile, 'getType'), 'stream');
        expect(
          await luaCallMethodList(sourceFromDecoder, 'getDuration'),
          closeTo(0.75, 1e-12),
        );
        expect(
          await luaCallMethodList(sourceFromFile, 'getDuration'),
          closeTo(0.75, 1e-12),
        );
        expect(
          await luaCallMethodList(
            sourceFromFile,
            'getDuration',
            const <Object?>['samples'],
          ),
          3.0,
        );

        expect(
          await luaCallList(
            runtime,
            const ['love', 'audio', 'play'],
            <Object?>[sourceFromData, sourceFromDecoder],
          ),
          isTrue,
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          2,
        );

        final paused = await luaCallList(runtime, const [
          'love',
          'audio',
          'pause',
        ]);
        expect(paused, isA<Map>().having((table) => table.length, 'length', 2));
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          0,
        );

        expect(
          luaCallList(
            runtime,
            const ['love', 'audio', 'newSource'],
            <Object?>[fileData, 'queue'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot create queueable sources using newSource. '
                  'Use newQueueableSource instead.',
            ),
          ),
        );
      },
    );

    test(
      'newSource reads mounted LOVE filesystem strings and rejects missing filenames',
      () async {
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'sounds/theme.wav': _pcm16StereoWave(
                sampleRate: 4,
                frames: const <List<int>>[
                  <int>[0, 0],
                  <int>[8192, -8192],
                  <int>[16384, -16384],
                ],
              ),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final source = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          const <Object?>['sounds/theme.wav', 'stream'],
        );
        expect(await luaCallMethodList(source, 'getType'), 'stream');
        expect(await luaCallMethodList(source, 'play'), isTrue);
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          1,
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'audio', 'newSource'],
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
      'newQueueableSource tracks queued buffers and validates format',
      () async {
        final queue = await luaCallList(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 2],
        );
        final matching = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 2],
        );
        final mismatch = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 44100, 16, 2],
        );

        expect(await luaCallMethodList(queue, 'getType'), 'queue');
        expect(await luaCallMethodList(queue, 'getFreeBufferCount'), 8);
        expect(await luaCallMethodList(queue, 'getDuration'), 0.0);
        expect(
          await luaCallMethodList(queue, 'getDuration', const <Object?>[
            'samples',
          ]),
          0.0,
        );
        expect(await luaCallMethodList(queue, 'play'), isFalse);
        expect(
          await luaCallList(
            runtime,
            const ['love', 'audio', 'play'],
            <Object?>[queue],
          ),
          isFalse,
        );

        expect(
          await luaCallMethodList(queue, 'queue', <Object?>[matching]),
          isTrue,
        );
        expect(await luaCallMethodList(queue, 'getFreeBufferCount'), 7);
        expect(
          await luaCallMethodList(queue, 'getDuration', const <Object?>[
            'samples',
          ]),
          4.0,
        );
        expect(
          await luaCallMethodList(queue, 'getDuration'),
          closeTo(4 / 22050, 1e-12),
        );

        expect(
          await luaCallMethodList(queue, 'queue', <Object?>[matching, 8]),
          isTrue,
        );
        expect(await luaCallMethodList(queue, 'getFreeBufferCount'), 6);
        expect(
          await luaCallMethodList(queue, 'getDuration', const <Object?>[
            'samples',
          ]),
          6.0,
        );

        final clone = await luaCallMethodList(queue, 'clone');
        expect(await luaCallMethodList(clone, 'getType'), 'queue');
        expect(await luaCallMethodList(clone, 'getFreeBufferCount'), 8);
        expect(await luaCallMethodList(clone, 'getDuration'), 0.0);

        expect(
          luaCallMethodList(queue, 'setLooping', const <Object?>[true]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Queueable Sources can not be looped.'),
            ),
          ),
        );
        expect(
          luaCallMethodList(queue, 'queue', <Object?>[mismatch]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Queued sound data must have same format as sound Source.',
              ),
            ),
          ),
        );
        expect(
          luaCallMethodList(queue, 'queue', <Object?>[matching, 3]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('multiple of sample size'),
            ),
          ),
        );

        await luaCallMethodList(queue, 'stop');
        expect(await luaCallMethodList(queue, 'getFreeBufferCount'), 8);
        expect(await luaCallMethodList(queue, 'getDuration'), 0.0);
      },
    );

    test(
      'newQueueableSource matches LOVE constructor acceptance and format errors',
      () async {
        final zeroRateQueue = await luaCallList(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[0, 16, 1],
        );
        expect(await luaCallMethodList(zeroRateQueue, 'getType'), 'queue');
        expect(await luaCallMethodList(zeroRateQueue, 'getFreeBufferCount'), 8);

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'audio', 'newQueueableSource'],
            const <Object?>[22050, 24, 1],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                '1-channel Sources with 24 bits per sample are not supported.',
              ),
            ),
          ),
        );

        await expectLater(
          () => luaCallList(
            runtime,
            const ['love', 'audio', 'newQueueableSource'],
            const <Object?>[22050, 16, 3],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                '3-channel Sources with 16 bits per sample are not supported.',
              ),
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
