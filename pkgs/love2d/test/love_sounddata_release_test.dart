import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.sound SoundData release', () {
    test(
      'SoundData release invalidates methods but preserves type metadata',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final soundData = await luaCall(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[8, 22050, 16, 2],
        );

        expect(await luaCallMethod(soundData, 'release'), isTrue);
        expect(await luaCallMethod(soundData, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(soundData, 'getSampleCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(soundData, 'type'), 'SoundData');
        expect(
          await luaCallMethod(soundData, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}
