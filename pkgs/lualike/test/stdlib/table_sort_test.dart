import 'package:lualike/lualike.dart';
import 'package:lualike_test/test.dart';

void main() {
  group('table.sort', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('reverse comparator uses fast path', () async {
      await lua.execute(r'''
        math.randomseed(1234)
        local limit = 1000
        local counter = 0
        local values = {}
        for i = 1, limit do
          values[i] = math.random()
        end

        table.sort(values, function (x, y)
          counter = counter + 1
          return y < x
        end)

        reverseSorted = true
        for i = 2, limit do
          if values[i - 1] < values[i] then
            reverseSorted = false
            break
          end
        end

        comparatorCalls = counter
      ''');

      expect(lua.getGlobal('reverseSorted').unwrap(), isTrue);
      final calls = lua.getGlobal('comparatorCalls').unwrap() as num;
      expect(calls, lessThan(100));
    });

    test('manual collect throttling engages for repeated collects', () async {
      final interpreter = Interpreter();
      final gc = interpreter.gc;

      expect(gc.shouldThrottleManualCollect(), isFalse);

      gc.noteManualCollectCompletion();
      for (var i = 0; i < 8; i++) {
        expect(gc.shouldThrottleManualCollect(), isTrue);
      }

      await Future<void>.delayed(const Duration(milliseconds: 120));
      var attempts = 0;
      while (gc.shouldThrottleManualCollect()) {
        attempts++;
        expect(attempts, lessThan(64));
      }
    });
  });
}
