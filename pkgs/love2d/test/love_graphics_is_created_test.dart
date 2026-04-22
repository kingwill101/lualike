import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  test(
    'love.graphics.isCreated is available as a source-backed shim',
    () async {
      final runtime = Interpreter();
      installLove2d(runtime: runtime, host: LoveHeadlessHost());

      final love = runtime.getCurrentEnv().get('love')! as Value;
      final graphics =
          (love.raw as Map<Object?, Object?>)['graphics']! as Value;
      final graphicsTable = graphics.raw as Map<Object?, Object?>;

      expect(graphicsTable.containsKey('isCreated'), isTrue);

      final result = await _call(runtime, const [
        'love',
        'graphics',
        'isCreated',
      ]);
      expect(result, isTrue);
    },
  );
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
