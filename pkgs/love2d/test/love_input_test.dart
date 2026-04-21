import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

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
        await _call(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['a'],
        ),
        'a',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['lgui'],
        ),
        'lgui',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['printscreen'],
        ),
        'printscreen',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'keyboard', 'getScancodeFromKey'],
          const <Object?>['appsearch'],
        ),
        'acsearch',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'keyboard', 'getKeyFromScancode'],
          const <Object?>['a'],
        ),
        'a',
      );
      expect(
        await _call(
          runtime,
          const ['love', 'keyboard', 'getKeyFromScancode'],
          const <Object?>['acsearch'],
        ),
        'appsearch',
      );

      await expectLater(
        _call(
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
        await _call(runtime, const ['love', 'keyboard', 'hasKeyRepeat']),
        isFalse,
      );
      expect(
        await _call(runtime, const ['love', 'keyboard', 'hasTextInput']),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'keyboard', 'hasScreenKeyboard']),
        isTrue,
      );

      await _call(
        runtime,
        const ['love', 'keyboard', 'setKeyRepeat'],
        const <Object?>[true],
      );
      await _call(
        runtime,
        const ['love', 'keyboard', 'setTextInput'],
        const <Object?>[true, 12.5, 20.25, 160.0, 48.0],
      );

      expect(
        await _call(runtime, const ['love', 'keyboard', 'hasKeyRepeat']),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'keyboard', 'hasTextInput']),
        isTrue,
      );
      expect(host.keyboard.textInputArea, isNotNull);
      expect(host.keyboard.textInputArea!.x, 12.5);
      expect(host.keyboard.textInputArea!.y, 20.25);
      expect(host.keyboard.textInputArea!.width, 160.0);
      expect(host.keyboard.textInputArea!.height, 48.0);

      await _call(
        runtime,
        const ['love', 'keyboard', 'setTextInput'],
        const <Object?>[false],
      );
      expect(
        await _call(runtime, const ['love', 'keyboard', 'hasTextInput']),
        isFalse,
      );
    });

    test(
      'reports pressed keys and scancodes for variadic and table inputs',
      () async {
        host.keyboard.setKeyDown('a', down: true);
        host.keyboard.setKeyDown('appsearch', down: true);

        expect(
          await _call(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            const <Object?>['x', 'a'],
          ),
          isTrue,
        );
        expect(
          await _call(
            runtime,
            const ['love', 'keyboard', 'isDown'],
            <Object?>[
              Value(<Object?, Object?>{1: 'escape', 2: 'appsearch'}),
            ],
          ),
          isTrue,
        );
        expect(
          await _call(
            runtime,
            const ['love', 'keyboard', 'isScancodeDown'],
            const <Object?>['escape', 'acsearch'],
          ),
          isTrue,
        );
        expect(
          await _call(
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
      await _call(
        runtime,
        const ['love', 'mouse', 'setPosition'],
        const <Object?>[12.9, 34.1],
      );
      expect(
        await _call(runtime, const ['love', 'mouse', 'getPosition']),
        <Object?>[12.0, 34.0],
      );

      await _call(
        runtime,
        const ['love', 'mouse', 'setX'],
        const <Object?>[9.9],
      );
      await _call(
        runtime,
        const ['love', 'mouse', 'setY'],
        const <Object?>[7.8],
      );
      expect(await _call(runtime, const ['love', 'mouse', 'getX']), 9.0);
      expect(await _call(runtime, const ['love', 'mouse', 'getY']), 7.0);

      expect(
        await _call(runtime, const ['love', 'mouse', 'isVisible']),
        isTrue,
      );
      await _call(
        runtime,
        const ['love', 'mouse', 'setVisible'],
        const <Object?>[false],
      );
      expect(
        await _call(runtime, const ['love', 'mouse', 'isVisible']),
        isFalse,
      );

      await _call(
        runtime,
        const ['love', 'mouse', 'setVisible'],
        const <Object?>[true],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'mouse', 'setRelativeMode'],
          const <Object?>[true],
        ),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'mouse', 'getRelativeMode']),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'mouse', 'isVisible']),
        isFalse,
      );

      await _call(
        runtime,
        const ['love', 'mouse', 'setRelativeMode'],
        const <Object?>[false],
      );
      await _call(
        runtime,
        const ['love', 'mouse', 'setGrabbed'],
        const <Object?>[true],
      );
      expect(
        await _call(runtime, const ['love', 'mouse', 'isGrabbed']),
        isTrue,
      );
      expect(
        await _call(runtime, const ['love', 'mouse', 'isVisible']),
        isTrue,
      );
    });

    test('reports pressed buttons for variadic and table inputs', () async {
      host.mouse.setButtonDown(2, down: true);

      expect(
        await _call(
          runtime,
          const ['love', 'mouse', 'isDown'],
          const <Object?>[1, 2],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'mouse', 'isDown'],
          <Object?>[
            Value(<Object?, Object?>{1: 1, 2: 2}),
          ],
        ),
        isTrue,
      );
      expect(
        await _call(
          runtime,
          const ['love', 'mouse', 'isDown'],
          const <Object?>[1, 3],
        ),
        isFalse,
      );
    });

    test('creates and manages cursor objects', () async {
      expect(
        await _call(runtime, const ['love', 'mouse', 'isCursorSupported']),
        isTrue,
      );

      final handCursor = await _call(
        runtime,
        const ['love', 'mouse', 'getSystemCursor'],
        const <Object?>['hand'],
      );
      expect(await _callMethod(handCursor!, 'getType'), 'hand');

      await expectLater(
        _call(
          runtime,
          const ['love', 'mouse', 'getSystemCursor'],
          const <Object?>['image'],
        ),
        throwsA(isA<LuaError>()),
      );

      await _call(
        runtime,
        const ['love', 'mouse', 'setCursor'],
        <Object?>[handCursor],
      );
      final currentCursor = await _call(runtime, const [
        'love',
        'mouse',
        'getCursor',
      ]);
      expect(await _callMethod(currentCursor!, 'getType'), 'hand');

      final imageData = await _call(
        runtime,
        const ['love', 'image', 'newImageData'],
        const <Object?>[8, 8],
      );
      final imageCursor = await _call(
        runtime,
        const ['love', 'mouse', 'newCursor'],
        <Object?>[imageData!, 2, 3],
      );
      expect(await _callMethod(imageCursor!, 'getType'), 'image');

      final imageCursorWithDefaultHotspot = await _call(
        runtime,
        const ['love', 'mouse', 'newCursor'],
        <Object?>[imageData],
      );
      expect(
        await _callMethod(imageCursorWithDefaultHotspot!, 'getType'),
        'image',
      );

      final fileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[
          LoveImageData(width: 8, height: 8).encode('png'),
          'cursor.png',
        ],
      );
      final fileCursor = await _call(
        runtime,
        const ['love', 'mouse', 'newCursor'],
        <Object?>[fileData!],
      );
      expect(await _callMethod(fileCursor!, 'getType'), 'image');

      await _call(runtime, const ['love', 'mouse', 'setCursor']);
      expect(
        await _call(runtime, const ['love', 'mouse', 'getCursor']),
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

        final cursor = await _call(
          runtime,
          const ['love', 'mouse', 'newCursor'],
          const <Object?>['cursor.png', 1, 2],
        );
        expect(await _callMethod(cursor!, 'getType'), 'image');

        await expectLater(
          () => _call(
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

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object object,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  final table = object is Value ? object.raw : object;
  expect(table, isA<Map>());

  final methodValue = (table as Map)[method];
  final callable = switch (methodValue) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => methodValue,
  };
  expect(callable, isA<BuiltinFunction>());
  return _resolveCallResult(
    (callable as BuiltinFunction).call(<Object?>[object, ...args]),
  );
}

BuiltinFunction _rawFunction(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  expect(current, isA<Value>());
  final raw = (current! as Value).raw;
  expect(raw, isA<BuiltinFunction>());
  return raw as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
