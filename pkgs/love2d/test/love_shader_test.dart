import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('Shader', () {
    test(
      'supported shader wrappers expose LOVE-like uniform helpers and draw state',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        expect(
          await _call(runtime, const ['love', 'graphics', 'getShader']),
          isNull,
        );
        final shader = await _call(
          runtime,
          const ['love', 'graphics', 'newShader'],
          <Object?>[
            '''
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

        expect(await _callMethod(shader!, 'type'), 'Shader');
        expect(
          await _callMethod(shader, 'typeOf', <Object?>['Shader']),
          isTrue,
        );
        expect(
          await _callMethod(shader, 'typeOf', <Object?>['Object']),
          isTrue,
        );
        expect(
          await _callMethod(shader, 'hasUniform', <Object?>['innerRadius']),
          isTrue,
        );
        expect(
          await _callMethod(shader, 'hasUniform', <Object?>['outerRadius']),
          isTrue,
        );
        expect(
          await _callMethod(shader, 'hasUniform', <Object?>['missingUniform']),
          isFalse,
        );

        await _callMethod(shader, 'send', <Object?>['innerRadius', 0.75]);
        await _callMethod(shader, 'send', <Object?>[
          'center',
          _luaSeq(<Object?>[4.0, 6.0]),
        ]);
        await _callMethod(shader, 'sendColor', <Object?>[
          'colorInner',
          -0.25,
          0.5,
          1.25,
          2.0,
        ]);
        expect(await _callMethod(shader, 'getWarnings'), '');

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'setShader'],
          <Object?>[shader],
        );
        final activeShader = await _call(runtime, const [
          'love',
          'graphics',
          'getShader',
        ]);
        expect(activeShader, isNotNull);
        expect(
          await _callMethod(activeShader!, 'typeOf', <Object?>['Shader']),
          isTrue,
        );
        await _callMethod(activeShader, 'send', <Object?>['innerRadius', 0.5]);
        await _call(
          runtime,
          const ['love', 'graphics', 'rectangle'],
          <Object?>['fill', 0.0, 0.0, 8.0, 10.0],
        );
        await _call(runtime, const ['love', 'graphics', 'setShader']);
        expect(
          await _call(runtime, const ['love', 'graphics', 'getShader']),
          isNull,
        );
        await _call(
          runtime,
          const ['love', 'graphics', 'rectangle'],
          <Object?>['fill', 1.0, 2.0, 3.0, 4.0],
        );

        expect(host.graphics.commands, hasLength(2));

        final first = host.graphics.commands.first as LoveRectangleCommand;
        expect(first.shader, isNotNull);
        expect(first.shader!.kind, LoveShaderKind.radialGradient);
        expect(first.shader!.uniform('innerRadius'), 0.5);
        expect(first.shader!.uniform('center'), <Object?>[4.0, 6.0]);
        expect(first.shader!.uniform('colorInner'), <Object?>[
          0.0,
          0.5,
          1.0,
          1.0,
        ]);

        final second = host.graphics.commands.last as LoveRectangleCommand;
        expect(second.shader, isNull);
      },
    );

    test(
      'arbitrary runtime shader source throws a compatibility error',
      () async {
        final runtime = _newRuntime();

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'newShader'],
            <Object?>[
              '''
extern vec4 tint;
extern number intensity;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
  vec4 base = Texel(texture, texture_coords) * color;
  return vec4(tint.rgb * intensity, tint.a) * base;
}
''',
            ],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('cannot compile arbitrary runtime shader source'),
            ),
          ),
        );
      },
    );

    test('send and sendColor reject calls without values', () async {
      final runtime = _newRuntime();
      final shader = await _call(
        runtime,
        const ['love', 'graphics', 'newShader'],
        <Object?>[
          '''
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

      expect(
        () => _callMethod(shader!, 'send', <Object?>['innerRadius']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Shader:send expected at least 1 value to send'),
          ),
        ),
      );
      expect(
        () => _callMethod(shader!, 'sendColor', <Object?>['colorInner']),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Shader:sendColor expected at least 1 value to send'),
          ),
        ),
      );
    });

    test(
      'send rejects unknown uniforms and sendColor rejects non-color uniforms',
      () async {
        final runtime = _newRuntime();
        final shader = await _call(
          runtime,
          const ['love', 'graphics', 'newShader'],
          <Object?>[
            '''
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

        expect(
          () => _callMethod(shader!, 'send', <Object?>['missingUniform', 1.0]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains("Shader uniform 'missingUniform' does not exist."),
            ),
          ),
        );
        expect(
          () =>
              _callMethod(shader!, 'sendColor', <Object?>['innerRadius', 0.5]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('sendColor can only be used on vec3 or vec4 uniforms.'),
            ),
          ),
        );
      },
    );

    test('send normalizes matrix uniforms using LOVE matrix layouts', () async {
      final host = LoveHeadlessHost();
      final runtime = _newRuntime(host: host);
      final shader = await _call(
        runtime,
        const ['love', 'graphics', 'newShader'],
        <Object?>[
          '''
extern mat2 basis;
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

      LoveRuntimeContext.of(runtime).beginDrawFrame();
      await _call(
        runtime,
        const ['love', 'graphics', 'setShader'],
        <Object?>[shader],
      );
      await _callMethod(shader!, 'send', <Object?>[
        'basis',
        _luaSeq(<Object?>[
          _luaSeq(<Object?>[1.0, 2.0]),
          _luaSeq(<Object?>[3.0, 4.0]),
        ]),
      ]);
      await _call(
        runtime,
        const ['love', 'graphics', 'rectangle'],
        <Object?>['fill', 0.0, 0.0, 4.0, 4.0],
      );
      await _callMethod(shader, 'send', <Object?>[
        'basis',
        'column',
        _luaSeq(<Object?>[1.0, 3.0, 2.0, 4.0]),
      ]);
      await _call(
        runtime,
        const ['love', 'graphics', 'rectangle'],
        <Object?>['fill', 4.0, 0.0, 4.0, 4.0],
      );

      expect(host.graphics.commands, hasLength(2));
      final first = host.graphics.commands.first as LoveRectangleCommand;
      final second = host.graphics.commands.last as LoveRectangleCommand;
      expect(first.shader!.uniform('basis'), <Object?>[1.0, 3.0, 2.0, 4.0]);
      expect(second.shader!.uniform('basis'), <Object?>[1.0, 3.0, 2.0, 4.0]);
    });

    test('send accepts Transform payloads for mat4 uniforms', () async {
      final host = LoveHeadlessHost();
      final runtime = _newRuntime(host: host);
      final shader = await _call(
        runtime,
        const ['love', 'graphics', 'newShader'],
        <Object?>[
          '''
extern mat4 model;
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
      final transform = await _call(
        runtime,
        const ['love', 'math', 'newTransform'],
        <Object?>[2.0, 3.0],
      );

      LoveRuntimeContext.of(runtime).beginDrawFrame();
      await _call(
        runtime,
        const ['love', 'graphics', 'setShader'],
        <Object?>[shader],
      );
      await _callMethod(shader!, 'send', <Object?>['model', transform]);
      await _call(
        runtime,
        const ['love', 'graphics', 'rectangle'],
        <Object?>['fill', 0.0, 0.0, 4.0, 4.0],
      );

      expect(host.graphics.commands, hasLength(1));
      final command = host.graphics.commands.single as LoveRectangleCommand;
      expect(command.shader!.uniform('model'), <Object?>[
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        2.0,
        3.0,
        0.0,
        1.0,
      ]);
    });

    test(
      'send and sendColor reject unsupported Data object upload overloads',
      () async {
        final runtime = _newRuntime();
        final shader = await _call(
          runtime,
          const ['love', 'graphics', 'newShader'],
          <Object?>[
            '''
extern mat2 basis;
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
        final data = await _call(
          runtime,
          const ['love', 'data', 'newByteData'],
          <Object?>[16],
        );
        final shaderObject = shader!;

        expect(
          () =>
              _callMethod(shaderObject, 'send', <Object?>['innerRadius', data]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send does not support Data object uploads on the Flutter backend yet',
              ),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'send', <Object?>[
            'basis',
            'column',
            data,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:send does not support Data object uploads on the Flutter backend yet',
              ),
            ),
          ),
        );
        expect(
          () => _callMethod(shaderObject, 'sendColor', <Object?>[
            'colorInner',
            data,
          ]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains(
                'Shader:sendColor does not support Data object uploads on the Flutter backend yet',
              ),
            ),
          ),
        );
      },
    );

    test(
      'release invalidates one shader wrapper while getShader can return a fresh live wrapper',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final shader = await _call(
          runtime,
          const ['love', 'graphics', 'newShader'],
          <Object?>[
            '''
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

        await _call(
          runtime,
          const ['love', 'graphics', 'setShader'],
          <Object?>[shader],
        );

        expect(await _callMethod(shader!, 'release'), isTrue);
        expect(await _callMethod(shader, 'release'), isFalse);
        expect(
          () => _callMethod(shader, 'send', <Object?>['innerRadius', 1.5]),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              contains('Cannot use object after it has been released.'),
            ),
          ),
        );

        final activeShader = await _call(runtime, const [
          'love',
          'graphics',
          'getShader',
        ]);
        expect(activeShader, isNotNull);
        expect(activeShader, isNot(same(shader)));

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _callMethod(activeShader!, 'send', <Object?>['innerRadius', 1.5]);
        await _call(
          runtime,
          const ['love', 'graphics', 'rectangle'],
          <Object?>['fill', 0.0, 0.0, 4.0, 4.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveRectangleCommand;
        expect(command.shader!.uniform('innerRadius'), 1.5);
      },
    );

    test('type and typeOf require a live Shader receiver', () async {
      final runtime = _newRuntime();
      final shader = await _call(
        runtime,
        const ['love', 'graphics', 'newShader'],
        <Object?>[
          '''
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

      final typeMethod = _rawMethod(shader!, 'type');
      final typeOfMethod = _rawMethod(shader, 'typeOf');

      expect(
        await _resolveCallResult(typeMethod.call(<Object?>[shader])),
        'Shader',
      );
      expect(
        await _resolveCallResult(
          typeOfMethod.call(<Object?>[shader, 'Shader']),
        ),
        isTrue,
      );

      await expectLater(
        () => _resolveCallResult(typeMethod.call(const <Object?>[])),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Object:type expected a Shader at argument 1'),
          ),
        ),
      );
      await expectLater(
        () => _resolveCallResult(typeMethod.call(const <Object?>['oops'])),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Object:type expected a Shader at argument 1'),
          ),
        ),
      );
      await expectLater(
        () => _resolveCallResult(
          typeOfMethod.call(const <Object?>['oops', 'Shader']),
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Object:typeOf expected a Shader at argument 1'),
          ),
        ),
      );

      expect(await _callMethod(shader, 'release'), isTrue);
      await expectLater(
        () => _resolveCallResult(typeMethod.call(<Object?>[shader])),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Cannot use object after it has been released.'),
          ),
        ),
      );
    });
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

BuiltinFunction _rawMethod(Object receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());

  final methodValue = (table as Map)[method];
  final callable = switch (methodValue) {
    final Value value => value.raw,
    final BuiltinFunction function => function,
    _ => methodValue,
  };
  expect(callable, isA<BuiltinFunction>());
  return callable as BuiltinFunction;
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;

  if (resolved case final Value wrapped when wrapped.isMulti) {
    return (wrapped.raw as List<Object?>).map(_unwrap).toList(growable: false);
  }

  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
