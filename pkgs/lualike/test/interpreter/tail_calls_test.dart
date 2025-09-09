import 'package:lualike_test/test.dart';

void main() {
  group('Tail Calls', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('simple tail recursion', () async {
      await lua.execute('''
        function deep(n)
          if n > 0 then return deep(n-1) else return 101 end
        end
        result = deep(3000)
      ''');
      expect(lua.getGlobal('result').unwrap(), equals(101));
    });

    test('method tail recursion', () async {
      await lua.execute('''
        a = {}
        function a:deep(n)
          if n > 0 then return self:deep(n-1) else return 101 end
        end
        result = a:deep(3000)
      ''');
      expect(lua.getGlobal('result').unwrap(), equals(101));
    });

    test('tail calls with varargs', () async {
      await lua.execute('''
        local function foo(x, ...)
          local a = {...}
          return x, a[1], a[2]
        end

        local function foo1(x)
          return foo(10, x, x + 1)
        end

        local a,b,c = foo1(-2)
        results = {a, b, c}
      ''');
      final res = lua.getGlobal('results').raw as Map;
      expect((res[1] as Value).unwrap(), equals(10));
      expect((res[2] as Value).unwrap(), equals(-2));
      expect((res[3] as Value).unwrap(), equals(-1));
    });

    test('__call chain in tail call', () async {
      await lua.execute('''
        local n = 2000
        local function foo()
          if n == 0 then return 123
          else n = n - 1; return foo() end
        end

        for i = 1, 20 do
          foo = setmetatable({}, {__call = foo})
        end

        result = coroutine.wrap(function() return foo() end)()
      ''');
      expect(lua.getGlobal('result').unwrap(), equals(123));
    });
  });
}
