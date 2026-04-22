import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.keyboard module', () {
    late Interpreter runtime;
    late LoveHeadlessHost host;

    setUp(() {
      runtime = Interpreter();
      host = LoveHeadlessHost();
      installLove2d(runtime: runtime, host: host);
    });

    test('maps keys and scancodes using LOVE constants', () async {
      expect(
        await luaCall(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['a'],
        ),
        'a',
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['lgui'],
        ),
        'lgui',
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['printscreen'],
        ),
        'printscreen',
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['appsearch'],
        ),
        'acsearch',
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'keyboard', 'getKeyFromScancode'],
          const <Object?>['a'],
        ),
        'a',
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'keyboard', 'getKeyFromScancode'],
          const <Object?>['acsearch'],
        ),
        'appsearch',
      );

      await expectLater(
        luaCall(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['lmeta'],
        ),
        throwsA(isA<LuaError>()),
      );
    });

    test('tracks key repeat, text input, and screen keyboard state', () async {
      host.keyboard.screenKeyboardSupported = true;

      expect(
        await luaCall(runtime, const ['love', 'keyboard', 'hasKeyRepeat']),
        isFalse,
      );
      expect(
        await luaCall(runtime, const ['love', 'keyboard', 'hasTextInput']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'keyboard', 'hasScreenKeyboard']),
        isTrue,
      );

      await luaCall(
        runtime,
        const ['love', 'keyboard', 'setKeyRepeat'],
        const <Object?>[true],
      );
      await luaCall(
        runtime,
        const ['love', 'keyboard', 'setTextInput'],
        const <Object?>[true, 12.5, 20.25, 160.0, 48.0],
      );

      expect(
        await luaCall(runtime, const ['love', 'keyboard', 'hasKeyRepeat']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'keyboard', 'hasTextInput']),
        isTrue,
      );
      expect(host.keyboard.textInputArea, isNotNull);
      expect(host.keyboard.textInputArea!.x, 12.5);
      expect(host.keyboard.textInputArea!.y, 20.25);
      expect(host.keyboard.textInputArea!.width, 160.0);
      expect(host.keyboard.textInputArea!.height, 48.0);

      await luaCall(
        runtime,
        const ['love', 'keyboard', 'setTextInput'],
        const <Object?>[false],
      );
      expect(
        await luaCall(runtime, const ['love', 'keyboard', 'hasTextInput']),
        isFalse,
      );
    });

    test(
      'reports pressed keys and scancodes for variadic and table inputs',
      () async {
        host.keyboard.setKeyDown('a', down: true);
        host.keyboard.setKeyDown('appsearch', down: true);

        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            const <Object?>['x', 'a'],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            <Object?>[
              Value(<Object?, Object?>{1: 'escape', 2: 'appsearch'}),
            ],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isScancodeDown'],
            const <Object?>['escape', 'acsearch'],
          ),
          isTrue,
        );
        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isScancodeDown'],
            <Object?>[
              Value(<Object?, Object?>{1: 'lshift', 2: 'acsearch'}),
            ],
          ),
          isTrue,
        );
      },
    );

    test(
      'lua-side variadic isDown preserves single-character key constants',
      () async {
        host.keyboard.setKeyDown('d', down: true);
        final lua = LuaLike(runtime: runtime);

        await lua.execute('''
pressed = love.keyboard.isDown("right", "d")
''');

        expect((runtime.globals.get('pressed') as Value).unwrap(), isTrue);
      },
    );

    test(
      'isDown ignores leaked active touch ids after valid key constants',
      () async {
        host.keyboard.setKeyDown('d', down: true);
        host.touch.beginTouch(id: 100, x: 0, y: 0);

        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            const <Object?>['right', 'd', 100],
          ),
          isTrue,
        );
      },
    );

    test(
      'isDown ignores leaked active touch ids before valid key constants',
      () async {
        host.keyboard.setKeyDown('d', down: true);
        host.touch.beginTouch(id: 100, x: 0, y: 0);

        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            const <Object?>[100, 'd'],
          ),
          isTrue,
        );
      },
    );

    test(
      'isDown returns false when every argument is a leaked active touch id',
      () async {
        host.touch.beginTouch(id: 100, x: 0, y: 0);

        expect(
          await luaCall(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            const <Object?>[100],
          ),
          isFalse,
        );
      },
    );

    test(
      'isDown still rejects standalone numeric-like values that are not touches',
      () async {
        await expectLater(
          luaCall(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            const <Object?>[100],
          ),
          throwsA(isA<LuaError>()),
        );
      },
    );
  });

  group('love.mouse module', () {
    late Interpreter runtime;
    late LoveHeadlessHost host;

    setUp(() {
      runtime = Interpreter();
      host = LoveHeadlessHost();
      installLove2d(runtime: runtime, host: host);
    });

    test('tracks position, visibility, grab, and relative mode', () async {
      await luaCall(
        runtime,
        const ['love', 'mouse', 'setPosition'],
        const <Object?>[12.9, 34.1],
      );
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'getPosition']),
        <Object?>[12.0, 34.0],
      );

      await luaCall(
        runtime,
        const ['love', 'mouse', 'setX'],
        const <Object?>[9.9],
      );
      await luaCall(
        runtime,
        const ['love', 'mouse', 'setY'],
        const <Object?>[7.8],
      );
      expect(await luaCall(runtime, const ['love', 'mouse', 'getX']), 9.0);
      expect(await luaCall(runtime, const ['love', 'mouse', 'getY']), 7.0);

      expect(
        await luaCall(runtime, const ['love', 'mouse', 'isVisible']),
        isTrue,
      );
      await luaCall(
        runtime,
        const ['love', 'mouse', 'setVisible'],
        const <Object?>[false],
      );
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'isVisible']),
        isFalse,
      );

      await luaCall(
        runtime,
        const ['love', 'mouse', 'setVisible'],
        const <Object?>[true],
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'mouse', 'setRelativeMode'],
          const <Object?>[true],
        ),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'getRelativeMode']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'isVisible']),
        isFalse,
      );

      await luaCall(
        runtime,
        const ['love', 'mouse', 'setRelativeMode'],
        const <Object?>[false],
      );
      await luaCall(
        runtime,
        const ['love', 'mouse', 'setGrabbed'],
        const <Object?>[true],
      );
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'isGrabbed']),
        isTrue,
      );
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'isVisible']),
        isTrue,
      );
    });

    test('reports pressed buttons for variadic and table inputs', () async {
      host.mouse.setButtonDown(2, down: true);

      expect(
        await luaCall(
          runtime,
          const ['love', 'mouse', 'isDown'],
          const <Object?>[1, 2],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'mouse', 'isDown'],
          <Object?>[
            Value(<Object?, Object?>{1: 1, 2: 2}),
          ],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'mouse', 'isDown'],
          const <Object?>[1, 3],
        ),
        isFalse,
      );
    });

    test('creates and manages cursor objects', () async {
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'isCursorSupported']),
        isTrue,
      );

      final handCursor = await luaCall(
        runtime,
        const ['love', 'mouse', 'getSystemCursor'],
        const <Object?>['hand'],
      );
      expect(await luaCallMethod(handCursor!, 'getType'), 'hand');

      await expectLater(
        luaCall(
          runtime,
          const ['love', 'mouse', 'getSystemCursor'],
          const <Object?>['image'],
        ),
        throwsA(isA<LuaError>()),
      );

      await luaCall(
        runtime,
        const ['love', 'mouse', 'setCursor'],
        <Object?>[handCursor],
      );
      final currentCursor = await luaCall(runtime, const [
        'love',
        'mouse',
        'getCursor',
      ]);
      expect(await luaCallMethod(currentCursor!, 'getType'), 'hand');

      final imageData = await luaCall(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 8],
      );
      final imageCursor = await luaCall(
        runtime,
        const ['love', 'mouse', 'newCursor'],
        <Object?>[imageData!, 2, 3],
      );
      expect(await luaCallMethod(imageCursor!, 'getType'), 'image');

      final imageCursorWithDefaultHotspot = await luaCall(
        runtime,
        const ['love', 'mouse', 'newCursor'],
        <Object?>[imageData],
      );
      expect(
        await luaCallMethod(imageCursorWithDefaultHotspot!, 'getType'),
        'image',
      );

      final fileData = await luaCall(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          LoveImageData(width: 8, height: 8).encode('png'),
          'cursor.png',
        ],
      );
      final fileCursor = await luaCall(
        runtime,
        const ['love', 'mouse', 'newCursor'],
        <Object?>[fileData!],
      );
      expect(await luaCallMethod(fileCursor!, 'getType'), 'image');

      await luaCall(runtime, const ['love', 'mouse', 'setCursor']);
      expect(
        await luaCall(runtime, const ['love', 'mouse', 'getCursor']),
        isNull,
      );
    });

    test(
      'newCursor reads mounted LOVE filesystem strings and rejects missing filenames',
      () async {
        final runtime = Interpreter();
        final host = LoveHeadlessHost();
        installLove2d(
          runtime: runtime,
          host: host,
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'cursor.png': LoveImageData(width: 8, height: 8).encode('png'),
            }),
          ),
        );
        final filesystem = LoveFilesystemState.of(runtime);
        expect(filesystem.setSource(loveTestMountedSourceRoot), isTrue);

        final cursor = await luaCall(
          runtime,
          const ['love', 'mouse', 'newCursor'],
          const <Object?>['cursor.png', 1, 2],
        );
        expect(await luaCallMethod(cursor!, 'getType'), 'image');

        await expectLater(
          () => luaCall(
            runtime,
            const ['love', 'mouse', 'newCursor'],
            const <Object?>['missing.png'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Could not open file missing.png. Does not exist.'),
            ),
          ),
        );
      },
    );
  });
}
