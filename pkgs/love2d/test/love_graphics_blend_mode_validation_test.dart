import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart'
    show BuiltinFunction, LuaError, LuaRuntime, Value;
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics.setBlendMode', () {
    test(
      'requires premultiplied alpha for multiply, lighten, and darken',
      () async {
        final runtime = createLuaLikeTestRuntime();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        for (final mode in const <String>['multiply', 'lighten', 'darken']) {
          expect(
            () => _call(
              runtime,
              const ['love', 'graphics', 'setBlendMode'],
              <Object?>[mode, 'alphamultiply'],
            ),
            throwsA(
              isA<LuaError>().having(
                (error) => error.message,
                'message',
                "The '$mode' blend mode must be used with premultiplied alpha.",
              ),
            ),
          );
        }
      },
    );

    test('accepts premultiplied alpha for multiply', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      await _call(
        runtime,
        const ['love', 'graphics', 'setBlendMode'],
        const <Object?>['multiply', 'premultiplied'],
      );

      expect(
        await _call(runtime, const ['love', 'graphics', 'getBlendMode']),
        <Object?>['multiply', 'premultiplied'],
      );
    });
  });
}

Future<Object?> _call(
  LuaRuntime runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

BuiltinFunction _rawFunction(LuaRuntime runtime, List<String> path) {
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
    return (wrapped.raw as List<Object?>)
        .map<Object?>((entry) => entry is Value ? entry.unwrap() : entry)
        .toList(growable: false);
  }

  return resolved is Value ? resolved.unwrap() : resolved;
}
