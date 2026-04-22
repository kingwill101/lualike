import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';

import 'test_support/font_test_support.dart';
import 'test_support/memory_filesystem_test_support.dart';

void main() {
  group('love.font true type size validation', () {
    test(
      'newTrueTypeRasterizer rejects dpi-scaled pixel sizes that round to zero',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newTrueTypeRasterizer'],
            const <Object?>[12, 'normal', 0.01],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid TrueType font size: 0',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newFont rejects source-backed dpi-scaled pixel sizes that round to zero',
      () async {
        final veraBytes = await (await love2dVeraFontFile()).readAsBytes();
        final runtime = Interpreter();
        installLove2d(
          runtime: runtime,
          host: LoveHeadlessHost(),
          filesystemAdapter: MemoryLoveFilesystemAdapter(
            files: mountLoveTestFiles(<String, List<int>>{
              'assets/fonts/Vera.ttf': veraBytes,
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
            const ['love', 'graphics', 'newFont'],
            const <Object?>['assets/fonts/Vera.ttf', 12, 'normal', 0.01],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Invalid TrueType font size: 0',
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
