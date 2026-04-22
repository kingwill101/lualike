import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love core bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test('getVersion and isVersionCompatible follow LOVE 11.5', () async {
      expect(await luaCall(runtime, const ['love', 'getVersion']), <Object?>[
        11,
        5,
        0,
        'Mysterious Mysteries',
      ]);
      expect(
        await luaCall(
          runtime,
          const ['love', 'isVersionCompatible'],
          const <Object?>['11.5'],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'isVersionCompatible'],
          const <Object?>['11.4'],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'isVersionCompatible'],
          const <Object?>['11'],
        ),
        isFalse,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'isVersionCompatible'],
          const <Object?>[11, 2, 0],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'isVersionCompatible'],
          const <Object?>[12, 0, 0],
        ),
        isFalse,
      );
    });

    test('deprecation output state can be queried and changed', () async {
      expect(
        await luaCall(runtime, const ['love', 'hasDeprecationOutput']),
        isTrue,
      );

      await luaCall(
        runtime,
        const ['love', 'setDeprecationOutput'],
        const <Object?>[false],
      );
      expect(
        await luaCall(runtime, const ['love', 'hasDeprecationOutput']),
        isFalse,
      );

      await luaCall(
        runtime,
        const ['love', 'setDeprecationOutput'],
        const <Object?>[true],
      );
      expect(
        await luaCall(runtime, const ['love', 'hasDeprecationOutput']),
        isTrue,
      );
    });

    test(
      'Lua scripts can use the core version and deprecation helpers',
      () async {
        final script = LoveScriptRuntime(runtime: runtime);

        await script.execute('''
testbed = {}

local major, minor, revision, codename = love.getVersion()
testbed.version = string.format("%d.%d.%d|%s", major, minor, revision, codename)
testbed.compat_string = love.isVersionCompatible("11.5")
testbed.compat_numbers = love.isVersionCompatible(11, 0, 0)
testbed.before = love.hasDeprecationOutput()
love.setDeprecationOutput(false)
testbed.after = love.hasDeprecationOutput()
''');

        final snapshot = script.unwrapGlobalTable('testbed')!;
        expect(snapshot['version'], '11.5.0|Mysterious Mysteries');
        expect(snapshot['compat_string'], isTrue);
        expect(snapshot['compat_numbers'], isTrue);
        expect(snapshot['before'], isTrue);
        expect(snapshot['after'], isFalse);
      },
    );
  });
}
