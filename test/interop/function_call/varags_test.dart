@Tags(['interop'])
import 'package:lualike/testing.dart';

void main() {
  Logger.setEnabled(true);

  group('Vararg Functionality Tests', () {
    test('simple vararg function', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        function sum(...)
          local result = 0
          for _, v in ipairs({...}) do
            result = result + v
          end
          return result
        end

        local result = sum(1, 2, 3, 4, 5)
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals(15));
    });

    test('vararg with named parameters', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        function greet(name, ...)
          local greeting = "Hello, " .. name
          local extras = {...}
          if #extras > 0 then
            greeting = greeting .. " and " .. table.concat(extras, ", ")
          end
          return greeting
        end

        local result1 = greet("Alice")
        local result2 = greet("Alice", "Bob", "Charlie")
      ''');

      var result1 = bridge.getGlobal('result1');
      var result2 = bridge.getGlobal('result2');

      expect((result1 as Value).raw, equals("Hello, Alice"));
      expect((result2 as Value).raw, equals("Hello, Alice and Bob, Charlie"));
    });

    test('passing varargs to another function', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        function format(template, ...)
          print("format", #...)
          return string.format(template, ...)
        end

        function printAll(...)
        print("printAll", #...) 
          return format("Count: %d, First: %s", select("#", ...), select(1, ...))
        end

        local result = printAll("A", "B", "C")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Count: 3, First: A"));
    });

    test('vararg in local function', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        local function process(...)
          local args = {...}
          local result = {}
          for i, v in ipairs(args) do
            result[i] = v * 2
          end
          return result
        end

        local values = process(10, 20, 30)
        local first = values[1]
        local second = values[2]
        local third = values[3]
      ''');

      var first = bridge.getGlobal('first');
      var second = bridge.getGlobal('second');
      var third = bridge.getGlobal('third');

      expect((first as Value).raw, equals(20));
      expect((second as Value).raw, equals(40));
      expect((third as Value).raw, equals(60));
    });

    test('empty varargs handling', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        function countArgs(...)
          local args = {...}
          return #args
        end

        local empty = countArgs()
        local nonempty = countArgs(1, 2, 3)
      ''');

      var empty = bridge.getGlobal('empty');
      var nonempty = bridge.getGlobal('nonempty');

      expect((empty as Value).raw, equals(0));
      expect((nonempty as Value).raw, equals(3));
    });

    // Tests for varargs in table constructors
    group('Table Constructor with Varargs', () {
      test('expanding varargs in table constructor', () async {
        final bridge = LuaLikeBridge();

        await bridge.runCode('''
          function getValues(...)
            return {...}
          end

          local t = getValues(1, 2, 3)
          local count = #t
          local first = t[1]
          local second = t[2]
          local third = t[3]
        ''');

        var count = bridge.getGlobal('count');
        var first = bridge.getGlobal('first');
        var second = bridge.getGlobal('second');
        var third = bridge.getGlobal('third');

        expect((count as Value).raw, equals(3));
        expect((first as Value).raw, equals(1));
        expect((second as Value).raw, equals(2));
        expect((third as Value).raw, equals(3));
      });

      test('mixed values and varargs in table constructor', () async {
        final bridge = LuaLikeBridge();

        await bridge.runCode('''
          function getTable(...)
            return {10, 20, ..., 30, 40}
          end

          local t = getTable("a", "b", "c")
          local len = #t
          local values = {}
          for i=1,len do
            values[i] = t[i]
          end
        ''');

        var values = bridge.getGlobal('values') as Value;
        var len = bridge.getGlobal('len') as Value;

        expect(
          len.raw,
          equals(7),
        ); // 2 prefix values + 3 varargs + 2 suffix values

        // Get values map and verify contents
        var valuesMap = values.raw as Map;
        expect((valuesMap[1] as Value).raw, equals(10));
        expect((valuesMap[2] as Value).raw, equals(20));
        expect((valuesMap[3] as Value).raw, equals("a"));
        expect((valuesMap[4] as Value).raw, equals("b"));
        expect((valuesMap[5] as Value).raw, equals("c"));
        expect((valuesMap[6] as Value).raw, equals(30));
        expect((valuesMap[7] as Value).raw, equals(40));
      });

      test('function returns in table constructor', () async {
        final bridge = LuaLikeBridge();

        await bridge.runCode('''
          function getMultiple()
            return "x", "y", "z"
          end

          local t1 = {getMultiple()} -- Only first value used in table
          local first = t1[1]
          local size = #t1

          function getVarargs(...)
            return {...}
          end

          local t2 = getVarargs(getMultiple()) -- All values passed through varargs
          local x = t2[1]
          local y = t2[2]
          local z = t2[3]
          local count = #t2
        ''');

        var first = bridge.getGlobal('first') as Value;
        var size = bridge.getGlobal('size') as Value;

        var x = bridge.getGlobal('x') as Value;
        var y = bridge.getGlobal('y') as Value;
        var z = bridge.getGlobal('z') as Value;
        var count = bridge.getGlobal('count') as Value;

        // In regular table constructor, only first return value is used
        expect(first.raw, equals("x"));
        expect(size.raw, equals(3));

        // When passed through varargs, all values are preserved
        expect(x.raw, equals("x"));
        expect(y.raw, equals("y"));
        expect(z.raw, equals("z"));
        expect(count.raw, equals(3));
      });

      test('empty varargs in table constructor', () async {
        final bridge = LuaLikeBridge();

        await bridge.runCode('''
          function makeTable(...)
            return {1, 2, ..., 3}
          end

          local t1 = makeTable() -- No varargs
          local size1 = #t1

          local t2 = makeTable("a", "b") -- With varargs
          local size2 = #t2
        ''');

        var size1 = bridge.getGlobal('size1') as Value;
        var size2 = bridge.getGlobal('size2') as Value;

        // Without varargs: just the fixed elements
        expect(size1.raw, equals(3)); // [1, 2, 3]

        // With varargs: fixed elements plus varargs
        expect(size2.raw, equals(5)); // [1, 2, "a", "b", 3]
      });

      test('nested table with varargs', () async {
        final bridge = LuaLikeBridge();

        await bridge.runCode('''
          function getNestedTable(...)
            return {
              outer = 1,
              inner = {...}
            }
          end

          local t = getNestedTable("a", "b", "c")
          local outer = t.outer
          local innerCount = #t.inner
          local first = t.inner[1]
          local second = t.inner[2]
          local third = t.inner[3]
        ''');

        var outer = bridge.getGlobal('outer') as Value;
        var innerCount = bridge.getGlobal('innerCount') as Value;
        var first = bridge.getGlobal('first') as Value;
        var second = bridge.getGlobal('second') as Value;
        var third = bridge.getGlobal('third') as Value;

        expect(outer.raw, equals(1));
        expect(innerCount.raw, equals(3));
        expect(first.raw, equals("a"));
        expect(second.raw, equals("b"));
        expect(third.raw, equals("c"));
      });
    });
  });
}
