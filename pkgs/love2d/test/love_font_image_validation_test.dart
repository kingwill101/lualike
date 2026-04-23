import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font image validation', () {
    test(
      'newImageRasterizer uses LOVE error text for non-rgba image data',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[2, 2, 'r8'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'font', 'newImageRasterizer'],
            <Object?>[imageData, 'A', 0, 1.0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in Image Fonts!',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newImageFont uses LOVE error text for non-rgba image data',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[2, 2, 'r8'],
        );

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'graphics', 'newImageFont'],
            <Object?>[imageData, 'A', 0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in Image Fonts!',
            ),
          ),
        );
      },
    );
  });
}
