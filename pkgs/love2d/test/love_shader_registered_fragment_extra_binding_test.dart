import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/flame/love_flame_harness_renderer.dart';

const String _registeredFragmentHelperSource = '''
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform float iTime;
out vec4 fragColor;

void main() {
  fragColor = vec4(iTime / 10.0, 0.0, 0.0, 1.0);
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Registered fragment shader extra binding', () {
    test(
      '_newRegisteredFragmentShader accepts loadable Flutter fragment assets',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveFlameHarnessGame().host);

        final result = await _call(
          runtime,
          const ['love', 'graphics', '_newRegisteredFragmentShader'],
          const <Object?>[
            'test_assets/shaders/runtime_effect_solid_color.frag',
            _registeredFragmentHelperSource,
          ],
        );

        expect(result, isA<Value>());
      },
    );

    test(
      '_newRegisteredFragmentShader rejects missing Flutter fragment assets',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveFlameHarnessGame().host);

        await expectLater(
          _call(
            runtime,
            const ['love', 'graphics', '_newRegisteredFragmentShader'],
            const <Object?>[
              'test_assets/shaders/does_not_exist.frag',
              _registeredFragmentHelperSource,
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Could not load Flutter fragment shader asset "test_assets/shaders/does_not_exist.frag"',
              ),
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
