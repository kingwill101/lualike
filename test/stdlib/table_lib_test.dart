import 'package:lualike/testing.dart';

void main() {
  group('Table Library', () {
    test('table.insert', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          table.insert(t, 2, 4)
          return t[1], t[2], t[3], t[4]
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect(t1[0], equals(1));
        expect(t1[1], equals(4));
        expect(t1[2], equals(2));
        expect(t1[3], equals(3));
      }
    });

    test('table.insert at end', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          table.insert(t, 4)
          return t[1], t[2], t[3], t[4]
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect(t1[0], equals(1));
        expect(t1[1], equals(2));
        expect(t1[2], equals(3));
        expect(t1[3], equals(4));
      }
    });

    test('table.remove', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          local removed = table.remove(t, 2)
          return t[1], t[2], removed
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect(t1[0], equals(1));
        expect(t1[1], equals(3));
        expect(t1[2], equals(2));
      }
    });

    test('table.remove last element', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          local removed = table.remove(t)
          return t[1], t[2], t[3], removed
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect(t1[0], equals(1));
        expect(t1[1], equals(2));
        expect(t1[2], isNull);
        expect(t1[3], equals(3));
      }
    });

    test('table.concat', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {"hello", "world", "from", "Lua"}
          local str = table.concat(t, " ")
          return str
        ''');
      } on ReturnException catch (e) {
        var str = e.value as Value;
        expect(str.unwrap(), equals("hello world from Lua"));
      }
    });

    test('table.concat with range', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {"hello", "world", "from", "Lua"}
          local str1 = table.concat(t, "-", 2, 3)
          local str2 = table.concat(t, "", 1, 2)
          return str1, str2
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals("world-from"));
        expect(results[1], equals("helloworld"));
      }
    });

    test('table.concat edge cases', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local empty = {}
          local str1 = table.concat(empty)
          local str2 = table.concat({1, 2, 3}, "", 5, 3) -- i > j
          return str1, str2
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(""));
        expect(results[1], equals(""));
      }
    });

    test('table.move', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t1 = {1, 2, 3, 4, 5}
          local t2 = {}
          table.move(t1, 2, 4, 1, t2)
          return t2[1], t2[2], t2[3], t1[2] -- t1 should be unchanged
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(2));
        expect(results[1], equals(3));
        expect(results[2], equals(4));
        expect(results[3], equals(2)); // Original table unchanged
      }
    });

    test('table.move within same table', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3, 4, 5}
          table.move(t, 1, 3, 3)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(1)); // Unchanged
        expect(results[1], equals(2)); // Unchanged
        expect(results[2], equals(1)); // Moved from t[1]
        expect(results[3], equals(2)); // Moved from t[2]
        expect(results[4], equals(3)); // Moved from t[3]
      }
    });

    test('table.pack', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = table.pack(10, 20, 30)
          return t[1], t[2], t[3], t.n
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect(t1[0], equals(10));
        expect(t1[1], equals(20));
        expect(t1[2], equals(30));
        expect(t1[3], equals(3));
      }
    });

    test('table.pack with nil values', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local function get_nil() return nil end
          local t = table.pack(10, get_nil(), 30)
          return t[1], t[2], t[3], t.n
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect(t1[0], equals(10));
        expect(t1[1], isNull);
        expect(t1[2], equals(30));
        expect(t1[3], equals(3)); // n should be 3 even with nil
      }
    });

    test('table.sort', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {3, 1, 4, 2, 5}
          table.sort(t)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(1));
        expect(results[1], equals(2));
        expect(results[2], equals(3));
        expect(results[3], equals(4));
        expect(results[4], equals(5));
      }
    });

    test('table.sort with custom comparator', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {3, 1, 4, 2, 5}
          -- In Lua, the comparator returns true when a should come before b
          -- So for descending order, we return true when a > b
          table.sort(t, function(a, b) return a > b end)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        Logger.debug(
          "Results: ${results[0]}, ${results[1]}, ${results[2]}, ${results[3]}, ${results[4]}",
        );
        expect(results[0], equals(5));
        expect(results[1], equals(4));
        expect(results[2], equals(3));
        expect(results[3], equals(2));
        expect(results[4], equals(1));
      }
    });

    test('table.sort with invalid order function', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local function f(a, b)
            assert(a and b)
            return true
          end
          table.sort({1, 2, 3, 4}, f)
        ''');
        fail('Expected error for invalid order function');
      } on LuaError catch (e) {
        expect(e.message, contains('invalid order function for sorting'));
      }
    });

    test('table.sort with LuaString values', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local a = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}
          table.sort(a)
          return table.concat(a, ', ')
        ''');
      } on ReturnException catch (e) {
        final result = (e.value as Value).raw as String;
        expect(
          result,
          equals('Apr, Aug, Dec, Feb, Jan, Jul, Jun, Mar, May, Nov, Oct, Sep'),
        );
      }
    });

    test('table.sort with nil comparison function', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {3, 1, 4, 2, 5}
          table.sort(t, nil)  -- Should use default comparison
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(1));
        expect(results[1], equals(2));
        expect(results[2], equals(3));
        expect(results[3], equals(4));
        expect(results[4], equals(5));
      }
    });

    test('table.sort with mixed string types', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {'zebra', 'apple', 'banana', 'cat'}
          table.sort(t)
          return table.concat(t, ', ')
        ''');
      } on ReturnException catch (e) {
        final result = (e.value as Value).raw as String;
        expect(result, equals('apple, banana, cat, zebra'));
      }
    });

    test('table.sort with numbers and strings should error', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 'hello', 3, 'world'}
          table.sort(t)
        ''');
        fail('Expected error for incompatible types');
      } on LuaError catch (e) {
        expect(e.message, contains('attempt to compare incompatible types'));
      }
    });

    test(
      'table.sort with invalid order function that always returns true',
      () async {
        final bridge = LuaLike();

        try {
          await bridge.execute('''
          local function always_true(a, b)
            return true
          end
          table.sort({1, 2, 3}, always_true)
        ''');
          fail('Expected error for invalid order function');
        } on LuaError catch (e) {
          expect(e.message, contains('invalid order function for sorting'));
        }
      },
    );

    test(
      'table.sort with invalid order function that returns inconsistent results',
      () async {
        final bridge = LuaLike();

        try {
          await bridge.execute('''
          local function inconsistent(a, b)
            -- This function violates strict weak ordering
            if a == 1 and b == 2 then return true end
            if a == 2 and b == 1 then return true end
            return a < b
          end
          table.sort({1, 2, 3}, inconsistent)
        ''');
          fail('Expected error for invalid order function');
        } on LuaError catch (e) {
          expect(e.message, contains('invalid order function for sorting'));
        }
      },
    );

    test('table.sort with empty table', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {}
          table.sort(t)
          return #t
        ''');
      } on ReturnException catch (e) {
        final result = e.value as Value;
        expect(result.raw, equals(0));
      }
    });

    test('table.sort with single element table', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {42}
          table.sort(t)
          return t[1]
        ''');
      } on ReturnException catch (e) {
        final result = e.value as Value;
        expect(result.raw, equals(42));
      }
    });

    test('table.sort with duplicate values', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {3, 1, 3, 2, 1, 2}
          table.sort(t)
          return t[1], t[2], t[3], t[4], t[5], t[6]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(1));
        expect(results[1], equals(1));
        expect(results[2], equals(2));
        expect(results[3], equals(2));
        expect(results[4], equals(3));
        expect(results[5], equals(3));
      }
    });

    test('table.sort with custom comparator for strings', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {'cat', 'dog', 'bird', 'fish'}
          -- Sort by string length (ascending)
          table.sort(t, function(a, b) return #a < #b end)
          return table.concat(t, ', ')
        ''');
      } on ReturnException catch (e) {
        final result = (e.value as Value).raw as String;
        expect(result, equals('cat, dog, bird, fish'));
      }
    });

    test(
      'table.sort with custom comparator for numbers (descending)',
      () async {
        final bridge = LuaLike();

        try {
          await bridge.execute('''
          local t = {1, 5, 3, 2, 4}
          table.sort(t, function(a, b) return a > b end)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
        } on ReturnException catch (e) {
          var results = (e.value as Value).unwrap();
          expect(results[0], equals(5));
          expect(results[1], equals(4));
          expect(results[2], equals(3));
          expect(results[3], equals(2));
          expect(results[4], equals(1));
        }
      },
    );

    test('table.sort with non-function second argument should error', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          table.sort(t, "not a function")
        ''');
        fail('Expected error for non-function argument');
      } on LuaError catch (e) {
        expect(e.message, contains('invalid order function'));
      }
    });

    test('table.sort with table as second argument should error', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          table.sort(t, {})
        ''');
        fail('Expected error for table argument');
      } on LuaError catch (e) {
        expect(e.message, contains('invalid order function'));
      }
    });

    test('table.sort with number as second argument should error', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {1, 2, 3}
          table.sort(t, 42)
        ''');
        fail('Expected error for number argument');
      } on LuaError catch (e) {
        expect(e.message, contains('invalid order function'));
      }
    });

    test('table.unpack', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {10, 20, 30, 40, 50}
          local a, b, c = table.unpack(t, 2, 4)
          return a, b, c
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(20));
        expect(results[1], equals(30));
        expect(results[2], equals(40));
      }
    });

    test('table.unpack default range', () async {
      final bridge = LuaLike();

      try {
        await bridge.execute('''
          local t = {10, 20, 30}
          local a, b, c = table.unpack(t)
          return a, b, c
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect(results[0], equals(10));
        expect(results[1], equals(20));
        expect(results[2], equals(30));
      }
    });
  });
}
