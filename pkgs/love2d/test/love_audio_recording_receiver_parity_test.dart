import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.audio recording device receiver parity', () {
    test(
      'RecordingDevice:type and RecordingDevice:typeOf require a RecordingDevice receiver',
      () async {
        final device = LoveRecordingDevice(name: 'Test Mic');
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());
        LoveRuntimeContext.attach(runtime).audio.recordingDevices.add(device);

        final devices = await luaCall(runtime, const [
          'love',
          'audio',
          'getRecordingDevices',
        ]);
        final recordingDevice = (devices! as Map)[1];

        final typeMethod = luaRawMethod(recordingDevice, 'type');
        final typeOfMethod = luaRawMethod(recordingDevice, 'typeOf');

        expect(
          await luaResolveCallResult(
            typeMethod.call(<Object?>[recordingDevice]),
          ),
          'RecordingDevice',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[recordingDevice, 'RecordingDevice']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' "
                  '(RecordingDevice expected, got nil)',
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>['oops'])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' "
                  '(RecordingDevice expected, got string)',
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'RecordingDevice']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' "
                  '(RecordingDevice expected, got string)',
            ),
          ),
        );
      },
    );
  });
}
