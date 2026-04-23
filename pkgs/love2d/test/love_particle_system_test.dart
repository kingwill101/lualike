import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('ParticleSystem', () {
    test(
      'common particle configuration and lifecycle are implemented',
      () async {
        final runtime = _newRuntime();
        final image = await _newTestImage(runtime);
        final quad = await luaCall(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final particleSystem = await luaCall(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 4],
        );

        await luaCallMethod(particleSystem!, 'setColors', <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.8, 3: 0.2, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.4, 3: 1.0, 4: 0.0},
        ]);
        await luaCallMethod(particleSystem, 'setQuads', <Object?>[quad]);
        await luaCallMethod(particleSystem, 'setParticleLifetime', <Object?>[
          0.5,
          1.0,
        ]);
        await luaCallMethod(particleSystem, 'setEmissionRate', <Object?>[12.0]);
        await luaCallMethod(particleSystem, 'setEmitterLifetime', <Object?>[
          2.0,
        ]);
        await luaCallMethod(particleSystem, 'setInsertMode', <Object?>[
          'bottom',
        ]);
        await luaCallMethod(particleSystem, 'setPosition', <Object?>[
          10.0,
          20.0,
        ]);
        await luaCallMethod(particleSystem, 'moveTo', <Object?>[18.0, 26.0]);
        await luaCallMethod(particleSystem, 'setDirection', <Object?>[-1.57]);
        await luaCallMethod(particleSystem, 'setSpread', <Object?>[0.5]);
        await luaCallMethod(particleSystem, 'setSpeed', <Object?>[10.0, 20.0]);
        await luaCallMethod(particleSystem, 'setLinearAcceleration', <Object?>[
          -5.0,
          3.0,
          8.0,
          12.0,
        ]);
        await luaCallMethod(particleSystem, 'setLinearDamping', <Object?>[
          0.0,
          1.2,
        ]);
        await luaCallMethod(particleSystem, 'setSizes', <Object?>[
          0.5,
          1.0,
          0.2,
        ]);
        await luaCallMethod(particleSystem, 'setSizeVariation', <Object?>[
          0.25,
        ]);
        await luaCallMethod(particleSystem, 'setRotation', <Object?>[
          -0.2,
          0.3,
        ]);
        await luaCallMethod(particleSystem, 'setSpin', <Object?>[-1.0, 1.0]);
        await luaCallMethod(particleSystem, 'setSpinVariation', <Object?>[1.0]);
        await luaCallMethod(particleSystem, 'setRelativeRotation', <Object?>[
          true,
        ]);
        await luaCallMethod(particleSystem, 'emit', <Object?>[6]);

        expect(await luaCallMethod(particleSystem, 'getBufferSize'), 4);
        expect(await luaCallMethod(particleSystem, 'getInsertMode'), 'bottom');
        expect(await luaCallMethod(particleSystem, 'getEmissionRate'), 12.0);
        expect(await luaCallMethod(particleSystem, 'getEmitterLifetime'), 2.0);
        expect(
          await luaCallMethod(particleSystem, 'getParticleLifetime'),
          <Object?>[0.5, 1.0],
        );
        expect(await luaCallMethod(particleSystem, 'getPosition'), <Object?>[
          18.0,
          26.0,
        ]);
        expect(await luaCallMethod(particleSystem, 'getQuads'), isA<Map>());
        expect(await luaCallMethod(particleSystem, 'getCount'), 4);
        expect(
          await luaCallMethod(particleSystem, 'hasRelativeRotation'),
          isTrue,
        );
        expect(await luaCallMethod(particleSystem, 'type'), 'ParticleSystem');
        expect(
          await luaCallMethod(particleSystem, 'typeOf', <Object?>['Drawable']),
          isTrue,
        );

        await luaCallMethod(particleSystem, 'pause');
        expect(await luaCallMethod(particleSystem, 'isPaused'), isTrue);
        await luaCallMethod(particleSystem, 'start');
        expect(await luaCallMethod(particleSystem, 'isActive'), isTrue);
        await luaCallMethod(particleSystem, 'update', <Object?>[0.25]);
        expect(
          await luaCallMethod(particleSystem, 'getCount'),
          inInclusiveRange(1, 4),
        );

        final clone = await luaCallMethod(particleSystem, 'clone');
        expect(await luaCallMethod(clone!, 'type'), 'ParticleSystem');
        expect(await luaCallMethod(clone, 'isStopped'), isTrue);
        expect(await luaCallMethod(clone, 'getCount'), 0);

        await luaCallMethod(particleSystem, 'stop');
        expect(await luaCallMethod(particleSystem, 'isStopped'), isTrue);
        await luaCallMethod(particleSystem, 'reset');
        expect(await luaCallMethod(particleSystem, 'getCount'), 0);
      },
    );

    test(
      'draw records particle snapshots and snapshots canvas textures',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final quad = await luaCall(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final canvas = await luaCall(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[16, 16],
        );
        final particleSystem = await luaCall(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 8],
        );

        await luaCallMethod(particleSystem!, 'setTexture', <Object?>[canvas]);
        await luaCallMethod(particleSystem, 'setQuads', <Object?>[quad]);
        await luaCallMethod(particleSystem, 'setParticleLifetime', <Object?>[
          1.0,
        ]);
        await luaCallMethod(particleSystem, 'setEmissionRate', <Object?>[8.0]);
        await luaCallMethod(particleSystem, 'setDirection', <Object?>[-1.57]);
        await luaCallMethod(particleSystem, 'setSpread', <Object?>[0.2]);
        await luaCallMethod(particleSystem, 'setSizes', <Object?>[0.5, 1.0]);
        await luaCallMethod(particleSystem, 'setColors', <Object?>[
          <Object?, Object?>{1: 1.0, 2: 0.9, 3: 0.2, 4: 1.0},
          <Object?, Object?>{1: 0.2, 2: 0.4, 3: 1.0, 4: 0.0},
        ]);
        await luaCallMethod(particleSystem, 'emit', <Object?>[3]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
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
