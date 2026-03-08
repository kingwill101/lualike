import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('Debug library tests', () {
    late LuaLike luaLike;

    setUp(() {
      luaLike = LuaLike();
    });

    test('debug library should be available', () async {
      const script = '''
      return type(debug)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'table');
    });

    test('debug.getinfo function should exist', () async {
      const script = '''
      return type(debug.getinfo)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, 'function');
    });

    test('debug.getinfo should accept a level parameter', () async {
      const script = '''
      local status, result = pcall(function() 
        return debug.getinfo(1) 
      end)
      return status
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isTrue);
    });

    test('debug.getinfo should return a table', () async {
      const script = '''
      local status, result = pcall(function()
        local info = debug.getinfo(1)
        return type(info)
      end)
      
      return {status = status, result = result}
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<Map>());

      final resultMap = result.raw as Map;
      expect(resultMap['status'], isTrue);
      expect(resultMap['result'].raw, 'table');
    });

    test('debug.getinfo should include path in source field', () async {
      const scriptPath = 'custom_test_script.lua';
      const script = '''
      local function check_source()
        local info = debug.getinfo(1)
        return info.source
      end
      return check_source()
      ''';

      final result = (await luaLike.execute(script, scriptPath: scriptPath));
      // We expect the source to include the @ symbol followed by the script path
      expect(result.raw is String, isTrue);
      expect((result.raw as String).contains('@'), isTrue);
    });

    test('debug.getinfo should reject invalid option strings', () async {
      const script = '''
      local ok1 = pcall(debug.getinfo, print, "X")
      local ok2 = pcall(debug.getinfo, 0, ">")
      return ok1, ok2
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[false, false]),
      );
    });

    test('debug.getinfo should return nil for invalid stack levels', () async {
      const script = '''
      return debug.getinfo(1000), debug.getinfo(-1)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[null, null]),
      );
    });

    test('debug.getinfo should report builtin functions as C', () async {
      const script = '''
      local info = debug.getinfo(print)
      return info.what, info.short_src
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>['C', '[C]']),
      );
    });

    test('debug.getinfo should format load chunk names like Lua', () async {
      const script = r'''
      local a = "function f () end"
      local function dostring (s, x) return load(s, x)() end
      dostring(a)
      local infoA = debug.getinfo(f)
      dostring(a, "")
      local infoEmpty = debug.getinfo(f)
      dostring(a, '[string "xuxu"]')
      local infoCustom = debug.getinfo(f)
      return infoA.short_src, infoEmpty.short_src, infoCustom.short_src
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>[
          '[string "function f () end"]',
          '[string ""]',
          '[string "[string "xuxu"]"]',
        ]),
      );
    });

    test('debug.getinfo should classify active field calls', () async {
      const script = r'''
      local g = {x = function ()
        local info = debug.getinfo(1)
        return info.name, info.namewhat
      end}
      local function f() return g.x() end
      return f()
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      expect(
        (result.raw as List).map((value) => (value as Value).raw).toList(),
        equals(<Object?>['x', 'field']),
      );
    });

    test('debug.getinfo should prefer caller local alias names', () async {
      const script = r'''
      local function f(x, expected)
        local info = debug.getinfo(1)
        return info.name, info.namewhat, x
      end
      local function g(x)
        return x('a', 'x')
      end
      return g(f)
      ''';

      final result = await luaLike.execute(script);
      expect(result.raw, isA<List>());
      final values = (result.raw as List).cast<Value>();
      expect(values[0].raw, 'x');
      expect(values[1].raw, 'local');
      final third = values[2].raw;
      final thirdString = switch (third) {
        final Value nested => nested.raw.toString(),
        _ => third.toString(),
      };
      expect(thirdString, 'a');
    });
  });
}
