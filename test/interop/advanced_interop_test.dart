import 'package:lualike/testing.dart';

void main() {
  group('Advanced Interop Features', () {
    test('nested table assignment with direct indexing', () async {
      final bridge = LuaLike();

      // Create a table with numeric indices
      await bridge.runCode('''
        words = {}
        for i = 1, 5 do
          words[i] = "word" .. i
        end
      ''');

      // Test direct assignment to indexed element
      await bridge.runCode('''
        words[3] = 11
      ''');

      var words = bridge.getGlobal('words') as Value;
      var wordsMap = words.raw as Map<dynamic, dynamic>;

      // Check that the assignment worked
      expect((wordsMap[3] as Value).unwrap(), equals(11));
      expect((wordsMap[1] as Value).unwrap(), equals("word1"));
      expect((wordsMap[2] as Value).unwrap(), equals("word2"));
    });

    test('nested table assignment with direct indexing (workaround)', () async {
      final bridge = LuaLike();

      // Create a table with numeric indices (without using for loop)
      await bridge.runCode('''
        words = {}
        words[1] = "word1"
        words[2] = "word2"
        words[3] = "word3"
        words[4] = "word4"
        words[5] = "word5"
      ''');

      // Test direct assignment to indexed element
      await bridge.runCode('''
        words[3] = 11
      ''');

      var words = bridge.getGlobal('words') as Value;
      var wordsMap = words.raw as Map<dynamic, dynamic>;

      // Check that the assignment worked
      expect((wordsMap[3] as Value).unwrap(), equals(11));
      expect((wordsMap[1] as Value).unwrap(), equals("word1"));
      expect((wordsMap[2] as Value).unwrap(), equals("word2"));
    });

    test('deeply nested table assignment with indexing', () async {
      final bridge = LuaLike();

      // Create a nested table structure
      await bridge.runCode('''
        words = {}
        words.something = {}
        words.something.value = {}
        -- FIXME: Our for loop implementation has an issue with bounds checking
        -- Error: "For loop bounds must be numbers"
        -- This is valid Lua syntax and should be supported
        for i = 1, 5 do
          words.something.value[i] = "deep" .. i
        end
      ''');

      // Test assignment to deeply nested indexed element
      await bridge.runCode('''
        words.something.value[3] = 11
      ''');

      var words = bridge.getGlobal('words') as Value;
      var something = (words.raw as Map)['something'] as Value;
      var value = (something.raw as Map)['value'] as Value;
      var valueMap = value.unwrap() as Map<dynamic, dynamic>;

      // Check that the deep assignment worked
      expect(valueMap[3], equals(11));
      expect(valueMap[1], equals("deep1"));
      expect(valueMap[2], equals("deep2"));
    });

    test('deeply nested table assignment with indexing (workaround)', () async {
      final bridge = LuaLike();

      // Create a nested table structure (without using for loop)
      await bridge.runCode('''
        words = {}
        words.something = {}
        words.something.value = {}
        words.something.value[1] = "deep1"
        words.something.value[2] = "deep2"
        words.something.value[3] = "deep3"
        words.something.value[4] = "deep4"
        words.something.value[5] = "deep5"
      ''');

      // Test assignment to deeply nested indexed element
      await bridge.runCode('''
        words.something.value[3] = 11
      ''');

      var words = bridge.getGlobal('words') as Value;
      var something = (words.raw as Map)['something'] as Value;
      var value = (something.raw as Map)['value'] as Value;
      var valueMap = value.unwrap() as Map<dynamic, dynamic>;

      // Check that the deep assignment worked
      expect(valueMap[3], equals(11));
      expect(valueMap[1], equals("deep1"));
      expect(valueMap[2], equals("deep2"));
    });

    test('require module functionality', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        function M.start()
          return "GC tracing started"
        end

        function M.stop()
          return "GC tracing stopped"
        end

        return M
      ''');

      // Test require functionality
      // FIXME: Our parser doesn't support method chaining on require results
      // Error: FormatException: line 1, column 42: Expected: '"', '#', ''', '(', etc.
      // This is valid Lua syntax and should be supported
      await bridge.runCode('''
        local result = require("tracegc").start()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("GC tracing started"));
    });

    test('require module functionality (workaround)', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        function M.start()
          return "GC tracing started"
        end

        function M.stop()
          return "GC tracing stopped"
        end

        return M
      ''');

      // Test require functionality (using workaround)
      await bridge.runCode('''
        local tracegc = require("tracegc")
        local result = tracegc.start()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("GC tracing started"));
    });

    test('table property syntax', () async {
      final bridge = LuaLike();

      // Register a custom table library extension
      await bridge.runCode('''
        -- Extend table library with a property function
        table.property = function(propName)
          return "Property: " .. propName
        end

        -- Test the function
        local result = table.property("first")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("Property: first"));
    });

    test('table property syntax with alternative call style', () async {
      final bridge = LuaLike();

      // Register a custom table library extension
      await bridge.runCode('''
        -- Extend table library with a property function
        table.property = function(propName)
          return "Property: " .. propName
        end

        -- Test the function with alternative call syntax (no parentheses)
        -- FIXME: Our parser should support function calls without parentheses
        -- This is valid Lua syntax and should be supported
        local result = table.property"first"
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("Property: first"));
    });

    test(
      'table property syntax with alternative call style (workaround)',
      () async {
        final bridge = LuaLike();

        // Register a custom table library extension
        await bridge.runCode('''
        -- Extend table library with a property function
        table.property = function(propName)
          return "Property: " .. propName
        end

        -- Test the function with standard call syntax
        local result = table.property("first")
      ''');

        var result = bridge.getGlobal('result');
        expect((result as Value).unwrap(), equals("Property: first"));
      },
    );

    test('require with alternative call style', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        function M.start()
          return "GC tracing started"
        end

        function M.stop()
          return "GC tracing stopped"
        end

        return M
      ''');

      // Test require functionality with alternative call syntax
      // FIXME: Our parser should support function calls without parentheses
      // This is valid Lua syntax and should be supported
      await bridge.runCode('''
        local result = require"tracegc".start()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("GC tracing started"));
    });

    test('require with alternative call style (workaround)', () async {
      final bridge = LuaLike();

      // Register a virtual module for testing
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        function M.start()
          return "GC tracing started"
        end

        function M.stop()
          return "GC tracing stopped"
        end

        return M
      ''');

      // Test require functionality with standard call syntax
      await bridge.runCode('''
        local tracegc = require("tracegc")
        local result = tracegc.start()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).unwrap(), equals("GC tracing started"));
    });

    test('combined require and table property syntax', () async {
      final bridge = LuaLike();

      // Register a virtual module with table property functionality
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        M.status = "inactive"

        function M.start()
          M.status = "active"
          return "GC tracing started"
        end

        -- Add a property method
        M.property = function(propName)
          return "TracerProperty: " .. propName
        end

        return M
      ''');

      await bridge.runCode('''
        local m = require("tracegc")
        m.start()
        local propResult = m.property("status")
        local status = m.status
      ''');

      var propResult = bridge.getGlobal('propResult');
      var status = bridge.getGlobal('status');

      expect((propResult as Value).unwrap(), equals("TracerProperty: status"));
      expect((status as Value).unwrap(), equals("active"));
    });

    test('combined require and table property syntax (workaround)', () async {
      final bridge = LuaLike();

      // Register a virtual module with table property functionality
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        M.status = "inactive"

        function M.start()
          M.status = "active"
          return "GC tracing started"
        end

        -- Add a property method
        M.property = function(propName)
          return "TracerProperty: " .. propName
        end

        return M
      ''');

      // Test combined require and property syntax (using workaround)
      await bridge.runCode('''
        local tracegc = require("tracegc")
        tracegc.start()
        local propResult = tracegc.property("status")
        local status = tracegc.status
      ''');

      var propResult = bridge.getGlobal('propResult');
      var status = bridge.getGlobal('status');

      expect((propResult as Value).unwrap(), equals("TracerProperty: status"));
      expect((status as Value).unwrap(), equals("active"));
    });

    test('combined alternative call styles', () async {
      final bridge = LuaLike();

      // Register a virtual module with table property functionality
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        M.status = "inactive"

        function M.start()
          M.status = "active"
          return "GC tracing started"
        end

        -- Add a property method
        M.property = function(propName)
          return "TracerProperty: " .. propName
        end

        return M
      ''');

      // Test combined alternative call syntaxes
      // FIXME: Our parser should support function calls without parentheses
      // and method chaining on require results
      // This is valid Lua syntax and should be supported
      await bridge.runCode('''
        local tracegc = require"tracegc"
        tracegc.start()
        local propResult = tracegc.property"status"
        local status = tracegc.status
      ''');

      var propResult = bridge.getGlobal('propResult');
      var status = bridge.getGlobal('status');

      expect((propResult as Value).unwrap(), equals("TracerProperty: status"));
      expect((status as Value).unwrap(), equals("active"));
    });

    test('combined alternative call styles (workaround)', () async {
      final bridge = LuaLike();

      // Register a virtual module with table property functionality
      bridge.vm.fileManager.registerVirtualFile('tracegc.lua', '''
        local M = {}

        M.status = "inactive"

        function M.start()
          M.status = "active"
          return "GC tracing started"
        end

        -- Add a property method
        M.property = function(propName)
          return "TracerProperty: " .. propName
        end

        return M
      ''');

      // Test with standard call syntax
      await bridge.runCode('''
        local tracegc = require("tracegc")
        tracegc.start()
        local propResult = tracegc.property("status")
        local status = tracegc.status
      ''');

      var propResult = bridge.getGlobal('propResult');
      var status = bridge.getGlobal('status');

      expect((propResult as Value).unwrap(), equals("TracerProperty: status"));
      expect((status as Value).unwrap(), equals("active"));
    });
  });
}
