import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.math module', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test('color helpers accept variadic and table inputs', () async {
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'colorToBytes'],
          const <Object?>[0.0, 0.5, 1.0, 1.2],
        ),
        <Object?>[0, 128, 255, 255],
      );

      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'colorFromBytes'],
          <Object?>[
            Value(<Object?, Object?>{1: 0, 2: 128, 3: 255, 4: 260}),
          ],
        ),
        <Object?>[0.0, 128 / 255, 1.0, 1.0],
      );
    });

    test('gamma helpers convert rgb components', () async {
      final linear = await luaCall(
        runtime,
        const ['love', 'math', 'gammaToLinear'],
        <Object?>[
          Value(<Object?, Object?>{1: 0.5, 2: 0.25, 3: 0.75, 4: 0.5}),
        ],
      );

      expect(linear, isA<List<Object?>>());
      final linearValues = linear! as List<Object?>;
      expect(linearValues[0] as double, closeTo(0.21404114048223255, 1e-12));
      expect(linearValues[1] as double, closeTo(0.05087608817155679, 1e-12));
      expect(linearValues[2] as double, closeTo(0.5225215539683921, 1e-12));
      expect(linearValues[3], 0.5);

      final gamma = await luaCall(runtime, const [
        'love',
        'math',
        'linearToGamma',
      ], linearValues);

      expect(gamma, isA<List<Object?>>());
      final gammaValues = gamma! as List<Object?>;
      expect(gammaValues[0] as double, closeTo(0.5, 1e-12));
      expect(gammaValues[1] as double, closeTo(0.25, 1e-12));
      expect(gammaValues[2] as double, closeTo(0.75, 1e-12));
      expect(gammaValues[3], 0.5);
    });

    test('noise matches upstream reference values', () async {
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'noise'],
          const <Object?>[0.125],
        ),
        closeTo(0.684921085834503, 1e-7),
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'noise'],
          const <Object?>[0.25, 0.75],
        ),
        closeTo(0.372749149799347, 1e-7),
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'noise'],
          const <Object?>[0.5, 1.25, -0.75],
        ),
        closeTo(0.592740535736084, 1e-7),
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'noise'],
          const <Object?>[0.5, 1.25, -0.75, 2.0],
        ),
        closeTo(0.599076986312866, 1e-7),
      );
    });

    test('random seed and state roundtrip through module api', () async {
      final seed = int.parse('0123456789ABCDEF', radix: 16);
      await luaCall(
        runtime,
        const ['love', 'math', 'setRandomSeed'],
        <Object?>[seed],
      );

      expect(
        await luaCall(runtime, const ['love', 'math', 'getRandomSeed']),
        <Object?>[0x89ABCDEF, 0x01234567],
      );

      final savedState =
          await luaCall(runtime, const ['love', 'math', 'getRandomState'])
              as String;
      expect(savedState, matches(RegExp(r'^0x[0-9a-f]{16}$')));

      final firstRandom = await luaCall(runtime, const [
        'love',
        'math',
        'random',
      ]);
      final firstNormal = await luaCall(
        runtime,
        const ['love', 'math', 'randomNormal'],
        const <Object?>[2.0, 10.0],
      );

      await luaCall(
        runtime,
        const ['love', 'math', 'setRandomState'],
        <Object?>[savedState],
      );

      expect(
        await luaCall(runtime, const ['love', 'math', 'random']),
        firstRandom,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'randomNormal'],
          const <Object?>[2.0, 10.0],
        ),
        firstNormal,
      );
    });

    test('random uses LOVE integer helper semantics', () async {
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'random'],
          const <Object?>[0],
        ),
        1.0,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'random'],
          const <Object?>[5],
        ),
        inInclusiveRange(1.0, 5.0),
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'random'],
          const <Object?>[10, 20],
        ),
        inInclusiveRange(10.0, 20.0),
      );
    });

    test('polygon helpers detect convexity and triangulate', () async {
      final square = Value(<Object?, Object?>{
        1: 0,
        2: 0,
        3: 10,
        4: 0,
        5: 10,
        6: 10,
        7: 0,
        8: 10,
      });
      final concave = Value(<Object?, Object?>{
        1: 0,
        2: 0,
        3: 10,
        4: 0,
        5: 5,
        6: 5,
        7: 10,
        8: 10,
        9: 0,
        10: 10,
      });

      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'isConvex'],
          <Object?>[square],
        ),
        isTrue,
      );
      expect(
        await luaCall(
          runtime,
          const ['love', 'math', 'isConvex'],
          <Object?>[concave],
        ),
        isFalse,
      );

      final triangulated = await luaCall(
        runtime,
        const ['love', 'math', 'triangulate'],
        <Object?>[square],
      );

      expect(triangulated, isA<Map>());
      final triangles = triangulated! as Map;
      expect(triangles, hasLength(2));

      final areas = triangles.values
          .map(
            (triangle) => _triangleArea(_indexedNumericValues(triangle as Map)),
          )
          .toList(growable: false);
      expect(areas[0] + areas[1], closeTo(100.0, 1e-9));

      expect(
        luaCall(
          runtime,
          const ['love', 'math', 'triangulate'],
          <Object?>[
            Value(<Object?, Object?>{1: 0, 2: 0, 3: 10, 4: 0}),
          ],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Need at least 3 vertices to triangulate'),
          ),
        ),
      );
    });
  });

  group('love.math RandomGenerator', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test('newRandomGenerator exposes seeded object api', () async {
      final seed = int.parse('0123456789ABCDEF', radix: 16);
      final generator = await luaCall(
        runtime,
        const ['love', 'math', 'newRandomGenerator'],
        <Object?>[seed],
      );

      expect(await luaCallMethod(generator!, 'getSeed'), <Object?>[
        0x89ABCDEF,
        0x01234567,
      ]);

      final savedState = await luaCallMethod(generator, 'getState') as String;
      final firstRandom = await luaCallMethod(generator, 'random');
      final firstNormal = await luaCallMethod(
        generator,
        'randomNormal',
        const <Object?>[1.5, 2.0],
      );

      expect(
        await luaCallMethod(generator, 'random', const <Object?>[5]),
        inInclusiveRange(1.0, 5.0),
      );
      expect(
        await luaCallMethod(generator, 'random', const <Object?>[5, 10]),
        inInclusiveRange(5.0, 10.0),
      );

      await luaCallMethod(generator, 'setState', <Object?>[savedState]);
      expect(await luaCallMethod(generator, 'random'), firstRandom);
      expect(
        await luaCallMethod(generator, 'randomNormal', const <Object?>[
          1.5,
          2.0,
        ]),
        firstNormal,
      );

      await luaCallMethod(generator, 'setSeed', const <Object?>[9, 10]);
      expect(await luaCallMethod(generator, 'getSeed'), <Object?>[9, 10]);
    });
  });

  group('love.math BezierCurve', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test('newBezierCurve exposes evaluation and derivative APIs', () async {
      final curve = await luaCall(
        runtime,
        const ['love', 'math', 'newBezierCurve'],
        const <Object?>[0, 0, 10, 0, 10, 10],
      );

      expect(await luaCallMethod(curve!, 'getControlPointCount'), 3);
      expect(await luaCallMethod(curve, 'getDegree'), 2);
      expect(
        await luaCallMethod(curve, 'getControlPoint', const <Object?>[1]),
        [0.0, 0.0],
      );
      expect(
        await luaCallMethod(curve, 'getControlPoint', const <Object?>[-1]),
        [10.0, 10.0],
      );
      expect(await luaCallMethod(curve, 'evaluate', const <Object?>[0.5]), [
        7.5,
        2.5,
      ]);

      final derivative = await luaCallMethod(curve, 'getDerivative');
      expect(
        await luaCallMethod(derivative!, 'evaluate', const <Object?>[0.5]),
        <Object?>[10.0, 10.0],
      );

      final segment = await luaCallMethod(curve, 'getSegment', const <Object?>[
        0.25,
        0.75,
      ]);
      expect(
        await luaCallMethod(segment!, 'evaluate', const <Object?>[0.5]),
        <Object?>[7.5, 2.5],
      );

      final rendered = await luaCallMethod(curve, 'render', const <Object?>[1]);
      expect(rendered, isA<Map>());
      expect(_indexedNumericValues(rendered! as Map), <double>[
        0.0,
        0.0,
        5.0,
        0.0,
        7.5,
        2.5,
        10.0,
        5.0,
        10.0,
        10.0,
      ]);
    });

    test(
      'BezierCurve mutation and transform APIs follow LOVE indexing',
      () async {
        final curve = await luaCall(
          runtime,
          const ['love', 'math', 'newBezierCurve'],
          const <Object?>[1, 0, 2, 0],
        );

        await luaCallMethod(curve!, 'insertControlPoint', const <Object?>[
          1.5,
          0.5,
          2,
        ]);
        expect(await luaCallMethod(curve, 'getControlPointCount'), 3);
        expect(
          await luaCallMethod(curve, 'getControlPoint', const <Object?>[2]),
          [1.5, 0.5],
        );

        await luaCallMethod(curve, 'setControlPoint', const <Object?>[2, 3, 4]);
        expect(
          await luaCallMethod(curve, 'getControlPoint', const <Object?>[2]),
          [3.0, 4.0],
        );

        await luaCallMethod(curve, 'removeControlPoint', const <Object?>[2]);
        expect(await luaCallMethod(curve, 'getControlPointCount'), 2);

        await luaCallMethod(curve, 'rotate', <Object?>[math.pi / 2]);
        expect(
          await luaCallMethod(curve, 'getControlPoint', const <Object?>[1]),
          <Object?>[closeTo(0.0, 1e-12), closeTo(1.0, 1e-12)],
        );

        await luaCallMethod(curve, 'scale', const <Object?>[2.0]);
        expect(
          await luaCallMethod(curve, 'getControlPoint', const <Object?>[1]),
          <Object?>[closeTo(0.0, 1e-12), closeTo(2.0, 1e-12)],
        );

        await luaCallMethod(curve, 'translate', const <Object?>[1.0, -1.0]);
        expect(
          await luaCallMethod(curve, 'getControlPoint', const <Object?>[1]),
          <Object?>[closeTo(1.0, 1e-12), closeTo(1.0, 1e-12)],
        );

        expect(
          await luaCallMethod(curve, 'renderSegment', const <Object?>[
            0.5,
            0.5,
            1,
          ]),
          isEmpty,
        );
      },
    );
  });
}

List<double> _indexedNumericValues(Map<Object?, Object?> table) {
  final entries = table.entries.toList(growable: false)
    ..sort((a, b) {
      final left = (a.key as num).toInt();
      final right = (b.key as num).toInt();
      return left.compareTo(right);
    });
  return entries
      .map((entry) => (entry.value as num).toDouble())
      .toList(growable: false);
}

double _triangleArea(List<double> coordinates) {
  var twiceArea = 0.0;
  for (var index = 0; index < coordinates.length; index += 2) {
    final nextIndex = (index + 2) % coordinates.length;
    final x1 = coordinates[index];
    final y1 = coordinates[index + 1];
    final x2 = coordinates[nextIndex];
    final y2 = coordinates[nextIndex + 1];
    twiceArea += (x1 * y2) - (x2 * y1);
  }
  return twiceArea.abs() / 2.0;
}
