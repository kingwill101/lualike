import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

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

        final world = await _call(runtime, const [
          'love',
          'physics',
          'newWorld',
        ]);
        final body = await _call(
          runtime,
          const ['love', 'physics', 'newBody'],
          <Object?>[world, 0, 0, 'kinematic'],
        );
        final shape = await _call(
          runtime,
          const ['love', 'physics', 'newChainShape'],
          const <Object?>[false, 0, 0, 10, 0, 10, 10],
        );

        expect(await _callMethod(body, 'getType'), bodyType['kinematic']);
        expect(await _callMethod(shape, 'getType'), shapeType['chain']);
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

Map<dynamic, dynamic> _tableValue(Object? value) {
  final raw = value is Value ? value.raw : value;
  expect(raw, isA<Map<dynamic, dynamic>>());
  return raw as Map<dynamic, dynamic>;
}
