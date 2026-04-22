import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.font image validation', () {
    test(
      'newImageRasterizer uses LOVE error text for non-rgba image data',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[2, 2, 'r8'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'font', 'newImageRasterizer'],
            <Object?>[imageData, 'A', 0, 1.0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in Image Fonts!',
            ),
          ),
        );
      },
    );

    test(
      'graphics.newImageFont uses LOVE error text for non-rgba image data',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[2, 2, 'r8'],
        );

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newImageFont'],
            <Object?>[imageData, 'A', 0],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              'Only 32-bit RGBA images are supported in Image Fonts!',
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
