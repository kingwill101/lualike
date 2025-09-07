import 'package:lualike_test/test.dart';

void main() {
  group('load() with reader function', () {
    late LuaLike lua;
    setUp(() => lua = LuaLike());

    test('loads simple chunk from string', () async {
      await lua.execute(r'''
        a = assert(load("return '\\0'", "modname", "t", _G))
      ''');
      final res = await lua.execute('return a()') as Value;
      expect(res.unwrap(), equals('\u0000'));
      final src = await lua.execute('return debug.getinfo(a).source') as Value;
      expect(src.unwrap(), equals('modname'));
    });

    test('loads via reader function', () async {
      await lua.execute(r'''
        local x = "return '\\0'"
        local function read1 (x)
          local i = 0
          return function ()
            i=i+1
            return string.sub(x, i, i)
          end
        end
        a = assert(load(read1(x), "modname", "t", _G))
      ''');
      final res = await lua.execute('return a()') as Value;
      expect(res.unwrap(), equals('\u0000'));
      final src = await lua.execute('return debug.getinfo(a).source') as Value;
      expect(src.unwrap(), equals('modname'));
    });

    test('handles invalid reader function return types', () async {
      // Test reader function returning boolean
      await lua.execute(r'''
        f, err = load(function() return true end)
      ''');
      final f = lua.getGlobal('f') as Value;
      final err = lua.getGlobal('err') as Value;
      expect(f.unwrap(), isNull);
      expect(err.unwrap(), equals('reader function must return a string'));

      // Test reader function returning number
      await lua.execute(r'''
        f2, err2 = load(function() return 123 end)
      ''');
      final f2 = lua.getGlobal('f2') as Value;
      final err2 = lua.getGlobal('err2') as Value;
      expect(f2.unwrap(), isNull);
      expect(err2.unwrap(), equals('reader function must return a string'));

      // Test reader function returning table
      await lua.execute(r'''
        f3, err3 = load(function() return {} end)
      ''');
      final f3 = lua.getGlobal('f3') as Value;
      final err3 = lua.getGlobal('err3') as Value;
      expect(f3.unwrap(), isNull);
      expect(err3.unwrap(), equals('reader function must return a string'));

      // Test that assertion fails as expected (this was the original infinite loop case)
      final result =
          await lua.execute('return not load(function () return true end)')
              as Value;
      expect(result.unwrap(), equals(true));
    });
  });
}
