import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE sound source parity', () {
    test(
      'SoundData:getChannels and Decoder:getChannels mirror upstream deprecated aliases',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final soundData = await _call(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[4, 22050, 16, 2],
        );
        expect(await _callMethod(soundData!, 'getChannels'), 2);
        expect(await _callMethod(soundData, 'getChannelCount'), 2);

        final fileData = await _call(
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
        final decoder = await _call(
          runtime,
          const ['love', 'sound', 'newDecoder'],
          <Object?>[fileData, 8],
        );
        expect(await _callMethod(decoder!, 'getChannels'), 2);
        expect(await _callMethod(decoder, 'getChannelCount'), 2);
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
  final header = ByteData(44)
    ..setUint32(4, 36 + pcmBytes.length, Endian.little)
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
  Object receiver,
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

BuiltinFunction _rawMethod(Object receiver, String method) {
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
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
