import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/src/install_love2d.dart';
import 'package:love2d/src/runtime/love_runtime.dart';

void main() {
  group('love.audio recording device bindings', () {
    test(
      'host-provided recording devices are exposed with LOVE-style methods',
      () async {
        final recordedData = LoveSoundData.silence(
          samples: 4,
          sampleRate: 22050,
          bitDepth: 16,
          channels: 1,
        );
        final device = LoveRecordingDevice(
          name: 'Test Mic',
          maxSamples: 32,
          sampleRate: 11025,
          bitDepth: 16,
          channelCount: 1,
          onStart:
              (
                device, {
                required samples,
                required sampleRate,
                required bitDepth,
                required channels,
              }) {
                device.sampleCount = recordedData.sampleCount;
                return true;
              },
          onGetData: (device) => recordedData.clone(),
          onStop: (device) => recordedData.clone(),
        );

        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());
        LoveRuntimeContext.attach(runtime).audio.recordingDevices.add(device);

        final devices = await _call(runtime, const [
          'love',
          'audio',
          'getRecordingDevices',
        ]);
        expect(devices, isA<Map>());
        final recordingDevice = (devices! as Map)[1];
        expect(recordingDevice, isNotNull);

        expect(await _callMethod(recordingDevice, 'type'), 'RecordingDevice');
        expect(
          await _callMethod(recordingDevice, 'typeOf', const ['Object']),
          isTrue,
        );
        expect(await _callMethod(recordingDevice, 'getName'), 'Test Mic');
        expect(await _callMethod(recordingDevice, 'getSampleRate'), 11025);
        expect(await _callMethod(recordingDevice, 'getBitDepth'), 16);
        expect(await _callMethod(recordingDevice, 'getChannelCount'), 1);
        expect(await _callMethod(recordingDevice, 'getSampleCount'), 0);
        expect(await _callMethod(recordingDevice, 'isRecording'), isFalse);

        expect(await _callMethod(recordingDevice, 'start'), isTrue);
        expect(await _callMethod(recordingDevice, 'isRecording'), isTrue);
        expect(await _callMethod(recordingDevice, 'getSampleCount'), 4);

        final dataWhileRecording = await _callMethod(
          recordingDevice,
          'getData',
        );
        expect(await _callMethod(dataWhileRecording, 'getSampleCount'), 4);
        expect(await _callMethod(dataWhileRecording, 'getSampleRate'), 22050);

        expect(
          await _callMethod(recordingDevice, 'start', const <Object?>[
            64,
            8000,
            8,
            1,
          ]),
          isTrue,
        );
        expect(await _callMethod(recordingDevice, 'getSampleRate'), 8000);
        expect(await _callMethod(recordingDevice, 'getBitDepth'), 8);
        expect(await _callMethod(recordingDevice, 'getChannelCount'), 1);

        final stoppedData = await _callMethod(recordingDevice, 'stop');
        expect(await _callMethod(stoppedData, 'getSampleCount'), 4);
        expect(await _callMethod(recordingDevice, 'isRecording'), isFalse);
        expect(await _callMethod(recordingDevice, 'getData'), isNull);
      },
    );
  });
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
