import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.physics query and raycast bindings', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test('fixture and shape rayCast return LOVE-style normals and fractions', () async {
      final world = await _call(
        runtime,
        const ['love', 'physics', 'newWorld'],
      );
      final body = await _call(
        runtime,
        const ['love', 'physics', 'newBody'],
        <Object?>[world, 100, 50, 'static'],
      );
      final fixture = await _call(
        runtime,
        const ['love', 'physics', 'newFixture'],
        <Object?>[
          body,
          await _call(
            runtime,
            const ['love', 'physics', 'newCircleShape'],
            const <Object?>[20],
          ),
          1,
        ],
      );

      _expectDoubleListClose(
        await _callMethod(
          fixture,
          'rayCast',
          const <Object?>[60, 50, 140, 50, 1],
        ),
        const <double>[-1, 0, 0.25],
      );
      expect(
        await _callMethod(
          fixture,
          'rayCast',
          const <Object?>[60, 0, 140, 0, 1],
        ),
        <Object?>[],
      );

      final shape = await _callMethod(fixture, 'getShape');
      _expectDoubleListClose(
        await _callMethod(
          shape,
          'rayCast',
          const <Object?>[60, 50, 140, 50, 1, 100, 50, 0],
        ),
        const <double>[-1, 0, 0.25],
      );

      await expectLater(
        _callMethod(
          shape,
          'rayCast',
          const <Object?>[60, 50, 140, 50, 1, 100, 50, 0, 2],
        ),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains('Physics error: index out of bounds'),
          ),
        ),
      );
    });

    test('world queryBoundingBox and rayCast honor LOVE callback semantics', () async {
      final result = await _execute(lua, '''
local world = love.physics.newWorld()

local bodyA = love.physics.newBody(world, 30, 50, 'static')
local bodyB = love.physics.newBody(world, 60, 50, 'static')
local bodyC = love.physics.newBody(world, 90, 50, 'static')

love.physics.newFixture(bodyA, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyB, love.physics.newCircleShape(10), 1)
love.physics.newFixture(bodyC, love.physics.newCircleShape(10), 1)

local queryHits = {}
world:queryBoundingBox(0, 0, 100, 100, function(fixture)
  queryHits[#queryHits + 1] = fixture:getBody():getX()
  return #queryHits < 2
end)

local rayHits = {}
world:rayCast(0, 50, 120, 50, function(fixture, x, y, xn, yn, fraction)
  rayHits[#rayHits + 1] = {fixture:getBody():getX(), x, y, xn, yn, fraction}
  if #rayHits == 1 then
    return 1
  end
  return 0
end)

local clippedHits = {}
world:rayCast(0, 50, 120, 50, function(fixture, x, y, xn, yn, fraction)
  clippedHits[#clippedHits + 1] = fixture:getBody():getX()
  return fraction
end)

return queryHits, rayHits, clippedHits
''');

      expect(result, isA<List<Object?>>());
      final values = result! as List<Object?>;
      expect(_doubleTable(values[0] as Map), <double>[30, 60]);

      final rayRows = _indexedValues(values[1] as Map);
      expect(rayRows, hasLength(2));
      _expectDoubleListClose(
        rayRows[0],
        <double>[30, 20, 50, -1, 0, 1 / 6],
      );
      _expectDoubleListClose(
        rayRows[1],
        <double>[60, 50, 50, -1, 0, 5 / 12],
      );

      expect(_doubleTable(values[2] as Map), <double>[30]);
    });

    test('world rayCast rejects non-numeric callback returns', () async {
      await expectLater(
        _execute(lua, '''
local world = love.physics.newWorld()
local body = love.physics.newBody(world, 30, 50, 'static')
love.physics.newFixture(body, love.physics.newCircleShape(10), 1)

world:rayCast(0, 50, 120, 50, function()
  return false
end)
'''),
        throwsA(
          isA<LuaError>().having(
            (error) => error.message,
            'message',
            contains("Raycast callback didn't return a number!"),
          ),
        ),
      );
    });
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

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return _resolveCallResult(lua.execute(code, scriptPath: scriptPath));
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

List<Object?> _indexedValues(Map table) {
  final keys = table.keys.whereType<num>().map((key) => key.toInt()).toList()
    ..sort();
  return keys.map((key) => table[key]).toList(growable: false);
}

List<double> _doubleTable(Map table) {
  return _indexedValues(table)
      .map((entry) => (entry as num).toDouble())
      .toList(growable: false);
}

List<double> _doubleResults(Object? value) {
  if (value is Map) {
    return _doubleTable(value);
  }
  return (value as List<Object?>)
      .map((entry) => (entry as num).toDouble())
      .toList(growable: false);
}

void _expectDoubleListClose(
  Object? value,
  List<double> expected, [
  double epsilon = 1e-5,
]) {
  final actual = _doubleResults(value);
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(
      actual[i],
      closeTo(expected[i], epsilon),
      reason: 'Unexpected value at index $i',
    );
  }
}
