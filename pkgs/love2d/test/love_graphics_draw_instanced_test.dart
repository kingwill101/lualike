import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.graphics.drawInstanced', () {
    test(
      'queues a single mesh command with instance count and draw transform',
      () async {
        final host = LoveHeadlessHost();
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: host);

        final mesh = await luaCall(
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
        await luaCall(
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
            await luaCall(runtime, const ['love', 'graphics', 'getStats'])
                as Map<Object?, Object?>;
        expect(stats['drawcalls'], 1);
      },
    );

    test('treats non-positive instance counts as a no-op', () async {
      final host = LoveHeadlessHost();
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: host);

      final mesh = await luaCall(
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
      await luaCall(
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
