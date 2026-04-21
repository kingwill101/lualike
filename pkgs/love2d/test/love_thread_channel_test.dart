import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  group('love.thread Channel bindings', () {
    late Interpreter runtime;
    late LuaLike lua;

    setUp(() {
      runtime = Interpreter();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test('named and unnamed channels preserve queue semantics', () async {
      final named = await _call(
        runtime,
        const ['love', 'thread', 'getChannel'],
        const <Object?>['jobs'],
      );
      final sameNamed = await _call(
        runtime,
        const ['love', 'thread', 'getChannel'],
        const <Object?>['jobs'],
      );
      final unnamed = await _call(runtime, const [
        'love',
        'thread',
        'newChannel',
      ]);

      expect(await _callMethod(named, 'type'), 'Channel');
      expect(
        await _callMethod(named, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await _callMethod(named, 'getCount'), 0);

      final messageId = await _callMethod(named, 'push', <Object?>[
        <Object?, Object?>{'kind': 'work', 'value': 42},
      ]);
      expect(messageId, 1);
      expect(await _callMethod(sameNamed, 'getCount'), 1);
      expect(
        await _callMethod(sameNamed, 'hasRead', <Object?>[messageId]),
        isFalse,
      );

      final peeked = await _callMethod(sameNamed, 'peek');
      expect(peeked, isA<Map>());
      final peekedMap = peeked! as Map;
      expect(peekedMap['kind'], 'work');
      expect(peekedMap['value'], 42);
      expect(await _callMethod(sameNamed, 'getCount'), 1);

      final popped = await _callMethod(sameNamed, 'pop');
      expect(popped, isA<Map>());
      final poppedMap = popped! as Map;
      expect(poppedMap['kind'], 'work');
      expect(poppedMap['value'], 42);
      expect(await _callMethod(named, 'hasRead', <Object?>[messageId]), isTrue);
      expect(await _callMethod(named, 'getCount'), 0);
      expect(await _callMethod(named, 'pop'), isNull);
      expect(await _callMethod(named, 'demand', const <Object?>[0]), isNull);

      final demandFuture = _callMethod(unnamed, 'demand');
      await Future<void>.delayed(Duration.zero);
      expect(await _callMethod(unnamed, 'push', const <Object?>[7]), 1);
      expect(await demandFuture, 7);

      final supplyFuture = _callMethod(unnamed, 'supply', const <Object?>[99]);
      await Future<void>.delayed(Duration.zero);
      expect(await _callMethod(unnamed, 'pop'), 99);
      expect(await supplyFuture, isTrue);

      expect(
        await _callMethod(unnamed, 'supply', const <Object?>[123, 0]),
        isFalse,
      );
      expect(await _callMethod(unnamed, 'getCount'), 1);
      expect(await _callMethod(unnamed, 'pop'), 123);

      await _callMethod(unnamed, 'push', const <Object?>['stale']);
      expect(await _callMethod(unnamed, 'getCount'), 1);
      await _callMethod(unnamed, 'clear');
      expect(await _callMethod(unnamed, 'getCount'), 0);
    });

    test(
      'performAtomic passes the channel and preserves return values',
      () async {
        final channel = await _call(runtime, const [
          'love',
          'thread',
          'newChannel',
        ]);
        final callback = await _execute(lua, '''
return function(channel, a, b)
  channel:push(a + b)
  return channel:getCount(), a, b
end
''');

        final result = await _callMethod(channel, 'performAtomic', <Object?>[
          callback,
          3,
          4,
        ]);
        expect(result, <Object?>[1, 3, 4]);
        expect(await _callMethod(channel, 'pop'), 7);
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
