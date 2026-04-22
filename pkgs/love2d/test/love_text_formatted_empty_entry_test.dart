import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Text formatted empty entry parity', () {
    test('addf keeps empty formatted entries as one rendered line', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final font = await luaCall(
        runtime,
        const ['love', 'graphics', 'newFont'],
        const <Object?>[20],
      );
      final text = await luaCall(
        runtime,
        const ['love', 'graphics', 'newText'],
        <Object?>[font, 'seed'],
      );

      final index = await luaCallMethod(text, 'addf', const <Object?>[
        '',
        12.0,
        'left',
      ]);

      expect(await luaCallMethod(text, 'getWidth', <Object?>[index]), 0.0);
      expect(await luaCallMethod(text, 'getHeight', <Object?>[index]), 20.0);
      expect(
        await luaCallMethod(text, 'getDimensions', <Object?>[index]),
        <Object?>[0.0, 20.0],
      );

      expect(await luaCallMethod(text, 'getWidth'), 0.0);
      expect(await luaCallMethod(text, 'getHeight'), 20.0);
      expect(await luaCallMethod(text, 'getDimensions'), <Object?>[0.0, 20.0]);
    });
  });
}
