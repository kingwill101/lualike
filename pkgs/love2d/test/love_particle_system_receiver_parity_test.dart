import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics ParticleSystem receiver parity', () {
    test(
      'ParticleSystem type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await luaCall(
          runtime,
          const ['love', 'image', 'newImageData'],
          <Object?>[1, 1],
        );
        final image = await luaCall(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[imageData],
        );
        final particleSystem = await luaCall(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 8],
        );

        final typeMethod = luaRawMethod(particleSystem, 'type');
        final typeOfMethod = luaRawMethod(particleSystem, 'typeOf');

        expect(
          await luaResolveCallResult(
            typeMethod.call(<Object?>[particleSystem]),
          ),
          'ParticleSystem',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[particleSystem, 'Drawable']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (ParticleSystem expected, got nil)",
            ),
          ),
        );

        await expectLater(
          () => luaResolveCallResult(
            typeOfMethod.call(const <Object?>['oops', 'Object']),
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'typeOf' (ParticleSystem expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(particleSystem, 'release'), isTrue);
        expect(await luaCallMethod(particleSystem, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(particleSystem, 'getCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(particleSystem, 'type'), 'ParticleSystem');
        expect(
          await luaCallMethod(particleSystem, 'typeOf', const <Object?>[
            'Object',
          ]),
          isTrue,
        );
      },
    );
  });
}
