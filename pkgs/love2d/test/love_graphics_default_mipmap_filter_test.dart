import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics default mipmap filter', () {
    test(
      'source-backed module methods are installed and reset with graphics state',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final love = runtime.getCurrentEnv().get('love')! as Value;
        final graphics =
            (love.raw as Map<Object?, Object?>)['graphics']! as Value;
        final graphicsTable = graphics.raw as Map<Object?, Object?>;

        expect(graphicsTable.containsKey('getDefaultMipmapFilter'), isTrue);
        expect(graphicsTable.containsKey('setDefaultMipmapFilter'), isTrue);

        expect(
          await _call(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>['linear', 0.0],
        );

        await _call(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>['nearest', 0.5],
        );
        expect(
          await _call(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>['nearest', 0.5],
        );

        await _call(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>[null, 0.75],
        );
        expect(
          await _call(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>[null, 0.75],
        );

        await _call(runtime, const ['love', 'graphics', 'reset']);
        expect(
          await _call(runtime, const [
            'love',
            'graphics',
            'getDefaultMipmapFilter',
          ]),
          <Object?>['linear', 0.0],
        );
      },
    );

    test(
      'new mipmapped images inherit the current default mipmap filter',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await _call(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>['nearest', 0.5],
        );

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[8, 4],
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[
            imageData,
            Value(<Object?, Object?>{'mipmaps': true}),
          ],
        );

        expect(await _callMethod(image, 'getMipmapFilter'), <Object?>[
          'nearest',
          0.5,
        ]);
      },
    );

    test(
      'new mipmapped canvases inherit the current default mipmap filter',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        await _call(
          runtime,
          const ['love', 'graphics', 'setDefaultMipmapFilter'],
          const <Object?>['nearest', 0.25],
        );

        final canvas = await _call(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          <Object?>[
            32,
            16,
            Value(<Object?, Object?>{'mipmaps': 'manual'}),
          ],
        );

        expect(await _callMethod(canvas, 'getMipmapFilter'), <Object?>[
          'nearest',
          0.25,
        ]);
      },
    );
  });
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
}

Future<Object?> _callMethod(
  Object? receiver,
  String method, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(
    _rawMethod(receiver, method).call(<Object?>[receiver, ...args]),
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

BuiltinFunction _rawMethod(Object? receiver, String method) {
  final table = receiver is Value ? receiver.raw : receiver;
  expect(table, isA<Map>());
  final entry = (table! as Map)[method];
  return switch (entry) {
    final Value wrapped when wrapped.raw is BuiltinFunction =>
      wrapped.raw as BuiltinFunction,
    final BuiltinFunction function => function,
    _ => throw TestFailure('Expected $method to be a callable Lua method'),
  };
}

Future<Object?> _resolveCallResult(Object? result) async {
  final resolved = result is Future<Object?> ? await result : result;
  if (resolved is List<Object?>) {
    return resolved.map(_unwrap).toList(growable: false);
  }
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
