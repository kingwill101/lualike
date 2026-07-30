import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics reset', () {
    test(
      'reset restores the screen canvas and default filter state immediately',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final canvas = await lualike.execute('return love.graphics.newCanvas(4, 4)');

        expect(
          await lualike.execute(
            'return love.graphics.setDefaultFilter("nearest", "linear", 2.0)',
          ),
          isNull,
        );
        final setCanvas =
            await lualike.execute('return love.graphics.setCanvas') as Value;
        expect(await setCanvas.call(<Object?>[canvas]), isNull);
        expect(await lualike.execute('return love.graphics.getCanvas()'), isNotNull);

        await lualike.execute('love.graphics.translate(5, 6)');

        expect(await lualike.execute('return love.graphics.reset()'), isNull);

        expect(await lualike.execute('return love.graphics.getCanvas()'), isNull);
        expect(
          (await lualike.execute('return love.graphics.getDefaultFilter()') as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['linear', 'linear', 1.0],
        );
        expect(
          (await lualike.execute('return love.graphics.transformPoint(1, 2)')
                  as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>[1.0, 2.0],
        );
        expect(
          (await lualike.execute('return love.graphics.getStats()') as Value)
              .unwrap(),
          containsPair('canvasswitches', 2),
        );
      },
    );
  });
}
