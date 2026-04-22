import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('SpriteBatch advanced helpers', () {
    test(
      'layer, flush, clear, and attached-attribute state survive draw snapshots',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final quad = await _call(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final mesh = await _call(
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
        final spriteBatch = await _call(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 2],
        );

        expect(await _callMethod(spriteBatch!, 'add', <Object?>[1.0, 2.0]), 1);
        expect(
          await _callMethod(spriteBatch, 'addLayer', <Object?>[
            3,
            quad,
            4.0,
            6.0,
          ]),
          2,
        );
        await _callMethod(spriteBatch, 'attachAttribute', <Object?>[
          'instanceColor',
          mesh,
        ]);
        expect(await _callMethod(spriteBatch, 'flush'), isNull);
        await _callMethod(spriteBatch, 'setLayer', <Object?>[1, 5, 8.0, 10.0]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
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

        await _callMethod(spriteBatch, 'clear');
        expect(await _callMethod(spriteBatch, 'getCount'), 0);
        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
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
