import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font filter bindings', () {
    test(
      'graphics.newFont inherits the current graphics default filter',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await luaCall(
          runtime,
          const ['love', 'graphics', 'setDefaultFilter'],
          const <Object?>['nearest', 'linear', 4.0],
        );

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        expect(await luaCallMethod(font, 'getFilter'), <Object?>[
          'nearest',
          'linear',
          4.0,
        ]);
      },
    );

    test('Font:setFilter mirrors LOVE filter argument behavior', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[12],
      );

      expect(await luaCallMethod(font, 'getFilter'), <Object?>[
        'linear',
        'linear',
        1.0,
      ]);

      await luaCallMethod(font, 'setFilter', const <Object?>['nearest']);
      expect(await luaCallMethod(font, 'getFilter'), <Object?>[
        'nearest',
        'nearest',
        1.0,
      ]);

      await luaCallMethod(font, 'setFilter', const <Object?>[
        'linear',
        'nearest',
        2.5,
      ]);
      expect(await luaCallMethod(font, 'getFilter'), <Object?>[
        'linear',
        'nearest',
        2.5,
      ]);
    });
  });
}
