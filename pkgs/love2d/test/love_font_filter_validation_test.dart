import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font filter validation', () {
    test(
      'Font:setFilter uses LOVE enum error text for invalid min filter',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        await expectLater(
          () => luaCallMethod(font, 'setFilter', const <Object?>['bogus']),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid filter mode 'bogus', expected one of: "
                  "'linear', 'nearest'",
            ),
          ),
        );
      },
    );

    test(
      'Font:setFilter uses LOVE enum error text for invalid mag filter',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        await expectLater(
          () => luaCallMethod(font, 'setFilter', const <Object?>[
            'linear',
            'bogus',
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid filter mode 'bogus', expected one of: "
                  "'linear', 'nearest'",
            ),
          ),
        );
      },
    );
  });
}
