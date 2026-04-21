import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.touch module', () {
    late Interpreter runtime;
    late LoveHeadlessHost host;

    setUp(() {
      runtime = Interpreter();
      host = LoveHeadlessHost();
      installLove2d(runtime: runtime, host: host);
    });

    test('reports active touches in insertion order', () async {
      host.touch.beginTouch(id: 11, x: 10.5, y: 20.25, pressure: 0.75);
      host.touch.beginTouch(id: 12, x: 30.0, y: 40.0, pressure: 1.0);
      host.touch.beginTouch(id: 11, x: 15.0, y: 25.0, pressure: 0.5);

      expect(
        await _call(runtime, const ['love', 'touch', 'getTouches']),
        <Object?, Object?>{1: 12, 2: 11},
      );
      expect(
        await _call(
          runtime,
          const ['love', 'touch', 'getPosition'],
          const <Object?>[11],
        ),
        <Object?>[15.0, 25.0],
      );
      expect(
        await _call(
          runtime,
          const ['love', 'touch', 'getPressure'],
          const <Object?>[11],
        ),
        0.5,
      );
    });

    test('rejects inactive touch ids', () async {
      host.touch.beginTouch(id: 21, x: 1.0, y: 2.0, pressure: 1.0);
      host.touch.endTouch(21);

      await expectLater(
        _call(
          runtime,
          const ['love', 'touch', 'getPosition'],
          const <Object?>[21],
        ),
        throwsA(isA<LuaError>()),
      );
      await expectLater(
        _call(
          runtime,
          const ['love', 'touch', 'getPressure'],
          const <Object?>[21],
        ),
        throwsA(isA<LuaError>()),
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
