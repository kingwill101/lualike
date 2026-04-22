import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics transform bindings', () {
    test(
      'translate, rotate, scale, shear, and origin mirror Transform',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final oracle = await _call(runtime, const [
          'love',
          'math',
          'newTransform',
        ]);

        expect(
          await _call(runtime, const ['love', 'graphics', 'scale']),
          isNull,
        );
        _expectPointClose(
          await _call(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[3, 4],
          ),
          const <Object?>[3.0, 4.0],
        );

        await _call(
          runtime,
          const ['love', 'graphics', 'scale'],
          const <Object?>[2],
        );
        await _callMethod(oracle, 'scale', const <Object?>[2]);

        await _call(
          runtime,
          const ['love', 'graphics', 'rotate'],
          const <Object?>[0.25],
        );
        await _callMethod(oracle, 'rotate', const <Object?>[0.25]);

        await _call(
          runtime,
          const ['love', 'graphics', 'shear'],
          const <Object?>[0.1, -0.2],
        );
        await _callMethod(oracle, 'shear', const <Object?>[0.1, -0.2]);

        await _call(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[10, 20],
        );
        await _callMethod(oracle, 'translate', const <Object?>[10, 20]);

        final graphicsPoint = await _call(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[3, 4],
        );
        final oraclePoint = await _callMethod(
          oracle,
          'transformPoint',
          const <Object?>[3, 4],
        );
        _expectPointClose(graphicsPoint, oraclePoint);

        expect(
          await _call(runtime, const ['love', 'graphics', 'origin']),
          isNull,
        );
        _expectPointClose(
          await _call(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[3, 4],
          ),
          const <Object?>[3.0, 4.0],
        );
      },
    );

    test(
      'replaceTransform and applyTransform mirror Transform point mapping',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final base = await _call(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[15, 25, 0.4, 2, 3, 1, 2, 0.1, -0.2],
        );
        final offset = await _call(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[3, 4],
        );
        final composed = await _callMethod(base, 'clone');
        await _callMethod(composed, 'apply', <Object?>[offset]);

        expect(
          await _call(
            runtime,
            const ['love', 'graphics', 'replaceTransform'],
            <Object?>[base],
          ),
          isNull,
        );

        _expectPointClose(
          await _call(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          await _callMethod(base, 'transformPoint', const <Object?>[1, 2]),
        );

        expect(
          await _call(
            runtime,
            const ['love', 'graphics', 'applyTransform'],
            <Object?>[offset],
          ),
          isNull,
        );

        final graphicsPoint = await _call(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[1, 2],
        );
        final oraclePoint = await _callMethod(
          composed,
          'transformPoint',
          const <Object?>[1, 2],
        );
        _expectPointClose(graphicsPoint, oraclePoint);

        final inverseGraphicsPoint = await _call(runtime, const [
          'love',
          'graphics',
          'inverseTransformPoint',
        ], graphicsPoint as List<Object?>);
        final inverseOraclePoint = await _callMethod(
          composed,
          'inverseTransformPoint',
          oraclePoint as List<Object?>,
        );
        _expectPointClose(inverseGraphicsPoint, inverseOraclePoint);
        _expectPointClose(inverseGraphicsPoint, const <Object?>[1.0, 2.0]);
      },
    );

    test('push and pop preserve transform or all-state semantics', () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      await _call(
        runtime,
        const ['love', 'graphics', 'translate'],
        const <Object?>[10, 20],
      );
      await _call(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.2, 0.3, 0.4, 1.0],
      );

      await _call(runtime, const ['love', 'graphics', 'push']);
      await _call(
        runtime,
        const ['love', 'graphics', 'scale'],
        const <Object?>[2, 3],
      );
      await _call(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.9, 0.1, 0.2, 1.0],
      );
      expect(
        await _call(runtime, const ['love', 'graphics', 'getStackDepth']),
        1,
      );
      expect(await _call(runtime, const ['love', 'graphics', 'pop']), isNull);
      expect(
        await _call(runtime, const ['love', 'graphics', 'getStackDepth']),
        0,
      );
      _expectPointClose(
        await _call(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[1, 2],
        ),
        const <Object?>[11.0, 22.0],
      );
      expect(
        await _call(runtime, const ['love', 'graphics', 'getColor']),
        <Object?>[0.9, 0.1, 0.2, 1.0],
      );

      await _call(
        runtime,
        const ['love', 'graphics', 'push'],
        const <Object?>['all'],
      );
      await _call(
        runtime,
        const ['love', 'graphics', 'translate'],
        const <Object?>[5, 6],
      );
      await _call(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.4, 0.5, 0.6, 1.0],
      );
      expect(
        await _call(runtime, const ['love', 'graphics', 'getStackDepth']),
        1,
      );
      await _call(runtime, const ['love', 'graphics', 'pop']);
      expect(
        await _call(runtime, const ['love', 'graphics', 'getStackDepth']),
        0,
      );
      _expectPointClose(
        await _call(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[1, 2],
        ),
        const <Object?>[11.0, 22.0],
      );
      expect(
        await _call(runtime, const ['love', 'graphics', 'getColor']),
        <Object?>[0.9, 0.1, 0.2, 1.0],
      );
    });

    test(
      'push overload matches LOVE stack type and Transform dispatch',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final offset = await _call(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[3, 4],
        );

        await _call(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[10, 20],
        );

        await _call(
          runtime,
          const ['love', 'graphics', 'push'],
          <Object?>['all', offset],
        );
        _expectPointClose(
          await _call(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          const <Object?>[14.0, 26.0],
        );
        await _call(runtime, const ['love', 'graphics', 'pop']);

        await _call(
          runtime,
          const ['love', 'graphics', 'push'],
          const <Object?>['all', 'ignored'],
        );
        _expectPointClose(
          await _call(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          const <Object?>[11.0, 22.0],
        );
        await _call(runtime, const ['love', 'graphics', 'pop']);

        await expectLater(
          () => _call(
            runtime,
            const ['love', 'graphics', 'push'],
            const <Object?>['bogus'],
          ),
          throwsA(
            isA<LuaError>().having(
              (error) => error.message,
              'message',
              "Invalid graphics stack type 'bogus', expected one of: "
                  "'all', 'transform'",
            ),
          ),
        );
      },
    );
  });
}

void _expectPointClose(Object? actual, Object? expected) {
  final actualPoint = _pointPair(actual);
  final expectedPoint = _pointPair(expected);
  expect(actualPoint.$1, closeTo(expectedPoint.$1, 1e-9));
  expect(actualPoint.$2, closeTo(expectedPoint.$2, 1e-9));
}

(double, double) _pointPair(Object? value) {
  expect(value, isA<List<Object?>>());
  final point = value! as List<Object?>;
  expect(point, hasLength(2));
  return ((point[0] as num).toDouble(), (point[1] as num).toDouble());
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
  if (resolved case final Value wrapped when wrapped.isMulti) {
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
