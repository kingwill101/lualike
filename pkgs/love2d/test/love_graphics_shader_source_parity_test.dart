import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('LOVE graphics shader source parity', () {
    test(
      '_setDefaultShaderCode accepts the upstream-generated default table shape',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final love = runtime.getCurrentEnv().get('love')! as Value;
        final graphics =
            (love.raw as Map<Object?, Object?>)['graphics']! as Value;
        final graphicsTable = graphics.raw as Map<Object?, Object?>;

        expect(graphicsTable.containsKey('_setDefaultShaderCode'), isTrue);

        final result = await luaCallList(
          runtime,
          const ['love', 'graphics', '_setDefaultShaderCode'],
          <Object?>[
            Value(_defaultShaderTable('default')),
            Value(_defaultShaderTable('gammacorrect')),
          ],
        );

        expect(result, isNull);
      },
    );

    test('_setDefaultShaderCode rejects malformed shader default tables', () {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      expect(
        () =>
            luaRawFunction(runtime, const [
              'love',
              'graphics',
              '_setDefaultShaderCode',
            ]).call(<Object?>[
              Value(_defaultShaderTable('default')),
              Value(<Object?, Object?>{
                'glsl1': <Object?, Object?>{
                  'vertex': 'vertex',
                  'pixel': 'pixel',
                  'videopixel': 'videopixel',
                },
              }),
            ]),
        throwsA(isA<LuaError>()),
      );
    });
  });
}

Map<Object?, Object?> _defaultShaderTable(String prefix) {
  return <Object?, Object?>{
    for (final language in const <String>['glsl1', 'essl1', 'glsl3', 'essl3'])
      language: <Object?, Object?>{
        'vertex': '$prefix-$language-vertex',
        'pixel': '$prefix-$language-pixel',
        'videopixel': '$prefix-$language-videopixel',
        'arraypixel': '$prefix-$language-arraypixel',
      },
  };
}
