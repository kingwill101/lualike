@Tags(['interop'])
library;

import 'package:lualike/testing.dart';

void main() {
  group('Function Call Syntax Variations', () {
    test('standard function call with parentheses', () async {
      final bridge = LuaLike();

      // Register a function
      await bridge.execute('''
        function greet(name)
          return "Hello, " .. name
        end

        local result = greet("World")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("Hello, World"));
    });

    test('function call without parentheses for string literal', () async {
      final bridge = LuaLike();

      // Register a function
      await bridge.execute('''
        function greet(name)
          return "Hello, " .. name
        end

        local result = greet"World"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("Hello, World"));
    });

    test('table method call with parentheses', () async {
      final bridge = LuaLike();

      // Create a table with a method
      await bridge.execute('''
        local t = {}
        function t.method(param)
          return "Method called with: " .. param
        end

        local result = t.method("test")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("Method called with: test"));
    });

    test('table method call without parentheses', () async {
      final bridge = LuaLike();

      // Create a table with a method
      await bridge.execute('''
        local t = {}
        function t.method(param)
          return "Method called with: " .. param
        end

        local result = t.method"test"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("Method called with: test"));
    });

    test('standard library function call without parentheses', () async {
      final bridge = LuaLike();

      // Test string.upper without parentheses
      await bridge.execute('''
        local result = string.upper"hello"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("HELLO"));
    });

    test('require function call with parentheses', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}
        function M.test() return "test ok" end
        return M
      ''');

      // Test standard require syntax
      await bridge.execute('''
        local module = require("test_module")
        local result = module.test()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("test ok"));
    });

    test('require function call without parentheses', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}
        function M.test() return "test ok" end
        return M
      ''');

      // Test alternative require syntax without parentheses
      await bridge.execute('''
        local module = require"test_module"
        local result = module.test()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("test ok"));
    });
  });

  group('Method Chaining Syntax', () {
    test('method chaining on table', () async {
      final bridge = LuaLike();

      // Create a table with methods that return the table for chaining
      await bridge.execute('''
        local t = {value = 0}

        function t.increment(n)
          t.value = t.value + n
          return t
        end

        function t.double()
          t.value = t.value * 2
          return t
        end

        t.increment(5)
        t.double()
        local result = t.value
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals(10));
    });

    test('method chaining on require results (expected to fail)', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}

        function M.test()
          return "test ok"
        end

        return M
      ''');

      // Test method chaining on require results
      // FIXME: Our parser doesn't support method chaining on require results
      // Error: FormatException: Expected: '"', '#', ''', '(', etc.
      // This is valid Lua syntax and should be supported

      await bridge.execute('''
          local result = require("test_module").test()
        ''');
      final result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("test ok"));
    });

    test('combined alternative syntax (workaround)', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}
        function M.test(param) return "test: " .. param end
        return M
      ''');

      // Test combined alternative syntax with workaround
      await bridge.execute('''
        local module = require"test_module"
        local result = module.test"param"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("test: param"));
    });
  });

  group('Implicit Self Method Call', () {
    test('colon method definition and call', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {x = 42}
        function obj:foo(...)
          return self.x, select('#', ...), ...
        end
        local sx, n, a, b = obj:foo(10, 20)

      ''');
      var sx = bridge.getGlobal('sx');
      var n = bridge.getGlobal('n');
      var a = bridge.getGlobal('a');
      var b = bridge.getGlobal('b');
      expect((sx as Value).unwrap(), equals(42)); // self.x
      expect((n as Value).unwrap(), equals(2));
      expect((a as Value).unwrap(), equals(10));
      expect((b as Value).unwrap(), equals(20));
    });

    test('self field assignment and access', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {count = 0}
        function obj:inc()
          self.count = self.count + 1
          return self.count
        end
        local a = obj:inc()
        local b = obj:inc()
        local c = obj.count
      ''');
      var a = bridge.getGlobal('a');
      var b = bridge.getGlobal('b');
      var c = bridge.getGlobal('c');
      expect((a as Value).unwrap(), equals(1));
      expect((b as Value).unwrap(), equals(2));
      expect((c as Value).unwrap(), equals(2));
    });

    test('method chaining with self', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        local obj = {val = 1}

        function obj:inc(n)
          self.val = self.val + n
          return self
        end

        function obj:get()
          return self.val
        end

        local result = obj:inc(2):inc(3):get()
      ''');
      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals(6));
    });

    test('dot method definition and call', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {x = 99}
        function obj.foo(...)
          return obj.x, select('#', ...), ...
        end
        local ox, n, a, b = obj.foo(10, 20)
      ''');
      var ox = bridge.getGlobal('ox');
      var n = bridge.getGlobal('n');
      var a = bridge.getGlobal('a');
      var b = bridge.getGlobal('b');
      expect((ox as Value).unwrap(), equals(99));
      expect((n as Value).unwrap(), equals(2));
      expect((a as Value).unwrap(), equals(10));
      expect((b as Value).unwrap(), equals(20));
    });

    test(
      'calling colon method with dot syntax (should error like Lua)',
      () async {
        final bridge = LuaLike();
        await expectLater(
          bridge.execute('''
            local obj = {x = 5}
            function obj:bar(x, ...)
              return self and self.x or -1, x, select('#', ...), ...
            end
            local sx, x, n, a = obj.bar(99, 100)
          '''),
          throwsA(isA<LuaError>()),
        );
      },
      skip: 'Unstable when running with the full test suite',
    );

    test(
      'calling dot method with colon syntax (should get self as first arg)',
      () async {
        final bridge = LuaLike();
        await bridge.execute('''
        local obj = {y = 7}
        function obj.baz(x, ...)
          return x and x.y or -1, select('#', ...), ...
        end
        local ay, n, b, c = obj:baz(1, 2, 3)
      ''');
        var ay = bridge.getGlobal('ay');
        var n = bridge.getGlobal('n');
        var b = bridge.getGlobal('b');
        var c = bridge.getGlobal('c');
        expect(
          (ay as Value).unwrap(),
          equals(7),
        ); // self is passed as x, so x.y == 7
        expect((n as Value).unwrap(), equals(3));
        expect((b as Value).unwrap(), equals(1));
        expect((c as Value).unwrap(), equals(2));
      },
    );

    test('colon method returns self only', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {id = 123}
        function obj:whoami()
          return self
        end
        local result = obj:whoami()
      ''');
      var result = bridge.getGlobal('result');
      expect(result, isNotNull);
      expect((result as Value).raw is Map, isTrue);
      expect((((result).raw)['id'] as Value).unwrap(), equals(123));
    });

    test('colon method returns self and argument', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {name = 'A'}
        function obj:echo(x)
          return self, x
        end
        local s, x = obj:echo(42)
      ''');
      var s = bridge.getGlobal('s');
      var x = bridge.getGlobal('x');
      expect((s as Value).raw is Map, isTrue);
      expect(fromLuaValue(((s).raw)['name']), equals('A'));
      expect(fromLuaValue(x), equals(42));
    });

    test('colon method returns just argument', () async {
      final bridge = LuaLike();
      await bridge.execute('''
local obj = {y = 42}
function obj:val( x)
  return self.y + x
end
local result = obj:val(99)
      ''');
      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals(141));
    });

    test('colon method returns constant', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {}
        function obj:const()
          return 7
        end
        local result = obj:const()
      ''');
      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals(7));
    });

    test('colon method returns self.x', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        local obj = {x = 55}
        function obj:readx()
          return self.x
        end
        local result = obj:readx()
      ''');
      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals(55));
    });
  });
}
