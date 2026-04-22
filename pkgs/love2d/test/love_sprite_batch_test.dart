import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('SpriteBatch', () {
    test('add/set/getters follow LOVE-like SpriteBatch behavior', () async {
      final runtime = _newRuntime();
      final image = await _newTestImage(runtime);
      final quad = await luaCall(
        runtime,
        const ['love', 'graphics', 'newQuad'],
        <Object?>[0.0, 0.0, 8.0, 8.0, image],
      );
      final spriteBatch = await luaCall(
        runtime,
        const ['love', 'graphics', 'newSpriteBatch'],
        <Object?>[image, 2],
      );

      expect(await luaCallMethod(spriteBatch!, 'getBufferSize'), 2);
      expect(await luaCallMethod(spriteBatch, 'getCount'), 0);
      expect(await luaCallMethod(spriteBatch, 'getColor'), isNull);

      await luaCallMethod(spriteBatch, 'setColor', <Object?>[
        1.0,
        0.5,
        0.25,
        0.75,
      ]);
      expect(await luaCallMethod(spriteBatch, 'getColor'), <Object?>[
        1.0,
        0.5,
        0.25,
        0.75,
      ]);

      expect(await luaCallMethod(spriteBatch, 'add', <Object?>[4.0, 6.0]), 1);
      expect(
        await luaCallMethod(spriteBatch, 'add', <Object?>[
          quad,
          10.0,
          12.0,
          0.5,
          2.0,
          3.0,
          1.0,
          2.0,
          0.1,
          0.2,
        ]),
        2,
      );

      await luaCallMethod(spriteBatch, 'setColor');
      expect(await luaCallMethod(spriteBatch, 'add', <Object?>[18.0, 20.0]), 3);
      expect(await luaCallMethod(spriteBatch, 'getColor'), isNull);
      expect(await luaCallMethod(spriteBatch, 'getCount'), 3);
      expect(await luaCallMethod(spriteBatch, 'getBufferSize'), 4);

      await luaCallMethod(spriteBatch, 'setDrawRange', <Object?>[2, 2]);
      expect(await luaCallMethod(spriteBatch, 'getDrawRange'), <Object?>[2, 2]);

      await luaCallMethod(spriteBatch, 'set', <Object?>[1, 2.0, 4.0]);
      expect(await luaCallMethod(spriteBatch, 'type'), 'SpriteBatch');
      expect(
        await luaCallMethod(spriteBatch, 'typeOf', <Object?>['Drawable']),
        isTrue,
      );
    });

    test(
      'draw records a SpriteBatch command with the active draw range',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final quad = await luaCall(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final spriteBatch = await luaCall(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 2],
        );

        await luaCallMethod(spriteBatch!, 'setColor', <Object?>[
          0.2,
          0.8,
          1.0,
          0.5,
        ]);
        await luaCallMethod(spriteBatch, 'add', <Object?>[4.0, 6.0]);
        await luaCallMethod(spriteBatch, 'add', <Object?>[quad, 10.0, 12.0]);
        await luaCallMethod(spriteBatch, 'setColor');
        await luaCallMethod(spriteBatch, 'add', <Object?>[18.0, 20.0]);
        await luaCallMethod(spriteBatch, 'setDrawRange', <Object?>[2, 2]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[spriteBatch, 30.0, 40.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveSpriteBatchCommand;
        final entries = command.spriteBatch.spritesToDraw();
        expect(entries, hasLength(2));
        expect(entries.first.quad, isNotNull);
        expect(entries.first.color, const LoveColor(0.2, 0.8, 1.0, 0.5));
        expect(entries.last.quad, isNull);
        expect(entries.last.color, isNull);
      },
    );

    test(
      'Canvas textures snapshot when a SpriteBatch draw is queued',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final canvas = await luaCall(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[16, 16],
        );
        final spriteBatch = await luaCall(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 1],
        );

        await luaCallMethod(spriteBatch!, 'setTexture', <Object?>[canvas]);
        final texture = await luaCallMethod(spriteBatch, 'getTexture');
        expect(await luaCallMethod(texture!, 'getWidth'), 16);

        await luaCallMethod(spriteBatch, 'add', <Object?>[0.0, 0.0]);
        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[spriteBatch],
        );

        final command = host.graphics.commands.single as LoveSpriteBatchCommand;
        expect(command.spriteBatch.texture, isA<LoveCanvasSnapshot>());
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
