import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.audio recording device release parity', () {
    test(
      'RecordingDevice type metadata survives release while other methods fail',
      () async {
        final device = LoveRecordingDevice(name: 'Test Mic');
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());
        LoveRuntimeContext.attach(runtime).audio.recordingDevices.add(device);

        final devices = await luaCall(runtime, const [
          'love',
          'audio',
          'getRecordingDevices',
        ]);
        final recordingDevice = (devices! as Map)[1];

        expect(await luaCallMethod(recordingDevice, 'type'), 'RecordingDevice');
        expect(
          await luaCallMethod(recordingDevice, 'typeOf', const <Object?>[
            'Object',
          ]),
          isTrue,
        );

        expect(await luaCallMethod(recordingDevice, 'release'), isTrue);
        expect(await luaCallMethod(recordingDevice, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(recordingDevice, 'getName'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(recordingDevice, 'type'), 'RecordingDevice');
        expect(
          await luaCallMethod(recordingDevice, 'typeOf', const <Object?>[
            'RecordingDevice',
          ]),
          isTrue,
        );
      },
    );
  });
}
