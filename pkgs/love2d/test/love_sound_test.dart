import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.sound bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'newSoundData numeric constructor and sample access match LÖVE',
      () async {
        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[3, 22050, 16, 2],
        );

        expect(await _callMethod(soundData, 'type'), 'SoundData');
        expect(
          await _callMethod(soundData, 'typeOf', const <Object?>['Data']),
          isTrue,
        );
        expect(await _callMethod(soundData, 'getSampleCount'), 3);
        expect(await _callMethod(soundData, 'getSampleRate'), 22050);
        expect(await _callMethod(soundData, 'getBitDepth'), 16);
        expect(await _callMethod(soundData, 'getChannelCount'), 2);
        expect(
          await _callMethod(soundData, 'getSample', const <Object?>[0]),
          0,
        );

        await _callMethod(soundData, 'setSample', const <Object?>[1, 2, -0.5]);
        expect(
          await _callMethod(soundData, 'getSample', const <Object?>[1, 2]),
          closeTo(-0.5, 0.0001),
        );

        final cloned = await _callMethod(soundData, 'clone');
        expect(await _callMethod(cloned, 'type'), 'SoundData');
        expect(
          await _callMethod(cloned, 'getSample', const <Object?>[1, 2]),
          closeTo(-0.5, 0.0001),
        );
      },
    );

    test('8-bit SoundData uses unsigned byte sample conversion', () async {
      final soundData = await _call(
        runtime,
        const ['love', 'sound', 'newSoundData'],
        const <Object?>[2, 11025, 8, 1],
      );

      expect(
        await _call(
          runtime,
          const ['love', 'data', 'encode'],
          <Object?>['string', 'hex', soundData],
        ),
        '8080',
      );

      await _callMethod(soundData, 'setSample', const <Object?>[0, -1.0]);
      await _callMethod(soundData, 'setSample', const <Object?>[1, 1.0]);

      expect(
        await _callMethod(soundData, 'getSample', const <Object?>[0]),
        closeTo(-1.0, 0.01),
      );
      expect(
        await _callMethod(soundData, 'getSample', const <Object?>[1]),
        closeTo(1.0, 0.01),
      );
      expect(
        await _call(
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
        final fileData = await _call(
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

        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );

        expect(await _callMethod(decoder, 'type'), 'Decoder');
        expect(
          await _callMethod(decoder, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(await _callMethod(decoder, 'getSampleRate'), 4);
        expect(await _callMethod(decoder, 'getBitDepth'), 16);
        expect(await _callMethod(decoder, 'getChannelCount'), 2);
        expect(
          await _callMethod(decoder, 'getDuration'),
          closeTo(0.75, 0.0001),
        );

        final firstChunk = await _callMethod(decoder, 'decode');
        expect(await _callMethod(firstChunk, 'type'), 'SoundData');
        expect(await _callMethod(firstChunk, 'getSampleCount'), 2);
        expect(
          await _callMethod(firstChunk, 'getSample', const <Object?>[0, 2]),
          closeTo(1.0, 0.0001),
        );
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', firstChunk],
          ),
          '0000ff7f00c00040',
        );

        final clone = await _callMethod(decoder, 'clone');
        final clonedChunk = await _callMethod(clone, 'decode');
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', clonedChunk],
          ),
          '0000ff7f00c00040',
        );

        await _callMethod(decoder, 'seek', const <Object?>[0.5]);
        final tail = await _callMethod(decoder, 'decode');
        expect(await _callMethod(tail, 'getSampleCount'), 1);
        expect(
          await _callMethod(tail, 'getSample', const <Object?>[0, 1]),
          closeTo(8192 / 32767.0, 0.0001),
        );
        expect(await _callMethod(decoder, 'decode'), isNull);
      },
    );

    test(
      'newSoundData can drain decoders and resulting SoundData works as Data',
      () async {
        final fileData = await _call(
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

        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );
        await _callMethod(decoder, 'seek', const <Object?>[0.25]);

        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          <Object?>[decoder],
        );

        expect(await _callMethod(soundData, 'getSampleCount'), 2);
        expect(
          await _call(
            runtime,
            const ['love', 'data', 'encode'],
            <Object?>['string', 'hex', soundData],
          ),
          '00c00040002000e0',
        );
        expect(
          await _callMethod(soundData, 'getSample', const <Object?>[0, 1]),
          closeTo(-16384 / 32767.0, 0.0001),
        );
      },
    );

    test(
      'newDecoder and newSoundData read mounted LOVE filesystem strings and reject missing filenames',
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

        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          const <Object?>['sounds/theme.wav', 8],
        );
        expect(await _callMethod(decoder, 'getSampleRate'), 4);
        expect(
          await _callMethod(decoder, 'getDuration'),
          closeTo(0.75, 0.0001),
        );

        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>['sounds/theme.wav'],
        );
        expect(await _callMethod(soundData, 'getSampleCount'), 3);
        expect(await _callMethod(soundData, 'getSampleRate'), 4);

        await expectLater(
          () => _call(
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
          () => _call(
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
        final fileData = await _call(
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

        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 16],
        );

        expect(await _callMethod(decoder, 'getSampleRate'), 4);
        expect(await _callMethod(decoder, 'getBitDepth'), 16);
        expect(await _callMethod(decoder, 'getChannelCount'), 2);
        expect(await _callMethod(decoder, 'getDuration'), closeTo(0.5, 0.0001));

        final chunk = await _callMethod(decoder, 'decode');
        expect(await _callMethod(chunk, 'getSampleCount'), 2);
        expect(
          await _callMethod(chunk, 'getSample', const <Object?>[0, 2]),
          closeTo(1.0, 0.0001),
        );
        expect(
          await _callMethod(chunk, 'getSample', const <Object?>[1, 1]),
          closeTo(-0.5, 0.001),
        );
        expect(
          await _callMethod(chunk, 'getSample', const <Object?>[1, 2]),
          closeTo(0.25, 0.001),
        );
      },
    );

    test(
      'newDecoder converts extensible 24-bit PCM WAV audio into 16-bit SoundData',
      () async {
        final fileData = await _call(
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

        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 12],
        );

        expect(await _callMethod(decoder, 'getSampleRate'), 6);
        expect(await _callMethod(decoder, 'getBitDepth'), 16);
        expect(await _callMethod(decoder, 'getChannelCount'), 1);
        expect(await _callMethod(decoder, 'getDuration'), closeTo(0.5, 0.0001));

        final chunk = await _callMethod(decoder, 'decode');
        expect(await _callMethod(chunk, 'getSampleCount'), 3);
        expect(
          await _callMethod(chunk, 'getSample', const <Object?>[0]),
          closeTo(0.0, 0.0001),
        );
        expect(
          await _callMethod(chunk, 'getSample', const <Object?>[1]),
          closeTo(1.0, 0.0001),
        );
        expect(
          await _callMethod(chunk, 'getSample', const <Object?>[2]),
          closeTo(-0.5, 0.001),
        );
      },
    );

    test(
      'unsupported sound containers report partial codec support clearly',
      () async {
        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          const <Object?>['not real audio', 'fixture.ogg'],
        );

        expect(
          _call(
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
