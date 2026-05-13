import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('Font object semantics', () {
    test(
      'fonts expose LOVE Object type, typeOf, and release behavior',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[14],
        );

        expect(await luaCallMethodList(font, 'type'), 'Font');
        expect(
          await luaCallMethodList(font, 'typeOf', const <Object?>['Font']),
          isTrue,
        );
        expect(
          await luaCallMethodList(font, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(
          await luaCallMethodList(font, 'typeOf', const <Object?>['Image']),
          isFalse,
        );
        expect(await luaCallMethodList(font, 'release'), isTrue);
        expect(await luaCallMethodList(font, 'release'), isFalse);
      },
    );
  });
}
