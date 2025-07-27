import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('Standard library module equality', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('require("string") == string', () async {
      await lua.execute('''
        local result = require("string") == string
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("table") == table', () async {
      await lua.execute('''
        local result = require("table") == table
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("math") == math', () async {
      await lua.execute('''
        local result = require("math") == math
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("io") == io', () async {
      await lua.execute('''
        local result = require("io") == io
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("os") == os', () async {
      await lua.execute('''
        local result = require("os") == os
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("coroutine") == coroutine', () async {
      await lua.execute('''
        local result = require("coroutine") == coroutine
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("debug") == debug', () async {
      await lua.execute('''
        local result = require("debug") == debug
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require("utf8") == utf8', () async {
      await lua.execute('''
        local result = require("utf8") == utf8
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('modifications to standard library modules are consistent', () async {
      await lua.execute('''
        -- Add a custom function to the string module
        string.custom = function(s) return "custom: " .. s end

        -- Get the module through require
        local str = require("string")

        -- Check if the custom function is available through both references
        local result1 = string.custom("test")
        local result2 = str.custom("test")

        result = result1 == result2 and result1 == "custom: test"
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('package.loaded contains standard library modules', () async {
      await lua.execute('''
        local result = true
        result = result and (package.loaded["string"] == string)
        result = result and (package.loaded["table"] == table)
        result = result and (package.loaded["math"] == math)
        result = result and (package.loaded["io"] == io)
        result = result and (package.loaded["os"] == os)
        result = result and (package.loaded["coroutine"] == coroutine)
        result = result and (package.loaded["debug"] == debug)
        result = result and (package.loaded["utf8"] == utf8)
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('require returns same instance on multiple calls', () async {
      await lua.execute('''
        local str1 = require("string")
        local str2 = require("string")
        local str3 = require("string")

        result = (str1 == str2) and (str2 == str3) and (str1 == string)
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('standard library modules are pre-loaded', () async {
      await lua.execute('''
        -- Check that standard library modules are already in package.loaded
        -- before we call require
        local result = true
        for _, name in ipairs({"string", "table", "math", "io", "os", "coroutine", "debug", "utf8"}) do
          if package.loaded[name] == nil then
            result = false
            break
          end
        end
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });

    test('all standard library modules from attrib.lua test', () async {
      // This replicates the exact test from the Lua test suite
      await lua.execute('''
        assert(require"string" == string)
        assert(require"math" == math)
        assert(require"table" == table)
        assert(require"io" == io)
        assert(require"os" == os)
        assert(require"coroutine" == coroutine)
        result = true
      ''');
      expect(lua.getGlobal("result").unwrap(), equals(true));
    });
  });
}
