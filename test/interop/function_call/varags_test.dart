@Tags(['interop'])
library;

import 'package:lualike/testing.dart';

void main() {
  group('Vararg Functionality Tests', () {
    test('simple vararg function', () async {
      final bridge = LuaLike();

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
      expect((result as Value).unwrap(), equals(15));
    });

    test('vararg with named parameters', () async {
      final bridge = LuaLike();

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

      expect((result1 as Value).unwrap(), equals("Hello, Alice"));
      expect(
        (result2 as Value).unwrap(),
        equals("Hello, Alice and Bob, Charlie"),
      );
    });

    // New comprehensive parameter list tests
    group('Parameter List Variations', () {
      test('empty parameter list', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function noParams()
            return "no parameters"
          end

          local result = noParams()
        ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals("no parameters"));
      });

      test('vararg only parameter list', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function varargsOnly(...)
            local args = {...}
            return #args
          end

          local result1 = varargsOnly()
          local result2 = varargsOnly(1, 2, 3)
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');

        expect((result1 as Value).unwrap(), equals(0));
        expect((result2 as Value).unwrap(), equals(3));
      });

      test('named parameters with comma before vararg', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function withComma(a, b, ...)
            local extras = {...}
            return a + b + #extras
          end

          local result1 = withComma(10, 20)
          local result2 = withComma(10, 20, 1, 2, 3)
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');

        expect((result1 as Value).unwrap(), equals(30)); // 10 + 20 + 0
        expect((result2 as Value).unwrap(), equals(33)); // 10 + 20 + 3
      });

      test('named parameters without comma before vararg', () async {
        final bridge = LuaLike();

        // Test that invalid syntax is rejected (missing comma before ...)
        expect(() async {
          await bridge.runCode('''
            function withoutComma(a, b ...)
              local extras = {...}
              return a * b + #extras
            end
          ''');
        }, throwsA(isA<FormatException>()));
      });

      test('single named parameter with vararg', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function singleNamed(first, ...)
            local extras = {...}
            return first .. " " .. #extras
          end

          local result1 = singleNamed("hello")
          local result2 = singleNamed("hello", "world", "!")
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');

        expect((result1 as Value).unwrap(), equals("hello 0"));
        expect((result2 as Value).unwrap(), equals("hello 2"));
      });

      test('multiple named parameters with vararg', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function multipleNamed(a, b, c, ...)
            local extras = {...}
            local sum = a + b + c
            for _, v in ipairs(extras) do
              sum = sum + v
            end
            return sum
          end

          local result1 = multipleNamed(1, 2, 3)
          local result2 = multipleNamed(1, 2, 3, 10, 20)
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');

        expect((result1 as Value).unwrap(), equals(6)); // 1 + 2 + 3
        expect((result2 as Value).unwrap(), equals(36)); // 1 + 2 + 3 + 10 + 20
      });
    });

    group('Local Function Parameter Variations', () {
      test('local function with vararg only', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local function localVararg(...)
            return select("#", ...)
          end

          local result = localVararg("a", "b", "c")
        ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals(3));
      });

      test('local function with named params and vararg', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local function localMixed(prefix, ...)
            local args = {...}
            local result = prefix
            for _, v in ipairs(args) do
              result = result .. "-" .. v
            end
            return result
          end

          local result1 = localMixed("start")
          local result2 = localMixed("start", "middle", "end")
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');

        expect((result1 as Value).unwrap(), equals("start"));
        expect((result2 as Value).unwrap(), equals("start-middle-end"));
      });
    });

    test('passing varargs to another function', () async {
      final bridge = LuaLike();

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
      expect((result as Value).unwrap(), equals("Count: 3, First: A"));
    });

    test('vararg in local function', () async {
      final bridge = LuaLike();

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

      expect((first as Value).unwrap(), equals(20));
      expect((second as Value).unwrap(), equals(40));
      expect((third as Value).unwrap(), equals(60));
    });

    test('empty varargs handling', () async {
      final bridge = LuaLike();

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

      expect((empty as Value).unwrap(), equals(0));
      expect((nonempty as Value).unwrap(), equals(3));
    });

    // Tests for varargs in table constructors
    group('Table Constructor with Varargs', () {
      test('expanding varargs in table constructor', () async {
        final bridge = LuaLike();

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

        expect((count as Value).unwrap(), equals(3));
        expect((first as Value).unwrap(), equals(1));
        expect((second as Value).unwrap(), equals(2));
        expect((third as Value).unwrap(), equals(3));
      });

      test('mixed values and varargs in table constructor', () async {
        final bridge = LuaLike();

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
          len.unwrap(),
          equals(7),
        ); // 2 prefix values + 3 varargs + 2 suffix values

        // Get values map and verify contents
        var valuesMap = values.unwrap() as Map;
        expect(valuesMap[1], equals(10));
        expect(valuesMap[2], equals(20));
        expect(valuesMap[3], equals("a"));
        expect(valuesMap[4], equals("b"));
        expect(valuesMap[5], equals("c"));
        expect(valuesMap[6], equals(30));
        expect(valuesMap[7], equals(40));
      });

      test('function returns in table constructor', () async {
        final bridge = LuaLike();

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
        expect(first.unwrap(), equals("x"));
        expect(size.unwrap(), equals(3));

        // When passed through varargs, all values are preserved
        expect(x.unwrap(), equals("x"));
        expect(y.unwrap(), equals("y"));
        expect(z.unwrap(), equals("z"));
        expect(count.unwrap(), equals(3));
      });

      test('empty varargs in table constructor', () async {
        final bridge = LuaLike();

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
        expect(size1.unwrap(), equals(3)); // [1, 2, 3]

        // With varargs: fixed elements plus varargs
        expect(size2.unwrap(), equals(5)); // [1, 2, "a", "b", 3]
      });

      test('nested table with varargs', () async {
        final bridge = LuaLike();

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

        expect(outer.unwrap(), equals(1));
        expect(innerCount.unwrap(), equals(3));
        expect(first.unwrap(), equals("a"));
        expect(second.unwrap(), equals("b"));
        expect(third.unwrap(), equals("c"));
      });
    });

    // Additional edge cases for parameter parsing
    group('Parameter Parsing Edge Cases', () {
      test('function with only whitespace before vararg', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function spacedVararg( ... )
            return select("#", ...)
          end

          local result = spacedVararg(1, 2, 3)
        ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals(3));
      });

      test('function with whitespace around comma and vararg', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function spacedCommaVararg(a , ... )
            return a + select("#", ...)
          end

          local result = spacedCommaVararg(10, "x", "y")
        ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals(12)); // 10 + 2
      });

      test('nested function calls with different parameter patterns', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function outer(...)
            local function inner(a, b, ...)
              return a + b + select("#", ...)
            end

            local function justVararg(...)
              return select("#", ...)
            end

            return inner(1, 2, ...) + justVararg(...)
          end

          local result = outer("x", "y", "z")
        ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals(9));
      });

      test('function assignment with different parameter patterns', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local f1 = function(...) return select("#", ...) end
          local f2 = function(a, ...) return a + select("#", ...) end
          local f3 = function(a, b, c, ...) return a + b + c + select("#", ...) end

          local result1 = f1(1, 2, 3)
          local result2 = f2(10, 4, 5)
          local result3 = f3(1, 2, 3, 4, 5, 6)
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');
        var result3 = bridge.getGlobal('result3');

        expect((result1 as Value).unwrap(), equals(3));
        expect((result2 as Value).unwrap(), equals(12)); // 10 + 2
        expect((result3 as Value).unwrap(), equals(9)); // 1 + 2 + 3 + 3
      });

      test('method definition with varargs', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local obj = {}

          function obj:method1(...)
            return select("#", ...)
          end

          function obj:method2(a, ...)
            return a .. select("#", ...)
          end

          local result1 = obj:method1("x", "y")
          local result2 = obj:method2("hello", "world", "!")
        ''');

        var result1 = bridge.getGlobal('result1');
        var result2 = bridge.getGlobal('result2');

        expect((result1 as Value).unwrap(), equals(2));
        expect((result2 as Value).unwrap(), equals("hello2"));
      });

      test('complex nested vararg scenarios', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function level1(...)
            local function level2(prefix, ...)
              local function level3(...)
                return {...}
              end
              return prefix, level3(...)
            end
            return level2("nested", ...)
          end

          local prefix, nested = level1("a", "b", "c")
          local count = #nested
          local first = nested[1]
        ''');

        var prefix = bridge.getGlobal('prefix');
        var count = bridge.getGlobal('count');
        var first = bridge.getGlobal('first');

        expect((prefix as Value).unwrap(), equals("nested"));
        expect((count as Value).unwrap(), equals(3));
        expect((first as Value).unwrap(), equals("a"));
      });
    });

    // Test error cases and boundary conditions
    group('Vararg Boundary Conditions', () {
      test('vararg with nil values', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function handleNils(...)
            local args = {...}
            local count = 0
            for i = 1, select("#", ...) do
              count = count + 1
              if args[i] == nil then
                args[i] = "nil_placeholder"
              end
            end
            return count, args
          end

          local count, args = handleNils("a", nil, "b", nil)
          local first = args[1]
          local second = args[2]
          local third = args[3]
          local fourth = args[4]
        ''');

        var count = bridge.getGlobal('count');
        var first = bridge.getGlobal('first');
        var second = bridge.getGlobal('second');
        var third = bridge.getGlobal('third');
        var fourth = bridge.getGlobal('fourth');

        expect((count as Value).unwrap(), equals(4));
        expect((first as Value).unwrap(), equals("a"));
        expect((second as Value).unwrap(), equals("nil_placeholder"));
        expect((third as Value).unwrap(), equals("b"));
        expect((fourth as Value).unwrap(), equals("nil_placeholder"));
      });

      test('large number of varargs', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          function manyArgs(...)
            return select("#", ...)
          end

          -- Create a table with many values
          local args = {}
          for i = 1, 100 do
            args[i] = i
          end

          local result = manyArgs(table.unpack(args))
        ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals(100));
      });
    });
  });
}
