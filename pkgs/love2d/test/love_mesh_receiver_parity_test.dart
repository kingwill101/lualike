import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics Mesh receiver parity', () {
    test(
      'Mesh type metadata survives release while other methods fail',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final mesh = await luaCall(
          runtime,
          const ['love', 'graphics', 'newMesh'],
          <Object?>[
            _luaSeq(<Object?>[
              _luaSeq(<Object?>[0.0, 0.0, 0.0, 0.0]),
              _luaSeq(<Object?>[1.0, 0.0, 1.0, 0.0]),
              _luaSeq(<Object?>[1.0, 1.0, 1.0, 1.0]),
            ]),
            'triangles',
            'static',
          ],
        );

        final typeMethod = luaRawMethod(mesh, 'type');
        final typeOfMethod = luaRawMethod(mesh, 'typeOf');

        expect(
          await luaResolveCallResult(typeMethod.call(<Object?>[mesh])),
          'Mesh',
        );
        expect(
          await luaResolveCallResult(
            typeOfMethod.call(<Object?>[mesh, 'Drawable']),
          ),
          isTrue,
        );

        await expectLater(
          () => luaResolveCallResult(typeMethod.call(const <Object?>[])),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "bad argument #1 to 'type' (Mesh expected, got nil)",
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
              "bad argument #1 to 'typeOf' (Mesh expected, got string)",
            ),
          ),
        );

        expect(await luaCallMethod(mesh, 'release'), isTrue);
        expect(await luaCallMethod(mesh, 'release'), isFalse);

        await expectLater(
          () => luaCallMethod(mesh, 'getVertexCount'),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Cannot use object after it has been released.',
            ),
          ),
        );

        expect(await luaCallMethod(mesh, 'type'), 'Mesh');
        expect(
          await luaCallMethod(mesh, 'typeOf', const <Object?>['Object']),
          isTrue,
        );
      },
    );
  });
}

Map<Object?, Object?> _luaSeq(List<Object?> values) => <Object?, Object?>{
  for (var i = 0; i < values.length; i++) i + 1: values[i],
};
