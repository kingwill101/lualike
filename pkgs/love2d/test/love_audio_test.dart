import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.audio bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());
    });

    test('listener state and module queries follow LÖVE defaults', () async {
      expect(
        await _call(runtime, const ['love', 'audio', 'getPosition']),
        <Object?>[0.0, 0.0, 0.0],
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getVelocity']),
        <Object?>[0.0, 0.0, 0.0],
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getOrientation']),
        <Object?>[0.0, 0.0, -1.0, 0.0, 1.0, 0.0],
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getDistanceModel']),
        'inverseclamped',
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getDopplerScale']),
        1.0,
      );
      expect(await _call(runtime, const ['love', 'audio', 'getVolume']), 1.0);
      expect(
        await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
        0,
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getActiveEffects']),
        isEmpty,
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getRecordingDevices']),
        isEmpty,
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getMaxSceneEffects']),
        64,
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getMaxSourceEffects']),
        64,
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'isEffectsSupported']),
        isTrue,
      );

      await _call(
        runtime,
        const ['love', 'audio', 'setPosition'],
        const <Object?>[4.0, 5.0],
      );
      await _call(
        runtime,
        const ['love', 'audio', 'setVelocity'],
        const <Object?>[6.0, 7.0, 8.0],
      );
      await _call(
        runtime,
        const ['love', 'audio', 'setOrientation'],
        const <Object?>[1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      );
      await _call(
        runtime,
        const ['love', 'audio', 'setDopplerScale'],
        const <Object?>[2.5],
      );
      await _call(
        runtime,
        const ['love', 'audio', 'setDistanceModel'],
        const <Object?>['linear'],
      );
      await _call(
        runtime,
        const ['love', 'audio', 'setMixWithSystem'],
        const <Object?>[true],
      );
      await _call(
        runtime,
        const ['love', 'audio', 'setVolume'],
        const <Object?>[0.4],
      );

      expect(
        await _call(runtime, const ['love', 'audio', 'getPosition']),
        <Object?>[4.0, 5.0, 0.0],
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getVelocity']),
        <Object?>[6.0, 7.0, 8.0],
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getOrientation']),
        <Object?>[1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getDopplerScale']),
        2.5,
      );
      expect(
        await _call(runtime, const ['love', 'audio', 'getDistanceModel']),
        'linear',
      );
      expect(await _call(runtime, const ['love', 'audio', 'getVolume']), 0.4);
    });

    test('Source state, clone, and time units mirror LÖVE behavior', () async {
      final soundData = await _call(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[8, 22050, 16, 2],
      );

      final source = await _call(
        runtime,
        const ['love', 'audio', 'newSource'],
        <Object?>[soundData, 'stream'],
      );

      expect(await _callMethod(source, 'type'), 'Source');
      expect(await _callMethod(source, 'getType'), 'static');
      expect(
        await _callMethod(source, 'getDuration'),
        closeTo(8 / 22050, 1e-12),
      );
      expect(
        await _callMethod(source, 'getDuration', const <Object?>['samples']),
        closeTo(8.0, 1e-12),
      );
      expect(await _callMethod(source, 'getChannelCount'), 2);
      expect(await _callMethod(source, 'getFreeBufferCount'), 0);
      expect(await _callMethod(source, 'getActiveEffects'), isEmpty);

      await _callMethod(source, 'setDirection', const <Object?>[1.0, 2.0]);
      await _callMethod(source, 'setPosition', const <Object?>[3.0, 4.0]);
      await _callMethod(source, 'setVelocity', const <Object?>[5.0, 6.0, 7.0]);
      await _callMethod(source, 'setCone', const <Object?>[
        0.25,
        0.5,
        0.75,
        0.9,
      ]);
      await _callMethod(source, 'setAttenuationDistances', const <Object?>[
        2.0,
        20.0,
      ]);
      await _callMethod(source, 'setVolumeLimits', const <Object?>[0.2, 0.9]);
      await _callMethod(source, 'setAirAbsorption', const <Object?>[0.1]);
      await _callMethod(source, 'setRolloff', const <Object?>[0.5]);
      await _callMethod(source, 'setPitch', const <Object?>[1.25]);
      await _callMethod(source, 'seek', const <Object?>[4.0, 'samples']);

      expect(await _callMethod(source, 'getDirection'), <Object?>[
        1.0,
        2.0,
        0.0,
      ]);
      expect(await _callMethod(source, 'getPosition'), <Object?>[
        3.0,
        4.0,
        0.0,
      ]);
      expect(await _callMethod(source, 'getVelocity'), <Object?>[
        5.0,
        6.0,
        7.0,
      ]);
      expect(await _callMethod(source, 'getCone'), <Object?>[
        0.25,
        0.5,
        0.75,
        0.9,
      ]);
      expect(await _callMethod(source, 'getAttenuationDistances'), <Object?>[
        2.0,
        20.0,
      ]);
      expect(await _callMethod(source, 'getVolumeLimits'), <Object?>[0.2, 0.9]);
      expect(await _callMethod(source, 'getAirAbsorption'), 0.1);
      expect(await _callMethod(source, 'getRolloff'), 0.5);
      expect(await _callMethod(source, 'getPitch'), 1.25);
      expect(
        await _callMethod(source, 'tell', const <Object?>['samples']),
        closeTo(4.0, 1e-12),
      );
      expect(await _callMethod(source, 'tell'), closeTo(4 / 22050, 1e-12));

      final clone = await _callMethod(source, 'clone');
      expect(await _callMethod(clone, 'getType'), 'static');
      expect(await _callMethod(clone, 'isPlaying'), isFalse);
      expect(
        await _callMethod(clone, 'tell', const <Object?>['samples']),
        closeTo(0.0, 1e-12),
      );
      expect(await _callMethod(clone, 'getDirection'), <Object?>[
        1.0,
        2.0,
        0.0,
      ]);
      expect(await _callMethod(clone, 'getCone'), <Object?>[
        0.25,
        0.5,
        0.75,
        0.9,
      ]);
      expect(await _callMethod(clone, 'getAttenuationDistances'), <Object?>[
        2.0,
        20.0,
      ]);
      expect(await _callMethod(clone, 'getVolumeLimits'), <Object?>[0.2, 0.9]);

      expect(
        _callMethod(source, 'seek', const <Object?>[-1.0]),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("can't seek to a negative position"),
          ),
        ),
      );
    });

    test(
      'newSource accepts Decoder and file inputs and transport works',
      () async {
        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 1],
        );
        final fileData = await _call(
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
        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );

        final sourceFromData = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'stream'],
        );
        final sourceFromDecoder = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[decoder],
        );
        final sourceFromFile = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[fileData, 'stream'],
        );

        expect(await _callMethod(sourceFromData, 'getType'), 'static');
        expect(await _callMethod(sourceFromDecoder, 'getType'), 'stream');
        expect(await _callMethod(sourceFromFile, 'getType'), 'stream');
        expect(
          await _callMethod(sourceFromDecoder, 'getDuration'),
          closeTo(0.75, 1e-12),
        );
        expect(await _callMethod(sourceFromFile, 'getDuration'), -1.0);

        expect(
          await _call(
            runtime,
            const ['love', 'audio', 'play'],
            <Object?>[sourceFromData, sourceFromDecoder],
          ),
          isTrue,
        );
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
          2,
        );

        final paused = await _call(runtime, const ['love', 'audio', 'pause']);
        expect(paused, isA<Map>().having((table) => table.length, 'length', 2));
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
          0,
        );

        expect(
          _call(
            runtime,
            const ['love', 'audio', 'newSource'],
            <Object?>[fileData, 'queue'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('newQueueableSource'),
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

        final source = await _call(
          runtime,
          const ['love', 'audio', 'newSource'],
          const <Object?>['sounds/theme.wav', 'stream'],
        );
        expect(await _callMethod(source, 'getType'), 'stream');
        expect(await _callMethod(source, 'play'), isTrue);
        expect(
          await _call(runtime, const ['love', 'audio', 'getActiveSourceCount']),
          1,
        );

        await expectLater(
          () => _call(
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
        final queue = await _call(
          runtime,
          const ['love', 'audio', 'newQueueableSource'],
          const <Object?>[22050, 16, 2],
        );
        final matching = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 2],
        );
        final mismatch = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 44100, 16, 2],
        );

        expect(await _callMethod(queue, 'getType'), 'queue');
        expect(await _callMethod(queue, 'getFreeBufferCount'), 8);
        expect(await _callMethod(queue, 'getDuration'), 0.0);
        expect(
          await _callMethod(queue, 'getDuration', const <Object?>['samples']),
          0.0,
        );

        expect(await _callMethod(queue, 'queue', <Object?>[matching]), isTrue);
        expect(await _callMethod(queue, 'getFreeBufferCount'), 7);
        expect(
          await _callMethod(queue, 'getDuration', const <Object?>['samples']),
          4.0,
        );
        expect(
          await _callMethod(queue, 'getDuration'),
          closeTo(4 / 22050, 1e-12),
        );

        expect(
          await _callMethod(queue, 'queue', <Object?>[matching, 8]),
          isTrue,
        );
        expect(await _callMethod(queue, 'getFreeBufferCount'), 6);
        expect(
          await _callMethod(queue, 'getDuration', const <Object?>['samples']),
          6.0,
        );

        final clone = await _callMethod(queue, 'clone');
        expect(await _callMethod(clone, 'getType'), 'queue');
        expect(await _callMethod(clone, 'getFreeBufferCount'), 8);
        expect(await _callMethod(clone, 'getDuration'), 0.0);

        expect(
          _callMethod(queue, 'setLooping', const <Object?>[true]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Queueable Sources can not be looped.'),
            ),
          ),
        );
        expect(
          _callMethod(queue, 'queue', <Object?>[mismatch]),
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
          _callMethod(queue, 'queue', <Object?>[matching, 3]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('multiple of sample size'),
            ),
          ),
        );

        await _callMethod(queue, 'stop');
        expect(await _callMethod(queue, 'getFreeBufferCount'), 8);
        expect(await _callMethod(queue, 'getDuration'), 0.0);
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

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
  );
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = await _resolveRawCallResult(result);
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Future<Object?> _resolveRawCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(wrapped.raw as List<Object?>, growable: false);
  }
  return resolved;
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
