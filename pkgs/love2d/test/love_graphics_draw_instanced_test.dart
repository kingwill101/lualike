import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  group('love.graphics.drawInstanced', () {
    test(
      'queues a single mesh command with instance count and draw transform',
      () async {
        final host = LoveHeadlessHost();
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final mesh = await _call(
          runtime,
          const ['love', 'graphics', 'newMesh'],
          <Object?>[
            _luaSeq(<Object?>[
              _luaSeq(<Object?>[0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]),
              _luaSeq(<Object?>[4.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0]),
              _luaSeq(<Object?>[0.0, 3.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0]),
            ]),
            'triangles',
            'dynamic',
          ],
        );

        LoveRuntimeContext.of(runtime).beginDrawFrame();
        await _call(
          runtime,
          const ['love', 'graphics', 'drawInstanced'],
          <Object?>[mesh, 3, 10.0, 20.0, 0.0, 2.0, 3.0, 1.0, 2.0],
        );

        expect(host.graphics.commands, hasLength(1));
        final command = host.graphics.commands.single as LoveMeshCommand;
        expect(command.instanceCount, 3);
        expect(command.mesh.drawMode, LoveMeshDrawMode.triangles);

        final localOrigin = _transformPoint(command.drawTransform, 1.0, 2.0);
        expect(localOrigin.x, closeTo(10.0, 1e-9));
        expect(localOrigin.y, closeTo(20.0, 1e-9));

        final stats =
            await _call(runtime, const ['love', 'graphics', 'getStats'])
                as Map<Object?, Object?>;
        expect(stats['drawcalls'], 1);
      },
    );

    test('treats non-positive instance counts as a no-op', () async {
      final host = LoveHeadlessHost();
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: host);

      final mesh = await _call(
        runtime,
        const ['love', 'graphics', 'newMesh'],
        <Object?>[
          _luaSeq(<Object?>[
            _luaSeq(<Object?>[0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]),
          ]),
          'points',
          'dynamic',
        ],
      );

      LoveRuntimeContext.of(runtime).beginDrawFrame();
      await _call(
        runtime,
        const ['love', 'graphics', 'drawInstanced'],
        <Object?>[mesh, 0, 5.0, 6.0],
      );

      expect(host.graphics.commands, isEmpty);
    });
  });
}

Map<Object?, Object?> _luaSeq(List<Object?> values) {
  return <Object?, Object?>{
    for (var index = 0; index < values.length; index++)
      index + 1: values[index],
  };
}

({double x, double y}) _transformPoint(vm.Matrix4 matrix, double x, double y) {
  final point = matrix.transformed3(vm.Vector3(x, y, 0));
  return (x: point.x, y: point.y);
}

Future<Object?> _call(
  Interpreter runtime,
  List<String> path, [
  List<Object?> args = const <Object?>[],
]) async {
  return _resolveCallResult(_rawFunction(runtime, path).call(args));
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
