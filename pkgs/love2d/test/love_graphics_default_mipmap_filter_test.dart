import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics default mipmap filter', () {
    test(
      'source-backed module methods are installed and reset with graphics state',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final love = runtime.getCurrentEnv().get('love')! as Value;
        final graphics =
            (love.raw as Map<Object?, Object?>)['graphics']! as Value;
        final graphicsTable = graphics.raw as Map<Object?, Object?>;

        expect(graphicsTable.containsKey('getDefaultMipmapFilter'), isTrue);
        expect(graphicsTable.containsKey('setDefaultMipmapFilter'), isTrue);

        expect(
          await luaCallList(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>['linear', 0.0],
        );

        await luaCallList(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>['nearest', 0.5],
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>['nearest', 0.5],
        );

        await luaCallList(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>[null, 0.75],
        );
        expect(
          await luaCallList(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>[null, 0.75],
        );

        await luaCallList(runtime, const ['love', 'graphics', 'reset']);
        expect(
          await luaCallList(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>['linear', 0.0],
        );
      },
    );

    test(
      'new mipmapped images inherit the current default mipmap filter',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await luaCallList(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>['nearest', 0.5],
        );

        final imageData = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 4],
        );
        final image = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[
            imageData,
            Value(<Object?, Object?>{'mipmaps': true}),
          ],
        );

        expect(await luaCallMethodList(image, 'getMipmapFilter'), <Object?>[
          'nearest',
          0.5,
        ]);
      },
    );

    test(
      'new mipmapped canvases inherit the current default mipmap filter',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await luaCallList(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>['nearest', 0.25],
        );

        final canvas = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[
            32,
            16,
            Value(<Object?, Object?>{'mipmaps': 'manual'}),
          ],
        );

        expect(await luaCallMethodList(canvas, 'getMipmapFilter'), <Object?>[
          'nearest',
          0.25,
        ]);
      },
    );
  });
}
