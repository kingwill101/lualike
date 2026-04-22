import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';
import 'test_support/physics_test_support.dart';

void main() {
  group('love.physics joint inventory bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'World:getJointCount, World:getJoints, and Body:getJoints are empty without joints',
      () async {
        final world = await luaCallList(runtime, const [
          'love',
          'physics',
          'newWorld',
        ]);
        final body = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'dynamic'],
        );

        expect(await luaCallMethodList(world, 'getJointCount'), 0);
        expect(
          indexedValues(await luaCallMethodList(world, 'getJoints') as Map),
          isEmpty,
        );
        expect(
          indexedValues(await luaCallMethodList(body, 'getJoints') as Map),
          isEmpty,
        );
      },
    );
  });
}
