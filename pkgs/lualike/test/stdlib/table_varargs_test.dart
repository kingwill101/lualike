import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('Table Unpack and Varargs Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('table.unpack with nil as third argument', () async {
      // Test that table.unpack(args, 1, nil) works same as table.unpack(args, 1)
      await lua.execute('''
        args = {1, 2, 3}
        a, b, c = table.unpack(args, 1, nil)
      ''');

      expect((lua.getGlobal('a') as Value).raw, equals(1));
      expect((lua.getGlobal('b') as Value).raw, equals(2));
      expect((lua.getGlobal('c') as Value).raw, equals(3));
    });

    test('table.unpack with args.n being nil', () async {
      // Test the specific case that was failing in vararg.lua
      await lua.execute('''
        function call(f, args)
          return f(table.unpack(args, 1, args.n))
        end

        function test(a, b)
          return a + b
        end

        args = {10, 20}
        -- args.n is nil here
        result = call(test, args)
      ''');

      expect((lua.getGlobal('result') as Value).raw, equals(30));
    });

    test('table indexing with varargs uses first value only', () async {
      // Test that t[...] uses only the first value from varargs
      await lua.execute('''
        t = {10, 20, 30}

        function test(...)
          return t[...]
        end

        result = test(2, 999, 888)  -- Should return t[2] = 20, ignoring 999, 888
      ''');

      expect((lua.getGlobal('result') as Value).raw, equals(20));
    });

    test('method call with varargs arithmetic', () async {
      // Test the specific method call that was failing
      await lua.execute('''
        t = {1, 10}
        function t:f (...)
          arg = {...}
          return self[...] + #arg
        end

        result1 = t:f(1, 4)  -- t[1] + 2 = 1 + 2 = 3
        result2 = t:f(2)     -- t[2] + 1 = 10 + 1 = 11
      ''');

      expect((lua.getGlobal('result1') as Value).raw, equals(3));
      expect((lua.getGlobal('result2') as Value).raw, equals(11));
    });

    test('varargs in table constructor', () async {
      // Test varargs expansion in table constructors
      await lua.execute('''
        function test(...)
          return {...}
        end

        t = test(1, 2, 3, 4)
        a, b, c, d, n = t[1], t[2], t[3], t[4], #t
      ''');

      expect((lua.getGlobal('a') as Value).raw, equals(1));
      expect((lua.getGlobal('b') as Value).raw, equals(2));
      expect((lua.getGlobal('c') as Value).raw, equals(3));
      expect((lua.getGlobal('d') as Value).raw, equals(4));
      expect((lua.getGlobal('n') as Value).raw, equals(4));
    });

    test('select function with varargs', () async {
      // Test select function behavior
      await lua.execute('''
        function test(...)
          n = select('#', ...)
          first = select(1, ...)
          second = select(2, ...)
          return n, first, second
        end

        n, first, second = test('a', 'b', 'c')
      ''');

      expect((lua.getGlobal('n') as Value).raw, equals(3));
      expect((lua.getGlobal('first') as Value).raw.toString(), equals('a'));
      expect((lua.getGlobal('second') as Value).raw.toString(), equals('b'));
    });

    test('table.unpack with custom range', () async {
      // Test table.unpack with start and end indices
      await lua.execute('''
        t = {10, 20, 30, 40, 50}
        a, b, c = table.unpack(t, 2, 4)
      ''');

      expect((lua.getGlobal('a') as Value).raw, equals(20));
      expect((lua.getGlobal('b') as Value).raw, equals(30));
      expect((lua.getGlobal('c') as Value).raw, equals(40));
    });

    test('table.pack creates table with n field', () async {
      // Test table.pack functionality
      await lua.execute('''
        t = table.pack(1, 2, nil, 4)
        a, b, c, d, n = t[1], t[2], t[3], t[4], t.n
      ''');

      expect((lua.getGlobal('a') as Value).raw, equals(1));
      expect((lua.getGlobal('b') as Value).raw, equals(2));
      expect((lua.getGlobal('c') as Value).raw, isNull);
      expect((lua.getGlobal('d') as Value).raw, equals(4));
      expect((lua.getGlobal('n') as Value).raw, equals(4));
    });

    test('function redefinition scope', () async {
      // Test that global function definitions override ones
      await lua.execute('''
        function f(x)
          return x * 2  -- version
        end

        result1 = f(5)  -- Should use version: 10

        function f(x)
          return x * 3  -- global version
        end

        result2 = f(5)  -- Should use global version: 15
      ''');

      expect((lua.getGlobal('result1') as Value).raw, equals(10));
      expect((lua.getGlobal('result2') as Value).raw, equals(15));
    });

    test('complex varargs with function calls', () async {
      // Test complex varargs scenarios
      await lua.execute('''
        function vararg(...)
          return {n = select('#', ...), ...}
        end

        function c12(...)
          x = {...}
          x.n = #x
          res = (x.n == 2 and x[1] == 1 and x[2] == 2)
          if res then res = 55 end
          return res, 2
        end

        call = function(f, args)
          return f(table.unpack(args, 1, args.n))
        end

        a, b = call(c12, {1, 2})
      ''');

      expect((lua.getGlobal('a') as Value).raw, equals(55));
      expect((lua.getGlobal('b') as Value).raw, equals(2));
    });
  });
}
