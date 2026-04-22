import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('Shader uniform validation', () {
    test(
      'send accepts declared float, boolean, signed integer, and unsigned integer payloads',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final shader = await _call(
          runtime,
          const ['love', 'graphics', 'newShader'],
          <Object?>[
            '''
extern bool enabled;
extern ivec2 offsets;
extern uvec2 flags;
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
''',
          ],
        );

        await _callMethod(shader!, 'send', <Object?>['enabled', true]);
        await _callMethod(shader, 'send', <Object?>[
          'offsets',
          _luaSeq(<Object?>[1, -2]),
        ]);
        await _callMethod(shader, 'send', <Object?>[
          'flags',
          _luaSeq(<Object?>[3, 4]),
        ]);
        await _callMethod(shader, 'send', <Object?>[
          'center',
          _luaSeq(<Object?>[8.0, 10.0]),
        ]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setShader'],
          <Object?>[shader],
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'rectangle'],
          <Object?>['fill', 0.0, 0.0, 4.0, 4.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveRectangleCommand;
        expect(command.shader!.uniform('enabled'), isTrue);
        expect(command.shader!.uniform('offsets'), <Object?>[1, -2]);
        expect(command.shader!.uniform('flags'), <Object?>[3, 4]);
        expect(command.shader!.uniform('center'), <Object?>[8.0, 10.0]);
      },
    );

    test(
      'send rejects incompatible payload shapes and unsupported sampler uploads',
      () async {
        final runtime = _newRuntime();
        final shader = await _call(
          runtime,
          const ['love', 'graphics', 'newShader'],
          <Object?>[
            '''
extern Image mask;
extern bool enabled;
extern ivec2 offsets;
extern uvec2 flags;
extern number innerRadius;
extern number outerRadius;
extern vec2 center;
extern vec4 colorInner;
extern vec4 colorOuter;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  number dist = distance(screen_coords, center);
  number t = smoothstep(innerRadius, outerRadius, dist);
  return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
}
''',
          ],
        );
        final shaderObject = shader!;

        expect(
          () => _callMethod(shaderObject, 'send', <Object?>[
            'innerRadius',
            _luaSeq(<Object?>[1.0]),
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send expected a number for shader uniform values',
              ),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'send', <Object?>['center', 4.0]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Shader:send expected a table with 2 components'),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'send', <Object?>['enabled', 1]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send expected a boolean for shader uniform values',
              ),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'send', <Object?>[
            'offsets',
            _luaSeq(<Object?>[1.5, 2]),
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send expected an integer for shader uniform values',
              ),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'send', <Object?>[
            'flags',
            _luaSeq(<Object?>[-1, 2]),
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send expected a non-negative integer for unsigned shader uniform values',
              ),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'send', <Object?>['mask', 1]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send does not support sampler uniform uploads on the Flutter backend yet',
              ),
            ),
          ),
        );
      },
    );
  });
}

Interpreter _newRuntime({LoveHost? host}) {
  final runtime = Interpreter();
  installLove2d(runtime: runtime, host: host ?? LoveHeadlessHost());
  return runtime;
}

Map<Object?, Object?> _luaSeq(List<Object?> values) {
  return <Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  };
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
