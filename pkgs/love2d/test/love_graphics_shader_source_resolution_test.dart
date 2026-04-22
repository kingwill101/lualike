import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('LOVE graphics shader source resolution parity', () {
    test(
      'newShader preserves missing position or effect parse errors before backend rejection',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          _call(
            runtime,
            const ['love', 'graphics', 'newShader'],
            const <Object?>['extern number radius;'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains("missing 'position' or 'effect' function?"),
            ),
          ),
        );
      },
    );

    test(
      'validateShader preserves split-stage parse errors before backend rejection',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          _call(
            runtime,
            const ['love', 'graphics', 'validateShader'],
            <Object?>[
              false,
              '''
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return color;
}
''',
              '''
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return Texel(tex, tc);
}
''',
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                "Could not parse vertex shader code (missing 'position' function?)",
              ),
            ),
          ),
        );
      },
    );

    test(
      'validateShader preserves shader language mismatch errors before backend rejection',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await expectLater(
          _call(
            runtime,
            const ['love', 'graphics', 'validateShader'],
            <Object?>[
              false,
              '''
#pragma language glsl1
vec4 position(mat4 clipSpaceFromLocal, vec4 localPosition) {
  return clipSpaceFromLocal * localPosition;
}
''',
              '''
#pragma language glsl3
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  return color;
}
''',
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('vertex and pixel shader languages must match'),
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
  final result = _rawFunction(runtime, path).call(args);
  return result is Future<Object?> ? await result : result;
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
