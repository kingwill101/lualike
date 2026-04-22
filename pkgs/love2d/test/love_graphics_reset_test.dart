import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.graphics reset', () {
    test(
      'reset restores the screen canvas and default filter state immediately',
      () async {
        final runtime = Interpreter();
        installLove2d(runtime: runtime, host: LoveHeadlessHost());

        final canvas = await _call(
          runtime,
          const ['love', 'graphics', 'newCanvas'],
          const <Object?>[4, 4],
        );

        expect(
          await _call(
            runtime,
            const ['love', 'graphics', 'setDefaultFilter'],
            const <Object?>['nearest', 'linear', 2.0],
          ),
          isNull,
        );
        expect(
          await _call(
            runtime,
            const ['love', 'graphics', 'setCanvas'],
            <Object?>[canvas],
          ),
          isNull,
        );
        expect(
          await _call(runtime, const ['love', 'graphics', 'getCanvas']),
          isNotNull,
        );

        await _call(
          runtime,
          const ['love', 'graphics', 'translate'],
          const <Object?>[5, 6],
        );

        expect(
          await _call(runtime, const ['love', 'graphics', 'reset']),
          isNull,
        );

        expect(
          await _call(runtime, const ['love', 'graphics', 'getCanvas']),
          isNull,
        );
        expect(
          await _call(runtime, const ['love', 'graphics', 'getDefaultFilter']),
          <Object?>['linear', 'linear', 1.0],
        );
        expect(
          await _call(
            runtime,
            const ['love', 'graphics', 'transformPoint'],
            const <Object?>[1, 2],
          ),
          <Object?>[1.0, 2.0],
        );
        expect(
          await _call(runtime, const ['love', 'graphics', 'getStats']),
          containsPair('canvasswitches', 2),
        );
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
    return List<Object?>.from(
      wrapped.raw as List<Object?>,
      growable: false,
    ).map(_unwrap).toList(growable: false);
  }
  return _unwrap(resolved);
}

Object? _unwrap(Object? value) => value is Value ? value.unwrap() : value;
