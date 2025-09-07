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
  });
}
