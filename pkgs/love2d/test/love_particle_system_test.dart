import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('ParticleSystem', () {
    test(
      'common particle configuration and lifecycle are implemented',
      () async {
        final runtime = _newRuntime();
        final image = await _newTestImage(runtime);
        final quad = await _call(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final particleSystem = await _call(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 4],
        );

        await _callMethod(particleSystem!, 'setColors', <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.8, 3: 0.2, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.4, 3: 1.0, 4: 0.0},
        ]);
        await _callMethod(particleSystem, 'setQuads', <Object?>[quad]);
        await _callMethod(particleSystem, 'setParticleLifetime', <Object?>[
          0.5,
          1.0,
        ]);
        await _callMethod(particleSystem, 'setEmissionRate', <Object?>[12.0]);
        await _callMethod(particleSystem, 'setEmitterLifetime', <Object?>[2.0]);
        await _callMethod(particleSystem, 'setInsertMode', <Object?>['bottom']);
        await _callMethod(particleSystem, 'setPosition', <Object?>[10.0, 20.0]);
        await _callMethod(particleSystem, 'moveTo', <Object?>[18.0, 26.0]);
        await _callMethod(particleSystem, 'setDirection', <Object?>[-1.57]);
        await _callMethod(particleSystem, 'setSpread', <Object?>[0.5]);
        await _callMethod(particleSystem, 'setSpeed', <Object?>[10.0, 20.0]);
        await _callMethod(particleSystem, 'setLinearAcceleration', <Object?>[
          -5.0,
          3.0,
          8.0,
          12.0,
        ]);
        await _callMethod(particleSystem, 'setLinearDamping', <Object?>[
          0.0,
          1.2,
        ]);
        await _callMethod(particleSystem, 'setSizes', <Object?>[0.5, 1.0, 0.2]);
        await _callMethod(particleSystem, 'setSizeVariation', <Object?>[0.25]);
        await _callMethod(particleSystem, 'setRotation', <Object?>[-0.2, 0.3]);
        await _callMethod(particleSystem, 'setSpin', <Object?>[-1.0, 1.0]);
        await _callMethod(particleSystem, 'setSpinVariation', <Object?>[1.0]);
        await _callMethod(particleSystem, 'setRelativeRotation', <Object?>[
          true,
        ]);
        await _callMethod(particleSystem, 'emit', <Object?>[6]);

        expect(await _callMethod(particleSystem, 'getBufferSize'), 4);
        expect(await _callMethod(particleSystem, 'getInsertMode'), 'bottom');
        expect(await _callMethod(particleSystem, 'getEmissionRate'), 12.0);
        expect(await _callMethod(particleSystem, 'getEmitterLifetime'), 2.0);
        expect(
          await _callMethod(particleSystem, 'getParticleLifetime'),
          <Object?>[0.5, 1.0],
        );
        expect(await _callMethod(particleSystem, 'getPosition'), <Object?>[
          18.0,
          26.0,
        ]);
        expect(await _callMethod(particleSystem, 'getQuads'), isA<Map>());
        expect(await _callMethod(particleSystem, 'getCount'), 4);
        expect(
          await _callMethod(particleSystem, 'hasRelativeRotation'),
          isTrue,
        );
        expect(await _callMethod(particleSystem, 'type'), 'ParticleSystem');
        expect(
          await _callMethod(particleSystem, 'typeOf', <Object?>['Drawable']),
          isTrue,
        );

        await _callMethod(particleSystem, 'pause');
        expect(await _callMethod(particleSystem, 'isPaused'), isTrue);
        await _callMethod(particleSystem, 'start');
        expect(await _callMethod(particleSystem, 'isActive'), isTrue);
        await _callMethod(particleSystem, 'update', <Object?>[0.25]);
        expect(
          await _callMethod(particleSystem, 'getCount'),
          inInclusiveRange(1, 4),
        );

        final clone = await _callMethod(particleSystem, 'clone');
        expect(await _callMethod(clone!, 'type'), 'ParticleSystem');
        expect(await _callMethod(clone, 'isStopped'), isTrue);
        expect(await _callMethod(clone, 'getCount'), 0);

        await _callMethod(particleSystem, 'stop');
        expect(await _callMethod(particleSystem, 'isStopped'), isTrue);
        await _callMethod(particleSystem, 'reset');
        expect(await _callMethod(particleSystem, 'getCount'), 0);
      },
    );

    test(
      'draw records particle snapshots and snapshots canvas textures',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final quad = await _call(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final canvas = await _call(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[16, 16],
        );
        final particleSystem = await _call(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 8],
        );

        await _callMethod(particleSystem!, 'setTexture', <Object?>[canvas]);
        await _callMethod(particleSystem, 'setQuads', <Object?>[quad]);
        await _callMethod(particleSystem, 'setParticleLifetime', <Object?>[
          1.0,
        ]);
        await _callMethod(particleSystem, 'setEmissionRate', <Object?>[8.0]);
        await _callMethod(particleSystem, 'setDirection', <Object?>[-1.57]);
        await _callMethod(particleSystem, 'setSpread', <Object?>[0.2]);
        await _callMethod(particleSystem, 'setSizes', <Object?>[0.5, 1.0]);
        await _callMethod(particleSystem, 'setColors', <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.9, 3: 0.2, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.4, 3: 1.0, 4: 0.0},
        ]);
        await _callMethod(particleSystem, 'emit', <Object?>[3]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[particleSystem, 24.0, 36.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command =
            host.graphics.commands.single as LoveParticleSystemCommand;
        expect(command.particleSystem.texture, isA<LoveCanvasSnapshot>());
        expect(command.particleSystem.particles, hasLength(3));
        expect(command.particleSystem.particles.first.quad, isNotNull);
        expect(
          command.particleSystem.particles.first.color.a,
          lessThanOrEqualTo(1),
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

Future<Object?> _newTestImage(Interpreter runtime) async {
  final imageData = await _call(
    runtime,
    const ['love', 'image', 'newImageData'],
    <Object?>[16, 16],
  );
  return _call(
    runtime,
    const ['love', 'graphics', 'newImage'],
    <Object?>[imageData],
  );
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
