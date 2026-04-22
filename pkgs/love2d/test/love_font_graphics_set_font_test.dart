import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/font_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics setFont', () {
    test(
      'setFont updates the current graphics font and returns no value',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final defaultFont = await luaCall(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);
        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[9, 6, 'rgba8', imageFontStripBytes()],
        );
        final imageFont = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImageFont'],
          <Object?>[imageData, 'ABC', 1],
        );

        final defaultWidth = await luaCallMethod(
          defaultFont,
          'getWidth',
          const <Object?>['ABC'],
        );
        final imageWidth = await luaCallMethod(
          imageFont,
          'getWidth',
          const <Object?>['ABC'],
        );
        expect(imageWidth, isNot(defaultWidth));

        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'setFont'],
            <Object?>[imageFont],
          ),
          isNull,
        );

        final currentImageFont = await luaCall(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);
        expect(
          await luaCallMethod(currentImageFont, 'getWidth', const <Object?>[
            'ABC',
          ]),
          imageWidth,
        );
        expect(
          await luaCallMethod(currentImageFont, 'getFilter'),
          await luaCallMethod(imageFont, 'getFilter'),
        );

        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'setFont'],
            <Object?>[defaultFont],
          ),
          isNull,
        );

        final restoredFont = await luaCall(runtime, const [
          'love',
          'graphics',
          'getFont',
        ]);
        expect(
          await luaCallMethod(restoredFont, 'getWidth', const <Object?>['ABC']),
          defaultWidth,
        );
      },
    );
  });
}
