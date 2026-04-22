import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('Mesh', () {
    test(
      'mesh wrappers expose LOVE-like geometry, state, and drawable APIs',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final canvas = await luaCall(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[16, 16],
        );
        final mesh = await luaCall(
          runtime,
          const ['love', 'graphics', 'newMesh'],
          <Object?>[
            _luaSeq(<Object?>[
              _luaSeq(<Object?>[1.0, 2.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]),
              _luaSeq(<Object?>[3.0, 4.0, 0.5, 0.0, 0.0, 1.0, 0.0, 1.0]),
              _luaSeq(<Object?>[5.0, 6.0, 0.5, 1.0, 0.0, 0.0, 1.0, 1.0]),
            ]),
            'fan',
            'dynamic',
          ],
        );
        final countMesh = await luaCall(
          runtime,
          const ['love', 'graphics', 'newMesh'],
          <Object?>[2, 'points', 'stream'],
        );

        expect(await luaCallMethod(mesh!, 'type'), 'Mesh');
        expect(await luaCallMethod(mesh, 'typeOf', <Object?>['Mesh']), isTrue);
        expect(
          await luaCallMethod(mesh, 'typeOf', <Object?>['Drawable']),
          isTrue,
        );
        expect(
          await luaCallMethod(mesh, 'typeOf', <Object?>['Object']),
          isTrue,
        );

        expect(await luaCallMethod(countMesh!, 'getVertexCount'), 2);
        expect(await luaCallMethod(countMesh, 'getDrawMode'), 'points');
        expect(
          await luaCallMethod(countMesh, 'typeOf', <Object?>['Drawable']),
          isTrue,
        );

        expect(await luaCallMethod(mesh, 'getVertexCount'), 3);
        expect(await luaCallMethod(mesh, 'getDrawMode'), 'fan');
        expect(await luaCallMethod(mesh, 'getVertex', <Object?>[2]), <Object?>[
          3.0,
          4.0,
          0.5,
          0.0,
          0.0,
          1.0,
          0.0,
          1.0,
        ]);

        final vertexFormat =
            await luaCallMethod(mesh, 'getVertexFormat')
                as Map<Object?, Object?>;
        expect(vertexFormat, hasLength(3));
        expect(vertexFormat[1], <Object?, Object?>{
          1: 'VertexPosition',
          2: 'float',
          3: 2,
        });
        expect(vertexFormat[2], <Object?, Object?>{
          1: 'VertexTexCoord',
          2: 'float',
          3: 2,
        });
        expect(vertexFormat[3], <Object?, Object?>{
          1: 'VertexColor',
          2: 'byte',
          3: 4,
        });

        await luaCallMethod(mesh, 'setDrawMode', <Object?>['strip']);
        expect(await luaCallMethod(mesh, 'getDrawMode'), 'strip');

        expect(await luaCallMethod(mesh, 'getTexture'), isNull);
        await luaCallMethod(mesh, 'setTexture', <Object?>[image]);
        final imageTexture = await luaCallMethod(mesh, 'getTexture');
        expect(await luaCallMethod(imageTexture!, 'getWidth'), 16);
        expect(await luaCallMethod(imageTexture, 'getTextureType'), '2d');
        await luaCallMethod(mesh, 'setTexture', <Object?>[canvas]);
        final canvasTexture = await luaCallMethod(mesh, 'getTexture');
        expect(await luaCallMethod(canvasTexture!, 'getWidth'), 16);
        expect(await luaCallMethod(canvasTexture, 'getMSAA'), 0);
        await luaCallMethod(mesh, 'setTexture');
        expect(await luaCallMethod(mesh, 'getTexture'), isNull);

        expect(await luaCallMethod(mesh, 'getDrawRange'), isNull);
        await luaCallMethod(mesh, 'setDrawRange', <Object?>[1, 2]);
        expect(await luaCallMethod(mesh, 'getDrawRange'), <Object?>[1, 2]);
        await luaCallMethod(mesh, 'setDrawRange');
        expect(await luaCallMethod(mesh, 'getDrawRange'), isNull);

        expect(await luaCallMethod(mesh, 'getVertexMap'), isNull);
        await luaCallMethod(mesh, 'setVertexMap', <Object?>[
          _luaSeq(<Object?>[3, 1, 2]),
        ]);
        expect(await luaCallMethod(mesh, 'getVertexMap'), <Object?, Object?>{
          1: 3,
          2: 1,
          3: 2,
        });

        expect(
          await luaCallMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isTrue,
        );
        await luaCallMethod(mesh, 'setAttributeEnabled', <Object?>[
          'VertexColor',
          false,
        ]);
        expect(
          await luaCallMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isFalse,
        );
        await luaCallMethod(mesh, 'attachAttribute', <Object?>[
          'VertexColor',
          mesh,
        ]);
        expect(
          await luaCallMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isTrue,
        );
        await luaCallMethod(mesh, 'detachAttribute', <Object?>['VertexColor']);
        expect(
          await luaCallMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isFalse,
        );

        expect(
          await luaCallMethod(mesh, 'getVertexAttribute', <Object?>[1, 1]),
          <Object?>[1.0, 2.0],
        );
        expect(
          await luaCallMethod(mesh, 'getVertexAttribute', <Object?>[1, 2]),
          <Object?>[0.0, 0.0],
        );
        expect(
          await luaCallMethod(mesh, 'getVertexAttribute', <Object?>[1, 3]),
          <Object?>[1.0, 0.0, 0.0, 1.0],
        );

        await luaCallMethod(mesh, 'setVertex', <Object?>[
          2,
          7.0,
          8.0,
          0.25,
          0.75,
          0.2,
          0.3,
          0.4,
          0.5,
        ]);
        expect(await luaCallMethod(mesh, 'getVertex', <Object?>[2]), <Object?>[
          7.0,
          8.0,
          0.25,
          0.75,
          0.2,
          0.3,
          0.4,
          0.5,
        ]);

        await luaCallMethod(mesh, 'setVertexAttribute', <Object?>[
          1,
          1,
          11.0,
          12.0,
        ]);
        await luaCallMethod(mesh, 'setVertexAttribute', <Object?>[
          1,
          2,
          0.4,
          0.6,
        ]);
        await luaCallMethod(mesh, 'setVertexAttribute', <Object?>[
          1,
          3,
          0.9,
          0.8,
          0.7,
          0.6,
        ]);
        expect(
          await luaCallMethod(mesh, 'getVertexAttribute', <Object?>[1, 1]),
          <Object?>[11.0, 12.0],
        );
        expect(
          await luaCallMethod(mesh, 'getVertexAttribute', <Object?>[1, 2]),
          <Object?>[0.4, 0.6],
        );
        expect(
          await luaCallMethod(mesh, 'getVertexAttribute', <Object?>[1, 3]),
          <Object?>[0.9, 0.8, 0.7, 0.6],
        );

        await luaCallMethod(mesh, 'setDrawRange', <Object?>[1, 2]);
        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await luaCall(
          runtime,
          const ['love', 'graphics', 'draw'],
          <Object?>[mesh],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveMeshCommand;
        final drawnVertices = command.mesh.verticesForDraw();
        expect(drawnVertices, hasLength(2));
        expect(drawnVertices.first.x, 5.0);
        expect(drawnVertices.first.y, 6.0);
        expect(drawnVertices.last.x, 11.0);
        expect(drawnVertices.last.y, 12.0);

        await luaCallMethod(mesh, 'setVertexMap');
        expect(await luaCallMethod(mesh, 'getVertexMap'), isNull);

        expect(await luaCallMethod(mesh, 'flush'), isNull);
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

Map<Object?, Object?> _luaSeq(List<Object?> values) {
  return <Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  };
}
