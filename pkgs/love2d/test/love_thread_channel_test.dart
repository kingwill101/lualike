import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';
import 'test_support/lua_api_test_helpers.dart';

void main() {
  group('love.thread Channel bindings', () {
    late LuaRuntime runtime;
    late LuaLike lua;

    setUp(() {
      runtime = createLuaLikeTestRuntime();
      lua = LuaLike(runtime: runtime);
      installLove2d(runtime: runtime);
    });

    test('named and unnamed channels preserve queue semantics', () async {
      final named = await luaCallList(
        runtime,
        const ['love', 'thread', 'getChannel'],
        const <Object?>['jobs'],
      );
      final sameNamed = await luaCallList(
        runtime,
        const ['love', 'thread', 'getChannel'],
        const <Object?>['jobs'],
      );
      final unnamed = await luaCallList(runtime, const [
        'love',
        'thread',
        'newChannel',
      ]);

      expect(await luaCallMethodList(named, 'type'), 'Channel');
      expect(
        await luaCallMethodList(named, 'typeOf', const <Object?>['Object']),
        isTrue,
      );
      expect(await luaCallMethodList(named, 'getCount'), 0);

      final messageId = await luaCallMethodList(named, 'push', <Object?>[
        <Object?, Object?>{'kind': 'work', 'value': 42},
      ]);
      expect(messageId, 1);
      expect(await luaCallMethodList(sameNamed, 'getCount'), 1);
      expect(
        await luaCallMethodList(sameNamed, 'hasRead', <Object?>[messageId]),
        isFalse,
      );

      final peeked = await luaCallMethodList(sameNamed, 'peek');
      expect(peeked, isA<Map>());
      final peekedMap = peeked! as Map;
      expect(peekedMap['kind'], 'work');
      expect(peekedMap['value'], 42);
      expect(await luaCallMethodList(sameNamed, 'getCount'), 1);

      final popped = await luaCallMethodList(sameNamed, 'pop');
      expect(popped, isA<Map>());
      final poppedMap = popped! as Map;
      expect(poppedMap['kind'], 'work');
      expect(poppedMap['value'], 42);
      expect(
        await luaCallMethodList(named, 'hasRead', <Object?>[messageId]),
        isTrue,
      );
      expect(await luaCallMethodList(named, 'getCount'), 0);
      expect(await luaCallMethodList(named, 'pop'), isNull);
      expect(
        await luaCallMethodList(named, 'demand', const <Object?>[0]),
        isNull,
      );

      final demandFuture = luaCallMethodList(unnamed, 'demand');
      await Future<void>.delayed(Duration.zero);
      expect(await luaCallMethodList(unnamed, 'push', const <Object?>[7]), 1);
      expect(await demandFuture, 7);

      final supplyFuture = luaCallMethodList(unnamed, 'supply', const <Object?>[
        99,
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(await luaCallMethodList(unnamed, 'pop'), 99);
      expect(await supplyFuture, isTrue);

      expect(
        await luaCallMethodList(unnamed, 'supply', const <Object?>[123, 0]),
        isFalse,
      );
      expect(await luaCallMethodList(unnamed, 'getCount'), 1);
      expect(await luaCallMethodList(unnamed, 'pop'), 123);

      await luaCallMethodList(unnamed, 'push', const <Object?>['stale']);
      expect(await luaCallMethodList(unnamed, 'getCount'), 1);
      await luaCallMethodList(unnamed, 'clear');
      expect(await luaCallMethodList(unnamed, 'getCount'), 0);
    });

    test(
      'performAtomic passes the channel and preserves return values',
      () async {
        final channel = await luaCallList(runtime, const [
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

        final result = await luaCallMethodList(
          channel,
          'performAtomic',
          <Object?>[callback, 3, 4],
        );
        expect(result, <Object?>[1, 3, 4]);
        expect(await luaCallMethodList(channel, 'pop'), 7);
      },
    );
  });
}

Future<Object?> _execute(LuaLike lua, String code, {String? scriptPath}) async {
  return luaResolveCallResultList(lua.execute(code, scriptPath: scriptPath));
}
