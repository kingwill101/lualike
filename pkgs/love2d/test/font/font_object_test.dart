import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Font object semantics', () {
    test(
      'fonts expose LOVE Object type, typeOf, and release behavior',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final typeResult = await lualike.execute('''
local font = love.graphics.newFont(14)
return font:type(), font:typeOf("Font"), font:typeOf("Object"), font:typeOf("Image")
''');
        expect(
          (typeResult as List).map((e) => (e as Value).unwrap()).toList(),
          <Object?>['Font', true, true, false],
        );

        final releaseResult = await lualike.execute('''
local font = love.graphics.newFont(14)
return font:release(), font:release()
''');
        expect(
          (releaseResult as List).map((e) => (e as Value).unwrap()).toList(),
          <Object?>[true, false],
        );
      },
    );
  });
}
