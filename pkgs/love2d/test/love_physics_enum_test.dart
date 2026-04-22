import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.physics enum bindings', () {
    late Interpreter runtime;

    setUp(() {
      runtime = Interpreter();
      installLove2d(runtime: runtime);
    });

    test(
      'installs BodyType, JointType, and ShapeType in globals and module table',
      () {
        final love = runtime.getCurrentEnv().get('love');
        final loveRaw = love is Value ? love.raw : love;
        expect(loveRaw, isA<Map<dynamic, dynamic>>());

        final physics = (loveRaw as Map<dynamic, dynamic>)['physics'];
        final physicsRaw = physics is Value ? physics.raw : physics;
        expect(physicsRaw, isA<Map<dynamic, dynamic>>());

        final physicsTable = physicsRaw as Map<dynamic, dynamic>;
        final bodyType = _tableValue(physicsTable['BodyType']);
        final jointType = _tableValue(physicsTable['JointType']);
        final shapeType = _tableValue(physicsTable['ShapeType']);

        expect(bodyType['static'], 'static');
        expect(bodyType['dynamic'], 'dynamic');
        expect(bodyType['kinematic'], 'kinematic');

        expect(jointType['distance'], 'distance');
        expect(jointType['friction'], 'friction');
        expect(jointType['gear'], 'gear');
        expect(jointType['mouse'], 'mouse');
        expect(jointType['prismatic'], 'prismatic');
        expect(jointType['pulley'], 'pulley');
        expect(jointType['revolute'], 'revolute');
        expect(jointType['rope'], 'rope');
        expect(jointType['weld'], 'weld');

        expect(shapeType['circle'], 'circle');
        expect(shapeType['polygon'], 'polygon');
        expect(shapeType['edge'], 'edge');
        expect(shapeType['chain'], 'chain');

        expect(
          _tableValue(runtime.getCurrentEnv().get('BodyType'))['dynamic'],
          'dynamic',
        );
        expect(
          _tableValue(runtime.getCurrentEnv().get('JointType'))['rope'],
          'rope',
        );
        expect(
          _tableValue(runtime.getCurrentEnv().get('ShapeType'))['chain'],
          'chain',
        );
      },
    );

    test(
      'physics enums line up with runtime-returned body and shape type strings',
      () async {
        final bodyType = _tableValue(runtime.getCurrentEnv().get('BodyType'));
        final shapeType = _tableValue(runtime.getCurrentEnv().get('ShapeType'));

        final world = await luaCallList(runtime, const [
          'love',
          'physics',
          'newWorld',
        ]);
        final body = await luaCallList(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'kinematic'],
        );
        final shape = await luaCallList(
          runtime,
          const ['love', 'physics', 'newChainShape'],
          const <Object?>[false, 0, 0, 10, 0, 10, 10],
        );

        expect(await luaCallMethodList(body, 'getType'), bodyType['kinematic']);
        expect(await luaCallMethodList(shape, 'getType'), shapeType['chain']);
      },
    );
  });
}

Map<dynamic, dynamic> _tableValue(Object? value) {
  final raw = value is Value ? value.raw : value;
  expect(raw, isA<Map<dynamic, dynamic>>());
  return raw as Map<dynamic, dynamic>;
}
