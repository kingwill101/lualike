import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('ParticleSystem state accessors', () {
    test(
      'extended particle-system getters and setters mirror configured state',
      () async {
        final runtime = _newRuntime();
        final image = await _newTestImage(runtime);
        final canvas = await luaCall(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[12, 12],
        );
        final quad = await luaCall(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 6.0, 6.0, image],
        );
        final particleSystem = await luaCall(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 4],
        );

        expect(await luaCallMethod(particleSystem!, 'getBufferSize'), 4);
        await luaCallMethod(particleSystem, 'setBufferSize', <Object?>[6]);
        expect(await luaCallMethod(particleSystem, 'getBufferSize'), 6);

        await luaCallMethod(particleSystem, 'setColors', <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.8, 3: 0.1, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.3, 3: 0.9, 4: 0.4},
        ]);
        expect(await luaCallMethod(particleSystem, 'getColors'), <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.8, 3: 0.1, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.3, 3: 0.9, 4: 0.4},
        ]);

        await luaCallMethod(particleSystem, 'setEmissionArea', <Object?>[
          'ellipse',
          3.0,
          4.0,
          0.5,
          true,
        ]);
        expect(
          await luaCallMethod(particleSystem, 'getEmissionArea'),
          <Object?>['ellipse', 3.0, 4.0, 0.5, true],
        );

        await luaCallMethod(particleSystem, 'setDirection', <Object?>[1.25]);
        expect(await luaCallMethod(particleSystem, 'getDirection'), 1.25);

        await luaCallMethod(particleSystem, 'setLinearAcceleration', <Object?>[
          -1.0,
          2.0,
          3.0,
          4.0,
        ]);
        expect(
          await luaCallMethod(particleSystem, 'getLinearAcceleration'),
          <Object?>[-1.0, 2.0, 3.0, 4.0],
        );

        await luaCallMethod(particleSystem, 'setLinearDamping', <Object?>[
          0.2,
          0.7,
        ]);
        expect(
          await luaCallMethod(particleSystem, 'getLinearDamping'),
          <Object?>[0.2, 0.7],
        );

        await luaCallMethod(particleSystem, 'setOffset', <Object?>[2.5, 3.5]);
        expect(await luaCallMethod(particleSystem, 'getOffset'), <Object?>[
          2.5,
          3.5,
        ]);

        await luaCallMethod(particleSystem, 'setParticleLifetime', <Object?>[
          1.0,
          2.0,
        ]);
        expect(
          await luaCallMethod(particleSystem, 'getParticleLifetime'),
          <Object?>[1.0, 2.0],
        );

        await luaCallMethod(particleSystem, 'setPosition', <Object?>[
          10.0,
          20.0,
        ]);
        expect(await luaCallMethod(particleSystem, 'getPosition'), <Object?>[
          10.0,
          20.0,
        ]);

        await luaCallMethod(particleSystem, 'setQuads', <Object?>[quad]);
        final quads =
            await luaCallMethod(particleSystem, 'getQuads')
                as Map<Object?, Object?>;
        expect(quads, hasLength(1));
        expect(
          await luaCallMethod(quads[1]!, 'getTextureDimensions'),
          <Object?>[16.0, 16.0],
        );

        await luaCallMethod(particleSystem, 'setRadialAcceleration', <Object?>[
          -2.0,
          5.0,
        ]);
        expect(
          await luaCallMethod(particleSystem, 'getRadialAcceleration'),
          <Object?>[-2.0, 5.0],
        );

        await luaCallMethod(particleSystem, 'setRotation', <Object?>[0.1, 0.9]);
        expect(await luaCallMethod(particleSystem, 'getRotation'), <Object?>[
          0.1,
          0.9,
        ]);

        await luaCallMethod(particleSystem, 'setSizeVariation', <Object?>[0.6]);
        expect(await luaCallMethod(particleSystem, 'getSizeVariation'), 0.6);

        await luaCallMethod(particleSystem, 'setSizes', <Object?>[
          0.5,
          1.5,
          0.75,
        ]);
        expect(await luaCallMethod(particleSystem, 'getSizes'), <Object?>[
          0.5,
          1.5,
          0.75,
        ]);

        await luaCallMethod(particleSystem, 'setSpeed', <Object?>[10.0, 12.0]);
        expect(await luaCallMethod(particleSystem, 'getSpeed'), <Object?>[
          10.0,
          12.0,
        ]);

        await luaCallMethod(particleSystem, 'setSpin', <Object?>[-1.0, 1.0]);
        await luaCallMethod(particleSystem, 'setSpinVariation', <Object?>[0.4]);
        expect(await luaCallMethod(particleSystem, 'getSpin'), <Object?>[
          -1.0,
          1.0,
          0.4,
        ]);
        expect(await luaCallMethod(particleSystem, 'getSpinVariation'), 0.4);

        await luaCallMethod(particleSystem, 'setSpread', <Object?>[0.3]);
        expect(await luaCallMethod(particleSystem, 'getSpread'), 0.3);

        await luaCallMethod(
          particleSystem,
          'setTangentialAcceleration',
          <Object?>[-3.0, 6.0],
        );
        expect(
          await luaCallMethod(particleSystem, 'getTangentialAcceleration'),
          <Object?>[-3.0, 6.0],
        );

        await luaCallMethod(particleSystem, 'setTexture', <Object?>[canvas]);
        final texture = await luaCallMethod(particleSystem, 'getTexture');
        expect(await luaCallMethod(texture!, 'getWidth'), 12);
        expect(await luaCallMethod(texture, 'getMSAA'), 0);

        await luaCallMethod(particleSystem, 'emit', <Object?>[5]);
        expect(await luaCallMethod(particleSystem, 'getCount'), 5);
        await luaCallMethod(particleSystem, 'setBufferSize', <Object?>[2]);
        expect(await luaCallMethod(particleSystem, 'getBufferSize'), 2);
        expect(await luaCallMethod(particleSystem, 'getCount'), 2);
      },
    );
  });
}

LuaRuntime _newRuntime({LoveHost? host}) {
  final runtime = createLuaLikeTestRuntime();
  installLove2d(runtime: runtime, host: host ?? LoveHeadlessHost());
  return runtime;
}

Future<Object?> _newTestImage(LuaRuntime runtime) async {
  final imageData = await luaCall(
    runtime,
    const ['love', 'image', 'newImageData'],
    <Object?>[16, 16],
  );
  return luaCall(
    runtime,
    const ['love', 'graphics', 'newImage'],
    <Object?>[imageData],
  );
}
