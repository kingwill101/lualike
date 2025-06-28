import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Table Library', () {
    test('table.insert', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {1, 2, 3}
          table.insert(t, 2, 4)
          return t[1], t[2], t[3], t[4]
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect((t1[0] as Value).raw, equals(1));
        expect((t1[1] as Value).raw, equals(4));
        expect((t1[2] as Value).raw, equals(2));
        expect((t1[3] as Value).raw, equals(3));
      }
    });

    test('table.insert at end', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {1, 2, 3}
          table.insert(t, 4)
          return t[1], t[2], t[3], t[4]
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect((t1[0] as Value).raw, equals(1));
        expect((t1[1] as Value).raw, equals(2));
        expect((t1[2] as Value).raw, equals(3));
        expect((t1[3] as Value).raw, equals(4));
      }
    });

    test('table.remove', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {1, 2, 3}
          local removed = table.remove(t, 2)
          return t[1], t[2], removed
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect((t1[0] as Value).raw, equals(1));
        expect((t1[1] as Value).raw, equals(3));
        expect((t1[2] as Value).raw, equals(2));
      }
    });

    test('table.remove last element', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {1, 2, 3}
          local removed = table.remove(t)
          return t[1], t[2], t[3], removed
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect((t1[0] as Value).raw, equals(1));
        expect((t1[1] as Value).raw, equals(2));
        expect((t1[2] as Value).raw, isNull);
        expect((t1[3] as Value).raw, equals(3));
      }
    });

    test('table.concat', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
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
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {"hello", "world", "from", "Lua"}
          local str1 = table.concat(t, "-", 2, 3)
          local str2 = table.concat(t, "", 1, 2)
          return str1, str2
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals("world-from"));
        expect((results[1] as Value).raw, equals("helloworld"));
      }
    });

    test('table.concat edge cases', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local empty = {}
          local str1 = table.concat(empty)
          local str2 = table.concat({1, 2, 3}, "", 5, 3) -- i > j
          return str1, str2
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals(""));
        expect((results[1] as Value).raw, equals(""));
      }
    });

    test('table.move', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t1 = {1, 2, 3, 4, 5}
          local t2 = {}
          table.move(t1, 2, 4, 1, t2)
          return t2[1], t2[2], t2[3], t1[2] -- t1 should be unchanged
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals(2));
        expect((results[1] as Value).raw, equals(3));
        expect((results[2] as Value).raw, equals(4));
        expect(
          (results[3] as Value).raw,
          equals(2),
        ); // Original table unchanged
      }
    });

    test('table.move within same table', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {1, 2, 3, 4, 5}
          table.move(t, 1, 3, 3)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals(1)); // Unchanged
        expect((results[1] as Value).raw, equals(2)); // Unchanged
        expect((results[2] as Value).raw, equals(1)); // Moved from t[1]
        expect((results[3] as Value).raw, equals(2)); // Moved from t[2]
        expect((results[4] as Value).raw, equals(3)); // Moved from t[3]
      }
    });

    test('table.pack', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = table.pack(10, 20, 30)
          return t[1], t[2], t[3], t.n
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect((t1[0] as Value).raw, equals(10));
        expect((t1[1] as Value).raw, equals(20));
        expect((t1[2] as Value).raw, equals(30));
        expect((t1[3] as Value).raw, equals(3));
      }
    });

    test('table.pack with nil values', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local function get_nil() return nil end
          local t = table.pack(10, get_nil(), 30)
          return t[1], t[2], t[3], t.n
        ''');
      } on ReturnException catch (e) {
        var t1 = (e.value as Value).unwrap();
        expect((t1[0] as Value).raw, equals(10));
        expect((t1[1] as Value).raw, isNull);
        expect((t1[2] as Value).raw, equals(30));
        expect((t1[3] as Value).raw, equals(3)); // n should be 3 even with nil
      }
    });

    test('table.sort', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {3, 1, 4, 2, 5}
          table.sort(t)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals(1));
        expect((results[1] as Value).raw, equals(2));
        expect((results[2] as Value).raw, equals(3));
        expect((results[3] as Value).raw, equals(4));
        expect((results[4] as Value).raw, equals(5));
      }
    });

    test('table.sort with custom comparator', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {3, 1, 4, 2, 5}
          -- In Lua, the comparator returns true when a should come before b
          -- So for descending order, we return true when a > b
          table.sort(t, function(a, b) return a > b end)
          return t[1], t[2], t[3], t[4], t[5]
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        print(
          "Results: ${(results[0] as Value).raw}, ${(results[1] as Value).raw}, ${(results[2] as Value).raw}, ${(results[3] as Value).raw}, ${(results[4] as Value).raw}",
        );
        expect((results[0] as Value).raw, equals(5));
        expect((results[1] as Value).raw, equals(4));
        expect((results[2] as Value).raw, equals(3));
        expect((results[3] as Value).raw, equals(2));
        expect((results[4] as Value).raw, equals(1));
      }
    });

    test('table.unpack', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {10, 20, 30, 40, 50}
          local a, b, c = table.unpack(t, 2, 4)
          return a, b, c
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals(20));
        expect((results[1] as Value).raw, equals(30));
        expect((results[2] as Value).raw, equals(40));
      }
    });

    test('table.unpack default range', () async {
      final bridge = LuaLikeBridge();

      try {
        await bridge.runCode('''
          local t = {10, 20, 30}
          local a, b, c = table.unpack(t)
          return a, b, c
        ''');
      } on ReturnException catch (e) {
        var results = (e.value as Value).unwrap();
        expect((results[0] as Value).raw, equals(10));
        expect((results[1] as Value).raw, equals(20));
        expect((results[2] as Value).raw, equals(30));
      }
    });
  });
}
