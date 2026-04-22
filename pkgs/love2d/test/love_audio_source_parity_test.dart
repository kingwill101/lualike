import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE audio source parity', () {
    test(
      'getSourceCount and Source:getChannels mirror upstream deprecated aliases',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final soundData = await luaCallList(
          runtime,
          const ['love', 'sound', 'newSoundData'],
          const <Object?>[1024, 22050, 16, 2],
        );
        final source = await luaCallList(
          runtime,
          const ['love', 'audio', 'newSource'],
          <Object?>[soundData, 'stream'],
        );

        expect(await luaCallMethodList(source!, 'getChannels'), 2);
        expect(await luaCallMethodList(source, 'getChannelCount'), 2);

        expect(
          await luaCallList(runtime, const ['love', 'audio', 'getSourceCount']),
          0,
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          0,
        );

        expect(await luaCallMethodList(source, 'play'), isTrue);
        expect(
          await luaCallList(runtime, const ['love', 'audio', 'getSourceCount']),
          1,
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          1,
        );

        await luaCallList(runtime, const ['love', 'audio', 'pause']);
        expect(
          await luaCallList(runtime, const ['love', 'audio', 'getSourceCount']),
          0,
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'audio',
            'getActiveSourceCount',
          ]),
          0,
        );
      },
    );
  });
}
