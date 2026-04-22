import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.font layout parity', () {
    test(
      'Font:getWidth follows LOVE newline and carriage-return rules',
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
        final widthB =
            (await luaCallMethod(font, 'getWidth', const <Object?>['B']) as num)
                .toDouble();
        final widthAB =
            (await luaCallMethod(font, 'getWidth', const <Object?>['AB'])
                    as num)
                .toDouble();
        final widthMultiLine =
            (await luaCallMethod(font, 'getWidth', const <Object?>['A\nB'])
                    as num)
                .toDouble();
        final widthWithCarriageReturn =
            (await luaCallMethod(font, 'getWidth', const <Object?>['A\rB'])
                    as num)
                .toDouble();

        final expectedMultiLineWidth = widthA > widthB ? widthA : widthB;

        expect(widthMultiLine, closeTo(expectedMultiLineWidth, 1e-9));
        expect(widthWithCarriageReturn, closeTo(widthAB, 1e-9));
      },
    );

    test('Font:getWrap preserves trailing spaces in wrapped lines', () async {
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
      final widthB =
          (await luaCallMethod(font, 'getWidth', const <Object?>['B']) as num)
              .toDouble();
      final widthABWithSpace =
          (await luaCallMethod(font, 'getWidth', const <Object?>['A B']) as num)
              .toDouble();

      final wrapLimit = (widthA + widthABWithSpace) / 2.0;
      final wrapped =
          await luaCallMethod(font, 'getWrap', <Object?>['A B', wrapLimit])
              as List<Object?>;

      final expectedWidth = widthA > widthB ? widthA : widthB;

      expect((wrapped[0] as num).toDouble(), closeTo(expectedWidth, 1e-9));
      expect(wrapped[1], <Object?, Object?>{1: 'A ', 2: 'B'});
    });
  });
}
