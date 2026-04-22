import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics transform bindings', () {
    test(
      'translate, rotate, scale, shear, and origin mirror Transform',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final oracle = await luaCall(runtime, const [
          'love',
          'math',
          'newTransform',
        ]);

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'scale']),
          isNull,
        );
        _expectPointClose(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[3, 4],
          ),
          const <Object?>[3.0, 4.0],
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'scale'],
          const <Object?>[2],
        );
        await luaCallMethod(oracle, 'scale', const <Object?>[2]);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'rotate'],
          const <Object?>[0.25],
        );
        await luaCallMethod(oracle, 'rotate', const <Object?>[0.25]);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'shear'],
          const <Object?>[0.1, -0.2],
        );
        await luaCallMethod(oracle, 'shear', const <Object?>[0.1, -0.2]);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[10, 20],
        );
        await luaCallMethod(oracle, 'translate', const <Object?>[10, 20]);

        final graphicsPoint = await luaCall(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[3, 4],
        );
        final oraclePoint = await luaCallMethod(
          oracle,
          'transformPoint',
          const <Object?>[3, 4],
        );
        _expectPointClose(graphicsPoint, oraclePoint);

        expect(
          await luaCall(runtime, const ['love', 'graphics', 'origin']),
          isNull,
        );
        _expectPointClose(
          await luaCall(
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

        final base = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[15, 25, 0.4, 2, 3, 1, 2, 0.1, -0.2],
        );
        final offset = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[3, 4],
        );
        final composed = await luaCallMethod(base, 'clone');
        await luaCallMethod(composed, 'apply', <Object?>[offset]);

        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'replaceTransform'],
            <Object?>[base],
          ),
          isNull,
        );

        _expectPointClose(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          await luaCallMethod(base, 'transformPoint', const <Object?>[1, 2]),
        );

        expect(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'applyTransform'],
            <Object?>[offset],
          ),
          isNull,
        );

        final graphicsPoint = await luaCall(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[1, 2],
        );
        final oraclePoint = await luaCallMethod(
          composed,
          'transformPoint',
          const <Object?>[1, 2],
        );
        _expectPointClose(graphicsPoint, oraclePoint);

        final inverseGraphicsPoint = await luaCall(runtime, const [
          'love',
          'graphics',
          'inverseTransformPoint',
        ], graphicsPoint as List<Object?>);
        final inverseOraclePoint = await luaCallMethod(
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

      await luaCall(
        runtime,
        const ['love', 'graphics', 'translate'],
        const <Object?>[10, 20],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.2, 0.3, 0.4, 1.0],
      );

      await luaCall(runtime, const ['love', 'graphics', 'push']);
      await luaCall(
        runtime,
        const ['love', 'graphics', 'scale'],
        const <Object?>[2, 3],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.9, 0.1, 0.2, 1.0],
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
        1,
      );
      expect(await luaCall(runtime, const ['love', 'graphics', 'pop']), isNull);
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
        0,
      );
      _expectPointClose(
        await luaCall(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[1, 2],
        ),
        const <Object?>[11.0, 22.0],
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getColor']),
        <Object?>[0.9, 0.1, 0.2, 1.0],
      );

      await luaCall(
        runtime,
        const ['love', 'graphics', 'push'],
        const <Object?>['all'],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'translate'],
        const <Object?>[5, 6],
      );
      await luaCall(
        runtime,
        const ['love', 'graphics', 'setColor'],
        const <Object?>[0.4, 0.5, 0.6, 1.0],
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
        1,
      );
      await luaCall(runtime, const ['love', 'graphics', 'pop']);
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getStackDepth']),
        0,
      );
      _expectPointClose(
        await luaCall(
          runtime,
          const ['love', 'graphics', 'transformPoint'],
          const <Object?>[1, 2],
        ),
        const <Object?>[11.0, 22.0],
      );
      expect(
        await luaCall(runtime, const ['love', 'graphics', 'getColor']),
        <Object?>[0.9, 0.1, 0.2, 1.0],
      );
    });

    test(
      'push overload matches LOVE stack type and Transform dispatch',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final offset = await luaCall(
          runtime,
          const ['love', 'math', 'newTransform'],
          const <Object?>[3, 4],
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[10, 20],
        );

        await luaCall(
          runtime,
          const ['love', 'graphics', 'push'],
          <Object?>['all', offset],
        );
        _expectPointClose(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          const <Object?>[14.0, 26.0],
        );
        await luaCall(runtime, const ['love', 'graphics', 'pop']);

        await luaCall(
          runtime,
          const ['love', 'graphics', 'push'],
          const <Object?>['all', 'ignored'],
        );
        _expectPointClose(
          await luaCall(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          const <Object?>[11.0, 22.0],
        );
        await luaCall(runtime, const ['love', 'graphics', 'pop']);

        await expectLater(
          () => luaCall(
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
