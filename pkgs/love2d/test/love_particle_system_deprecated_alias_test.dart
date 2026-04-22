import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('ParticleSystem deprecated aliases', () {
    test(
      'setAreaSpread and getAreaSpread mirror upstream deprecated alias semantics',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final imageData = await _call(
          runtime,
          const ['love', 'image', 'newImageData'],
          const <Object?>[16, 16],
        );
        final image = await _call(
          runtime,
          const ['love', 'graphics', 'newImage'],
          <Object?>[imageData],
        );
        final particleSystem = await _call(
          runtime,
          const ['love', 'graphics', 'newParticleSystem'],
          <Object?>[image, 8],
        );

        await _callMethod(particleSystem!, 'setEmissionArea', <Object?>[
          'ellipse',
          3.0,
          4.0,
          0.5,
          true,
        ]);
        expect(await _callMethod(particleSystem, 'getAreaSpread'), <Object?>[
          'ellipse',
          3.0,
          4.0,
        ]);

        await _callMethod(particleSystem, 'setAreaSpread', <Object?>[
          'uniform',
          5.0,
          6.0,
        ]);
        expect(await _callMethod(particleSystem, 'getAreaSpread'), <Object?>[
          'uniform',
          5.0,
          6.0,
        ]);
        expect(await _callMethod(particleSystem, 'getEmissionArea'), <Object?>[
          'uniform',
          5.0,
          6.0,
          0.0,
          false,
        ]);

        await _callMethod(particleSystem, 'setAreaSpread');
        expect(await _callMethod(particleSystem, 'getAreaSpread'), <Object?>[
          'none',
          0.0,
          0.0,
        ]);
        expect(await _callMethod(particleSystem, 'getEmissionArea'), <Object?>[
          'none',
          0.0,
          0.0,
          0.0,
          false,
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
  Object receiver,
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

BuiltinFunction _rawMethod(Object receiver, String method) {
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
