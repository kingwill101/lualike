import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/src/install_love2d.dart';
import 'package:love2d/src/runtime/love_runtime.dart';
import 'test_support/lua_api_test_helpers.dart';

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
        var stopCallbackCount = 0;
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
          onStop: (device) {
            stopCallbackCount++;
            return LoveSoundData.silence(
              samples: 2,
              sampleRate: 8000,
              bitDepth: 8,
              channels: 1,
            );
          },
        );

        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());
        LoveRuntimeContext.attach(runtime).audio.recordingDevices.add(device);

        final devices = await luaCallList(runtime, const [
          'love',
          'audio',
          'getRecordingDevices',
        ]);
        expect(devices, isA<Map>());
        final recordingDevice = (devices! as Map)[1];
        expect(recordingDevice, isNotNull);

        expect(
          await luaCallMethodList(recordingDevice, 'type'),
          'RecordingDevice',
        );
        expect(
          await luaCallMethodList(recordingDevice, 'typeOf', const ['Object']),
          isTrue,
        );
        expect(await luaCallMethodList(recordingDevice, 'getName'), 'Test Mic');
        expect(
          await luaCallMethodList(recordingDevice, 'getSampleRate'),
          11025,
        );
        expect(await luaCallMethodList(recordingDevice, 'getBitDepth'), 16);
        expect(await luaCallMethodList(recordingDevice, 'getChannelCount'), 1);
        expect(await luaCallMethodList(recordingDevice, 'getSampleCount'), 0);
        expect(
          await luaCallMethodList(recordingDevice, 'isRecording'),
          isFalse,
        );

        expect(await luaCallMethodList(recordingDevice, 'start'), isTrue);
        expect(await luaCallMethodList(recordingDevice, 'isRecording'), isTrue);
        expect(await luaCallMethodList(recordingDevice, 'getSampleCount'), 4);

        final dataWhileRecording = await luaCallMethodList(
          recordingDevice,
          'getData',
        );
        expect(
          await luaCallMethodList(dataWhileRecording, 'getSampleCount'),
          4,
        );
        expect(
          await luaCallMethodList(dataWhileRecording, 'getSampleRate'),
          22050,
        );

        expect(
          await luaCallMethodList(recordingDevice, 'start', const <Object?>[
            64,
            8000,
            8,
            1,
          ]),
          isTrue,
        );
        expect(await luaCallMethodList(recordingDevice, 'getSampleRate'), 8000);
        expect(await luaCallMethodList(recordingDevice, 'getBitDepth'), 8);
        expect(await luaCallMethodList(recordingDevice, 'getChannelCount'), 1);

        final stoppedData = await luaCallMethodList(recordingDevice, 'stop');
        expect(await luaCallMethodList(stoppedData, 'getSampleCount'), 4);
        expect(await luaCallMethodList(stoppedData, 'getSampleRate'), 22050);
        expect(
          await luaCallMethodList(recordingDevice, 'isRecording'),
          isFalse,
        );
        expect(await luaCallMethodList(recordingDevice, 'getSampleCount'), 0);
        expect(await luaCallMethodList(recordingDevice, 'getData'), isNull);
        expect(stopCallbackCount, 2);
      },
    );

    test(
      'RecordingDevice:start validates capture arguments like LOVE',
      () async {
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
              }) => true,
        );

        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());
        LoveRuntimeContext.attach(runtime).audio.recordingDevices.add(device);

        final devices = await luaCallList(runtime, const [
          'love',
          'audio',
          'getRecordingDevices',
        ]);
        final recordingDevice = (devices! as Map)[1];

        await expectLater(
          () => luaCallMethodList(recordingDevice, 'start', const <Object?>[0]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid number of samples.',
            ),
          ),
        );

        await expectLater(
          () => luaCallMethodList(recordingDevice, 'start', const <Object?>[
            64,
            0,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid sample rate.',
            ),
          ),
        );

        await expectLater(
          () => luaCallMethodList(recordingDevice, 'start', const <Object?>[
            64,
            8000,
            24,
            1,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Recording 1 channels with 24 bits per sample is not supported.',
            ),
          ),
        );

        await expectLater(
          () => luaCallMethodList(recordingDevice, 'start', const <Object?>[
            64,
            8000,
            16,
            3,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Recording 3 channels with 16 bits per sample is not supported.',
            ),
          ),
        );
      },
    );
  });
}
