import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

import 'test_support/lua_api_test_helpers.dart';

const String _desaturationTintShaderSource = '''
extern vec4 tint;
extern number strength;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
{
  color = Texel(texture, tc);
  number luma = dot(vec3(0.299f, 0.587f, 0.114f), color.rgb);
  return mix(color, tint * luma, strength);
}
''';

void main() {
  group('Shader desaturation tint subset', () {
    test('newShader accepts the supported desaturation tint subset', () async {
      final runtime = LoveScriptRuntime(host: LoveHeadlessHost());

      await runtime.execute('''
local shader = love.graphics.newShader([[
$_desaturationTintShaderSource
]])

shader:send('tint', {1, 1, 1, 1})
shader:send('strength', 0.5)
love.graphics.setShader(shader)
love.graphics.rectangle('fill', 0, 0, 8, 8)
''');

      final shader = runtime.context.graphics.currentShader;
      expect(shader, isNotNull);
      expect(shader!.kind, LoveShaderKind.desaturationTint);
      expect(shader.uniform('strength'), 0.5);
      expect(shader.uniform('tint'), <Object?>[1, 1, 1, 1]);
    });

    test('validateShader reports success for the supported subset', () async {
      final runtime = createLuaLikeTestRuntime();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final result = await _call(
        runtime,
        const ['love', 'graphics', 'validateShader'],
        <Object?>[false, _desaturationTintShaderSource],
      );

      expect(result, isTrue);
    });
  });
}

Future<Object?> _call(
  LuaRuntime runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  final result = _rawFunction(runtime, path).call(args);
  return result is Future<Object?> ? await result : result;
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
