import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('ParticleSystem deprecated aliases', () {
    test(
      'setAreaSpread and getAreaSpread mirror upstream deprecated alias semantics',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCallList(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[16, 16],
        );
        final image = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[imageData],
        );
        final particleSystem = await luaCallList(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 8],
        );

        await luaCallMethodList(particleSystem!, 'setEmissionArea', <Object?>[
          'ellipse',
          3.0,
          4.0,
          0.5,
          true,
        ]);
        expect(
          await luaCallMethodList(particleSystem, 'getAreaSpread'),
          <Object?>['ellipse', 3.0, 4.0],
        );

        await luaCallMethodList(particleSystem, 'setAreaSpread', <Object?>[
          'uniform',
          5.0,
          6.0,
        ]);
        expect(
          await luaCallMethodList(particleSystem, 'getAreaSpread'),
          <Object?>['uniform', 5.0, 6.0],
        );
        expect(
          await luaCallMethodList(particleSystem, 'getEmissionArea'),
          <Object?>['uniform', 5.0, 6.0, 0.0, false],
        );

        await luaCallMethodList(particleSystem, 'setAreaSpread');
        expect(
          await luaCallMethodList(particleSystem, 'getAreaSpread'),
          <Object?>['none', 0.0, 0.0],
        );
        expect(
          await luaCallMethodList(particleSystem, 'getEmissionArea'),
          <Object?>['none', 0.0, 0.0, 0.0, false],
        );
      },
    );
  });
}
