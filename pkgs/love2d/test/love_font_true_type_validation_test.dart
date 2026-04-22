import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font true type validation', () {
    test('newTrueTypeRasterizer rejects non-font FileData inputs', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final fileData = await _call(
        runtime,
        const ['love', 'filesystem', 'newFileData'],
        <Object?>[_notAFontBytes, 'fake.ttf'],
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          <Object?>[fileData, 16],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Invalid font file: fake.ttf',
          ),
        ),
      );
    });

    test('newTrueTypeRasterizer rejects non-font filenames', () async {
      final runtime = Interpreter();
      installLove2d(
        runtime: runtime,
        host: LoveHeadlessHost(),
        filesystemAdapter: MemoryLoveFilesystemAdapter(
          files: mountLoveTestFiles(<String, List<int>>{
            'assets/fonts/not_a_font.ttf': _notAFontBytes,
          }),
        ),
      );
      expect(
        LoveFilesystemState.of(runtime).setSource(loveTestMountedSourceRoot),
        isTrue,
      );

      await expectLater(
        () => _call(
          runtime,
          const ['love', 'font', 'newTrueTypeRasterizer'],
          const <Object?>['assets/fonts/not_a_font.ttf', 16],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            'Invalid font file: assets/fonts/not_a_font.ttf',
          ),
        ),
      );
    });

    test(
      'newRasterizer rejects invalid loaded font data with LOVE text',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_notAFontBytes, 'fake.ttf'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newRasterizer'],
            <Object?>[fileData],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: fake.ttf',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects invalid loaded font data with LOVE text',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final fileData = await _call(
          runtime,
          const ['love', 'filesystem', 'newFileData'],
          <Object?>[_notAFontBytes, 'fake.ttf'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newFont'],
            <Object?>[fileData, 16],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid font file: fake.ttf',
            ),
          ),
        );
      },
    );
  });
}

final List<int> _notAFontBytes = utf8.encode('not a true type font');

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
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
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
