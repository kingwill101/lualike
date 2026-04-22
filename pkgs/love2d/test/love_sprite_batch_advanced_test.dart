import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('SpriteBatch advanced helpers', () {
    test(
      'layer, flush, clear, and attached-attribute state survive draw snapshots',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final quad = await luaCall(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final mesh = await luaCall(
          runtime,
          const ['love', 'graphics', 'newMesh'],
          <Object?>[
            <Object?, Object?>{
              1: <Object?, Object?>{
                1: 0.0,
                2: 0.0,
                3: 0.0,
                4: 0.0,
                5: 1.0,
                6: 0.0,
                7: 0.0,
                8: 1.0,
              },
              2: <Object?, Object?>{
                1: 8.0,
                2: 0.0,
                3: 1.0,
                4: 0.0,
                5: 0.0,
                6: 1.0,
                7: 0.0,
                8: 1.0,
              },
              3: <Object?, Object?>{
                1: 8.0,
                2: 8.0,
                3: 1.0,
                4: 1.0,
                5: 0.0,
                6: 0.0,
                7: 1.0,
                8: 1.0,
              },
            },
          ],
        );
        final spriteBatch = await luaCall(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 2],
        );

        expect(
          await luaCallMethod(spriteBatch!, 'add', <Object?>[1.0, 2.0]),
          1,
        );
        expect(
          await luaCallMethod(spriteBatch, 'addLayer', <Object?>[
            3,
            quad,
            4.0,
            6.0,
          ]),
          2,
        );
        await luaCallMethod(spriteBatch, 'attachAttribute', <Object?>[
          'instanceColor',
          mesh,
        ]);
        expect(await luaCallMethod(spriteBatch, 'flush'), isNull);
        await luaCallMethod(spriteBatch, 'setLayer', <Object?>[
          1,
          5,
          8.0,
          10.0,
        ]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[spriteBatch],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveSpriteBatchCommand;
        expect(command.spriteBatch.sprites, hasLength(2));
        expect(command.spriteBatch.sprites.first.layer, 4);
        expect(command.spriteBatch.sprites.last.layer, 2);
        expect(
          command.spriteBatch.attachedAttributes.keys,
          contains('instanceColor'),
        );
        expect(
          command.spriteBatch.attachedAttributes['instanceColor']!.vertexCount,
          3,
        );

        await luaCallMethod(spriteBatch, 'clear');
        expect(await luaCallMethod(spriteBatch, 'getCount'), 0);
        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[spriteBatch],
        );
        final cleared = host.graphics.commands.single as LoveSpriteBatchCommand;
        expect(cleared.spriteBatch.spritesToDraw(), isEmpty);
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
