@Tags(['expressions'])
library;

import 'package:lualike_test/test.dart';

void main() {
  group('Identifier evaluation for undefined variables', () {
    test('undefined global resolves to nil', () async {
      final bridge = LuaLike();
      await bridge.execute('result = undef');
      final result = bridge.getGlobal('result') as Value;
      expect(result.raw, isNull);
    });

    test('indexing undefined global throws', () async {
      final bridge = LuaLike();
      expect(
        () async => await bridge.execute('return undef.x'),
        throwsA(
          predicate(
            (e) => e.toString().contains('attempt to index a nil value'),
          ),
        ),
      );
    });
  });

  group('Identifier frame lookup', () {
    test('ordinary local lookup returns without allocating a Future', () {
      final vm = Interpreter();
      vm.getCurrentEnv().declare('answer', 42);

      final result = Identifier('answer').accept(vm);

      expect(result, isNot(isA<Future<Object?>>()));
      expect((result as Value).raw, equals(42));
    });

    test(
      'preserves nested local shadowing, upvalues, and coroutine state',
      () async {
        final bridge = LuaLike();
        await bridge.execute(r'''
        local outer = 10

        local function makeWorker(seed)
          local captured = seed
          return coroutine.create(function(argument)
            local before = captured + argument
            coroutine.yield(before)
            do
              local captured = before + 1
              return captured, outer
            end
          end)
        end

        local worker = makeWorker(20)
        firstOk, firstValue = coroutine.resume(worker, 2)
        secondOk, secondValue, outerValue = coroutine.resume(worker)
      ''');

        expect((bridge.getGlobal('firstOk') as Value).raw, isTrue);
        expect((bridge.getGlobal('firstValue') as Value).raw, equals(22));
        expect((bridge.getGlobal('secondOk') as Value).raw, isTrue);
        expect((bridge.getGlobal('secondValue') as Value).raw, equals(23));
        expect((bridge.getGlobal('outerValue') as Value).raw, equals(10));
      },
    );

    test('custom _ENV keeps yielding __index lookup asynchronous', () async {
      final bridge = LuaLike();
      final result = await bridge.execute(r'''
        local co = coroutine
        local proxy = setmetatable({}, {
          __index = function(_, key)
            return co.yield(key)
          end,
        })
        local worker = co.create(function()
          local _ENV = proxy
          return missing
        end)

        local firstOk, key = co.resume(worker)
        local secondOk, value = co.resume(worker, 42)
        return firstOk, key, secondOk, value
      ''');

      final values = result as List<Object?>;
      expect(
        values.map((value) => value is Value ? value.unwrap() : value),
        equals(<Object?>[true, 'missing', true, 42]),
      );
    });
  });
}
