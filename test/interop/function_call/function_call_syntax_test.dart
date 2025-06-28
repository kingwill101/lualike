@Tags(['interop'])
import 'package:lualike/testing.dart';

void main() {
  group('Function Call Syntax Variations', () {
    test('standard function call with parentheses', () async {
      final bridge = LuaLikeBridge();

      // Register a function
      await bridge.runCode('''
        function greet(name)
          return "Hello, " .. name
        end

        local result = greet("World")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Hello, World"));
    });

    test('function call without parentheses for string literal', () async {
      final bridge = LuaLikeBridge();

      // Register a function
      await bridge.runCode('''
        function greet(name)
          return "Hello, " .. name
        end

        local result = greet"World"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Hello, World"));
    });

    test('table method call with parentheses', () async {
      final bridge = LuaLikeBridge();

      // Create a table with a method
      await bridge.runCode('''
        local t = {}
        function t.method(param)
          return "Method called with: " .. param
        end

        local result = t.method("test")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Method called with: test"));
    });

    test('table method call without parentheses', () async {
      final bridge = LuaLikeBridge();

      // Create a table with a method
      await bridge.runCode('''
        local t = {}
        function t.method(param)
          return "Method called with: " .. param
        end

        local result = t.method"test"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Method called with: test"));
    });

    test('standard library function call without parentheses', () async {
      final bridge = LuaLikeBridge();

      // Test string.upper without parentheses
      await bridge.runCode('''
        local result = string.upper"hello"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("HELLO"));
    });

    test('require function call with parentheses', () async {
      final bridge = LuaLikeBridge();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}
        function M.test() return "test ok" end
        return M
      ''');

      // Test standard require syntax
      await bridge.runCode('''
        local module = require("test_module")
        local result = module.test()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("test ok"));
    });

    test('require function call without parentheses', () async {
      final bridge = LuaLikeBridge();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}
        function M.test() return "test ok" end
        return M
      ''');

      // Test alternative require syntax without parentheses
      await bridge.runCode('''
        local module = require"test_module"
        local result = module.test()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("test ok"));
    });
  });

  group('Method Chaining Syntax', () {
    // SKIP: Our implementation doesn't support method chaining
    test('method chaining on table (workaround)', () async {
      final bridge = LuaLikeBridge();

      // Create a table with methods that return the table for chaining
      await bridge.runCode('''
        local t = {value = 0}

        function t.increment(n)
          t.value = t.value + n
          return t
        end

        function t.double()
          t.value = t.value * 2
          return t
        end
      ''');

      // Call methods separately instead of chaining
      await bridge.runCode('''
        t.increment(5)
        t.double()
        local result = t.value
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals(10));
    });

    test('method chaining on require results (expected to fail)', () async {
      final bridge = LuaLikeBridge();

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

      await bridge.runCode('''
          local result = require("test_module").test()
        ''');
      final result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("test ok"));
    });

    test('combined alternative syntax (workaround)', () async {
      final bridge = LuaLikeBridge();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('test_module.lua', '''
        local M = {}
        function M.test(param) return "test: " .. param end
        return M
      ''');

      // Test combined alternative syntax with workaround
      await bridge.runCode('''
        local module = require"test_module"
        local result = module.test"param"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("test: param"));
    });
  });
}
