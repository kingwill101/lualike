import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font wrap edge parity', () {
    test(
      'Font:getWrap returns a single empty line for empty strings',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final wrapped =
            await luaCallMethod(font, 'getWrap', const <Object?>['', 10.0])
                as List<Object?>;

        expect((wrapped[0] as num).toDouble(), closeTo(0.0, 1e-9));
        expect(wrapped[1], <Object?, Object?>{1: ''});
      },
    );

    test(
      'Font:getWrap skips oversized leading glyphs and emits LOVE-style empty lines',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );
        final widthA =
            (await luaCallMethod(font, 'getWidth', const <Object?>['A']) as num)
                .toDouble();

        final wrapped =
            await luaCallMethod(font, 'getWrap', <Object?>['A', widthA / 2.0])
                as List<Object?>;

        expect((wrapped[0] as num).toDouble(), closeTo(0.0, 1e-9));
        expect(wrapped[1], <Object?, Object?>{1: '', 2: ''});
      },
    );

    test(
      'Font:getWrap preserves all-space lines while ignoring trailing-space width',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final font = await luaCall(
          runtime,
          const ['love', 'graphics', 'newFont'],
          const <Object?>[12],
        );

        final wrapped =
            await luaCallMethod(font, 'getWrap', const <Object?>['   ', 100.0])
                as List<Object?>;

        expect((wrapped[0] as num).toDouble(), closeTo(0.0, 1e-9));
        expect(wrapped[1], <Object?, Object?>{1: '   '});
      },
    );
  });
}
