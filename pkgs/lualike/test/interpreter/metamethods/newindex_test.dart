import 'package:lualike_test/test.dart';

void main() {
  group('__newindex metamethod', () {
    test('should call __newindex when key does not exist', () async {
      final bridge = LuaLike();

      // Execute the test code
      final result = await bridge.execute('''
        local t = {}
        local called = false
        function f(t, i, v)
          called = true
          rawset(t, i, v-3)
        end
        t.__newindex = f

        local a = setmetatable({}, t)
        a[1] = 30

        return a[1], called
      ''');

      expect(result, isA<List>());
      final values = result as List;
      final val1 = (values[0] as Value).raw; // 30 - 3
      final val2 = (values[1] as Value).raw; // __newindex was called
      expect(val1, equals(27));
      expect(val2, equals(true));
    });

    test('should handle string keys with __newindex', () async {
      final bridge = LuaLike();

      final result = await bridge.execute('''
        local t = {}
        function f(t, i, v)
          rawset(t, i, v-3)
        end
        t.__newindex = f

        local a = setmetatable({}, t)
        a.x = "101"

        return a.x
      ''');

      final val = (result as Value).raw;
      expect(val, equals(98)); // "101" - 3
    });

    test('should handle mixed assignments', () async {
      final bridge = LuaLike();

      final result = await bridge.execute('''
        local t = {}
        function f(t, i, v)
          rawset(t, i, v-3)
        end
        t.__newindex = f

        local a = setmetatable({}, t)
        a[1] = 30
        a.x = "101"
        a[5] = 200

        return a[1], a.x, a[5]
      ''');

      expect(result, isA<List>());
      final values = result as List;
      final val1 = (values[0] as Value).raw;
      final val2 = (values[1] as Value).raw;
      final val3 = (values[2] as Value).raw;
      expect(val1, equals(27)); // 30 - 3
      expect(val2, equals(98)); // "101" - 3
      expect(val3, equals(197)); // 200 - 3
    });

    test('should not call __newindex when key exists', () async {
      final bridge = LuaLike();

      final result = await bridge.execute('''
        local t = {}
        local called = false
        function f(t, i, v)
          called = true
          rawset(t, i, v-3)
        end
        t.__newindex = f

        local a = setmetatable({x = 10}, t)
        a.x = 20  -- key exists, should not call __newindex

        return a.x, called
      ''');

      expect(result, isA<List>());
      final values = result as List;
      final val1 = (values[0] as Value).raw;
      final val2 = (values[1] as Value).raw;
      expect(val1, equals(20)); // direct assignment
      expect(val2, equals(false)); // __newindex was not called
    });
  });
}
