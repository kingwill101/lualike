import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics default mipmap filter', () {
    test(
      'source-backed module methods are installed and reset with graphics state',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final love = runtime.getCurrentEnv().get('love')! as Value;
        final graphics = (love.raw as Map<Object?, Object?>)['graphics']! as Value;
        final graphicsTable = graphics.raw as Map<Object?, Object?>;

        expect(graphicsTable.containsKey('getDefaultMipmapFilter'), isTrue);
        expect(graphicsTable.containsKey('setDefaultMipmapFilter'), isTrue);

        final setDefaultMipmapFilter =
            await lualike.execute('return love.graphics.setDefaultMipmapFilter') as Value;

        expect(
          (await lualike.execute('return love.graphics.getDefaultMipmapFilter()')
                  as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['linear', 0.0],
        );

        await setDefaultMipmapFilter.call(<Object?>['nearest', 0.5]);
        expect(
          (await lualike.execute('return love.graphics.getDefaultMipmapFilter()')
                  as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['nearest', 0.5],
        );

        await setDefaultMipmapFilter.call(<Object?>[null, 0.75]);
        expect(
          (await lualike.execute('return love.graphics.getDefaultMipmapFilter()')
                  as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>[null, 0.75],
        );

        await lualike.execute('love.graphics.reset()');
        expect(
          (await lualike.execute('return love.graphics.getDefaultMipmapFilter()')
                  as List)
              .map((e) => (e as Value).unwrap())
              .toList(),
          <Object?>['linear', 0.0],
        );
      },
    );

    test(
      'new mipmapped images inherit the current default mipmap filter',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final setDefaultMipmapFilter =
            await lualike.execute('return love.graphics.setDefaultMipmapFilter') as Value;
        await setDefaultMipmapFilter.call(<Object?>['nearest', 0.5]);

        final mipmapFilter = await lualike.execute('''
local image = love.graphics.newImage(love.image.newImageData(8, 4), {mipmaps = true})
return image:getMipmapFilter()
''');
        expect(
          (mipmapFilter as List).map((e) => (e as Value).unwrap()).toList(),
          <Object?>['nearest', 0.5],
        );
      },
    );

    test(
      'new mipmapped canvases inherit the current default mipmap filter',
      () async {
        final lualike = LuaLike();
        final runtime = lualike.vm;
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final setDefaultMipmapFilter =
            await lualike.execute('return love.graphics.setDefaultMipmapFilter') as Value;
        await setDefaultMipmapFilter.call(<Object?>['nearest', 0.25]);

        final mipmapFilter = await lualike.execute('''
local canvas = love.graphics.newCanvas(32, 16, {mipmaps = "manual"})
return canvas:getMipmapFilter()
''');
        expect(
          (mipmapFilter as List).map((e) => (e as Value).unwrap()).toList(),
          <Object?>['nearest', 0.25],
        );
      },
    );
  });
}
