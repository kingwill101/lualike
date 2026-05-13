import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics reset', () {
    test(
      'reset restores the screen canvas and default filter state immediately',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final canvas = await luaCall(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          const <Object?>[4, 4],
        );

        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'setDefaultFilter'],
            const <Object?>['nearest', 'linear', 2.0],
          ),
          isNull,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'setCanvas'],
            <Object?>[canvas],
          ),
          isNull,
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getCanvas']),
          isNotNull,
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[5, 6],
        );

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'reset']),
          isNull,
        );

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getCanvas']),
          isNull,
        );
        expect(
          await luaCall(runtime, const [
            'love',
            'graphics',
            'getDefaultFilter',
          ]),
          <Object?>['linear', 'linear', 1.0],
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[1.0, 2.0],
        );
        expect(
          await luaCall(runtime, const ['love', 'graphics', 'getStats']),
          containsPair('canvasswitches', 2),
        );
      },
    );
  });
}
