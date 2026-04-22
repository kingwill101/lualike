import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('Text object semantics', () {
    test(
      'text objects expose LOVE type, typeOf, and release behavior',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[14],
        );
        final text = await luaCall(
          runtime,
          const ['love', 'graphics', 'newText'],
          <Object?>[font, 'LuaLike'],
        );

        expect(await luaCallMethod(text, 'type'), 'Text');
        expect(
          await luaCallMethod(text, 'typeOf', const <Object?>['Text']),
          isTrue,
        );
        expect(
          await luaCallMethod(text, 'typeOf', const <Object?>['Drawable']),
          isTrue,
        );
        expect(
          await luaCallMethod(text, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
        expect(
          await luaCallMethod(text, 'typeOf', const <Object?>['Font']),
          isFalse,
        );
        expect(await luaCallMethod(text, 'release'), isTrue);
        expect(await luaCallMethod(text, 'release'), isFalse);
      },
    );
  });
}
