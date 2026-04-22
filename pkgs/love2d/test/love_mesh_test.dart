import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('Mesh', () {
    test(
      'mesh wrappers expose LOVE-like geometry, state, and drawable APIs',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final canvas = await _call(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[16, 16],
        );
        final mesh = await _call(
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
        final countMesh = await _call(
          runtime,
          const ['love', 'graphics', 'newMesh'],
          <Object?>[2, 'points', 'stream'],
        );

        expect(await _callMethod(mesh!, 'type'), 'Mesh');
        expect(await _callMethod(mesh, 'typeOf', <Object?>['Mesh']), isTrue);
        expect(
          await _callMethod(mesh, 'typeOf', <Object?>['Drawable']),
          isTrue,
        );
        expect(await _callMethod(mesh, 'typeOf', <Object?>['Object']), isTrue);

        expect(await _callMethod(countMesh!, 'getVertexCount'), 2);
        expect(await _callMethod(countMesh, 'getDrawMode'), 'points');
        expect(
          await _callMethod(countMesh, 'typeOf', <Object?>['Drawable']),
          isTrue,
        );

        expect(await _callMethod(mesh, 'getVertexCount'), 3);
        expect(await _callMethod(mesh, 'getDrawMode'), 'fan');
        expect(await _callMethod(mesh, 'getVertex', <Object?>[2]), <Object?>[
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
            await _callMethod(mesh, 'getVertexFormat') as Map<Object?, Object?>;
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

        await _callMethod(mesh, 'setDrawMode', <Object?>['strip']);
        expect(await _callMethod(mesh, 'getDrawMode'), 'strip');

        expect(await _callMethod(mesh, 'getTexture'), isNull);
        await _callMethod(mesh, 'setTexture', <Object?>[image]);
        final imageTexture = await _callMethod(mesh, 'getTexture');
        expect(await _callMethod(imageTexture!, 'getWidth'), 16);
        expect(await _callMethod(imageTexture, 'getTextureType'), '2d');
        await _callMethod(mesh, 'setTexture', <Object?>[canvas]);
        final canvasTexture = await _callMethod(mesh, 'getTexture');
        expect(await _callMethod(canvasTexture!, 'getWidth'), 16);
        expect(await _callMethod(canvasTexture, 'getMSAA'), 0);
        await _callMethod(mesh, 'setTexture');
        expect(await _callMethod(mesh, 'getTexture'), isNull);

        expect(await _callMethod(mesh, 'getDrawRange'), isNull);
        await _callMethod(mesh, 'setDrawRange', <Object?>[1, 2]);
        expect(await _callMethod(mesh, 'getDrawRange'), <Object?>[1, 2]);
        await _callMethod(mesh, 'setDrawRange');
        expect(await _callMethod(mesh, 'getDrawRange'), isNull);

        expect(await _callMethod(mesh, 'getVertexMap'), isNull);
        await _callMethod(mesh, 'setVertexMap', <Object?>[
          _luaSeq(<Object?>[3, 1, 2]),
        ]);
        expect(await _callMethod(mesh, 'getVertexMap'), <Object?, Object?>{
          1: 3,
          2: 1,
          3: 2,
        });

        expect(
          await _callMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isTrue,
        );
        await _callMethod(mesh, 'setAttributeEnabled', <Object?>[
          'VertexColor',
          false,
        ]);
        expect(
          await _callMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isFalse,
        );
        await _callMethod(mesh, 'attachAttribute', <Object?>[
          'VertexColor',
          mesh,
        ]);
        expect(
          await _callMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isTrue,
        );
        await _callMethod(mesh, 'detachAttribute', <Object?>['VertexColor']);
        expect(
          await _callMethod(mesh, 'isAttributeEnabled', <Object?>[
            'VertexColor',
          ]),
          isFalse,
        );

        expect(
          await _callMethod(mesh, 'getVertexAttribute', <Object?>[1, 1]),
          <Object?>[1.0, 2.0],
        );
        expect(
          await _callMethod(mesh, 'getVertexAttribute', <Object?>[1, 2]),
          <Object?>[0.0, 0.0],
        );
        expect(
          await _callMethod(mesh, 'getVertexAttribute', <Object?>[1, 3]),
          <Object?>[1.0, 0.0, 0.0, 1.0],
        );

        await _callMethod(mesh, 'setVertex', <Object?>[
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
        expect(await _callMethod(mesh, 'getVertex', <Object?>[2]), <Object?>[
          7.0,
          8.0,
          0.25,
          0.75,
          0.2,
          0.3,
          0.4,
          0.5,
        ]);

        await _callMethod(mesh, 'setVertexAttribute', <Object?>[
          1,
          1,
          11.0,
          12.0,
        ]);
        await _callMethod(mesh, 'setVertexAttribute', <Object?>[
          1,
          2,
          0.4,
          0.6,
        ]);
        await _callMethod(mesh, 'setVertexAttribute', <Object?>[
          1,
          3,
          0.9,
          0.8,
          0.7,
          0.6,
        ]);
        expect(
          await _callMethod(mesh, 'getVertexAttribute', <Object?>[1, 1]),
          <Object?>[11.0, 12.0],
        );
        expect(
          await _callMethod(mesh, 'getVertexAttribute', <Object?>[1, 2]),
          <Object?>[0.4, 0.6],
        );
        expect(
          await _callMethod(mesh, 'getVertexAttribute', <Object?>[1, 3]),
          <Object?>[0.9, 0.8, 0.7, 0.6],
        );

        await _callMethod(mesh, 'setDrawRange', <Object?>[1, 2]);
        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
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

        await _callMethod(mesh, 'setVertexMap');
        expect(await _callMethod(mesh, 'getVertexMap'), isNull);

        expect(await _callMethod(mesh, 'flush'), isNull);
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
