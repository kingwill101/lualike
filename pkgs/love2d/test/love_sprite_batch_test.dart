import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('SpriteBatch', () {
    test('add/set/getters follow LOVE-like SpriteBatch behavior', () async {
      final runtime = _newRuntime();
      final image = await _newTestImage(runtime);
      final quad = await _call(
        runtime,
        const ['love', 'graphics', 'newQuad'],
        <Object?>[0.0, 0.0, 8.0, 8.0, image],
      );
      final spriteBatch = await _call(
        runtime,
        const ['love', 'graphics', 'newSpriteBatch'],
        <Object?>[image, 2],
      );

      expect(await _callMethod(spriteBatch!, 'getBufferSize'), 2);
      expect(await _callMethod(spriteBatch, 'getCount'), 0);
      expect(await _callMethod(spriteBatch, 'getColor'), isNull);

      await _callMethod(spriteBatch, 'setColor', <Object?>[
        1.0,
        0.5,
        0.25,
        0.75,
      ]);
      expect(await _callMethod(spriteBatch, 'getColor'), <Object?>[
        1.0,
        0.5,
        0.25,
        0.75,
      ]);

      expect(await _callMethod(spriteBatch, 'add', <Object?>[4.0, 6.0]), 1);
      expect(
        await _callMethod(spriteBatch, 'add', <Object?>[
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

      await _callMethod(spriteBatch, 'setColor');
      expect(await _callMethod(spriteBatch, 'add', <Object?>[18.0, 20.0]), 3);
      expect(await _callMethod(spriteBatch, 'getColor'), isNull);
      expect(await _callMethod(spriteBatch, 'getCount'), 3);
      expect(await _callMethod(spriteBatch, 'getBufferSize'), 4);

      await _callMethod(spriteBatch, 'setDrawRange', <Object?>[2, 2]);
      expect(await _callMethod(spriteBatch, 'getDrawRange'), <Object?>[2, 2]);

      await _callMethod(spriteBatch, 'set', <Object?>[1, 2.0, 4.0]);
      expect(await _callMethod(spriteBatch, 'type'), 'SpriteBatch');
      expect(
        await _callMethod(spriteBatch, 'typeOf', <Object?>['Drawable']),
        isTrue,
      );
    });

    test(
      'draw records a SpriteBatch command with the active draw range',
      () async {
        final host = LoveHeadlessHost();
        final runtime = _newRuntime(host: host);
        final image = await _newTestImage(runtime);
        final quad = await _call(
          runtime,
          const ['love', 'graphics', 'newQuad'],
          <Object?>[0.0, 0.0, 8.0, 8.0, image],
        );
        final spriteBatch = await _call(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 2],
        );

        await _callMethod(spriteBatch!, 'setColor', <Object?>[
          0.2,
          0.8,
          1.0,
          0.5,
        ]);
        await _callMethod(spriteBatch, 'add', <Object?>[4.0, 6.0]);
        await _callMethod(spriteBatch, 'add', <Object?>[quad, 10.0, 12.0]);
        await _callMethod(spriteBatch, 'setColor');
        await _callMethod(spriteBatch, 'add', <Object?>[18.0, 20.0]);
        await _callMethod(spriteBatch, 'setDrawRange', <Object?>[2, 2]);

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
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
        final canvas = await _call(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[16, 16],
        );
        final spriteBatch = await _call(
          runtime,
          const ['love', 'graphics', 'newSpriteBatch'],
          <Object?>[image, 1],
        );

        await _callMethod(spriteBatch!, 'setTexture', <Object?>[canvas]);
        final texture = await _callMethod(spriteBatch, 'getTexture');
        expect(await _callMethod(texture!, 'getWidth'), 16);

        await _callMethod(spriteBatch, 'add', <Object?>[0.0, 0.0]);
        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
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
