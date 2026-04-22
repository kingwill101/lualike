import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('ParticleSystem state accessors', () {
    test(
      'extended particle-system getters and setters mirror configured state',
      () async {
        final runtime = _newRuntime();
        final image = await _newTestImage(runtime);
        final canvas = await _call(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[12, 12],
        );
        final quad = await _call(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 6.0, 6.0, image],
        );
        final particleSystem = await _call(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 4],
        );

        expect(await _callMethod(particleSystem!, 'getBufferSize'), 4);
        await _callMethod(particleSystem, 'setBufferSize', <Object?>[6]);
        expect(await _callMethod(particleSystem, 'getBufferSize'), 6);

        await _callMethod(particleSystem, 'setColors', <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.8, 3: 0.1, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.3, 3: 0.9, 4: 0.4},
        ]);
        expect(await _callMethod(particleSystem, 'getColors'), <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.8, 3: 0.1, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.3, 3: 0.9, 4: 0.4},
        ]);

        await _callMethod(particleSystem, 'setEmissionArea', <Object?>[
          'ellipse',
          3.0,
          4.0,
          0.5,
          true,
        ]);
        expect(await _callMethod(particleSystem, 'getEmissionArea'), <Object?>[
          'ellipse',
          3.0,
          4.0,
          0.5,
          true,
        ]);

        await _callMethod(particleSystem, 'setDirection', <Object?>[1.25]);
        expect(await _callMethod(particleSystem, 'getDirection'), 1.25);

        await _callMethod(particleSystem, 'setLinearAcceleration', <Object?>[
          -1.0,
          2.0,
          3.0,
          4.0,
        ]);
        expect(
          await _callMethod(particleSystem, 'getLinearAcceleration'),
          <Object?>[-1.0, 2.0, 3.0, 4.0],
        );

        await _callMethod(particleSystem, 'setLinearDamping', <Object?>[
          0.2,
          0.7,
        ]);
        expect(await _callMethod(particleSystem, 'getLinearDamping'), <Object?>[
          0.2,
          0.7,
        ]);

        await _callMethod(particleSystem, 'setOffset', <Object?>[2.5, 3.5]);
        expect(await _callMethod(particleSystem, 'getOffset'), <Object?>[
          2.5,
          3.5,
        ]);

        await _callMethod(particleSystem, 'setParticleLifetime', <Object?>[
          1.0,
          2.0,
        ]);
        expect(
          await _callMethod(particleSystem, 'getParticleLifetime'),
          <Object?>[1.0, 2.0],
        );

        await _callMethod(particleSystem, 'setPosition', <Object?>[10.0, 20.0]);
        expect(await _callMethod(particleSystem, 'getPosition'), <Object?>[
          10.0,
          20.0,
        ]);

        await _callMethod(particleSystem, 'setQuads', <Object?>[quad]);
        final quads =
            await _callMethod(particleSystem, 'getQuads')
                as Map<Object?, Object?>;
        expect(quads, hasLength(1));
        expect(await _callMethod(quads[1]!, 'getTextureDimensions'), <Object?>[
          16.0,
          16.0,
        ]);

        await _callMethod(particleSystem, 'setRadialAcceleration', <Object?>[
          -2.0,
          5.0,
        ]);
        expect(
          await _callMethod(particleSystem, 'getRadialAcceleration'),
          <Object?>[-2.0, 5.0],
        );

        await _callMethod(particleSystem, 'setRotation', <Object?>[0.1, 0.9]);
        expect(await _callMethod(particleSystem, 'getRotation'), <Object?>[
          0.1,
          0.9,
        ]);

        await _callMethod(particleSystem, 'setSizeVariation', <Object?>[0.6]);
        expect(await _callMethod(particleSystem, 'getSizeVariation'), 0.6);

        await _callMethod(particleSystem, 'setSizes', <Object?>[
          0.5,
          1.5,
          0.75,
        ]);
        expect(await _callMethod(particleSystem, 'getSizes'), <Object?>[
          0.5,
          1.5,
          0.75,
        ]);

        await _callMethod(particleSystem, 'setSpeed', <Object?>[10.0, 12.0]);
        expect(await _callMethod(particleSystem, 'getSpeed'), <Object?>[
          10.0,
          12.0,
        ]);

        await _callMethod(particleSystem, 'setSpin', <Object?>[-1.0, 1.0]);
        await _callMethod(particleSystem, 'setSpinVariation', <Object?>[0.4]);
        expect(await _callMethod(particleSystem, 'getSpin'), <Object?>[
          -1.0,
          1.0,
          0.4,
        ]);
        expect(await _callMethod(particleSystem, 'getSpinVariation'), 0.4);

        await _callMethod(particleSystem, 'setSpread', <Object?>[0.3]);
        expect(await _callMethod(particleSystem, 'getSpread'), 0.3);

        await _callMethod(
          particleSystem,
          'setTangentialAcceleration',
          <Object?>[-3.0, 6.0],
        );
        expect(
          await _callMethod(particleSystem, 'getTangentialAcceleration'),
          <Object?>[-3.0, 6.0],
        );

        await _callMethod(particleSystem, 'setTexture', <Object?>[canvas]);
        final texture = await _callMethod(particleSystem, 'getTexture');
        expect(await _callMethod(texture!, 'getWidth'), 12);
        expect(await _callMethod(texture, 'getMSAA'), 0);

        await _callMethod(particleSystem, 'emit', <Object?>[5]);
        expect(await _callMethod(particleSystem, 'getCount'), 5);
        await _callMethod(particleSystem, 'setBufferSize', <Object?>[2]);
        expect(await _callMethod(particleSystem, 'getBufferSize'), 2);
        expect(await _callMethod(particleSystem, 'getCount'), 2);
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
