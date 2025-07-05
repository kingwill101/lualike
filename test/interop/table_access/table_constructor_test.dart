@Tags(['interop'])
import 'package:lualike/testing.dart';

void main() {
  group('Table Constructor Tests', () {
    test('table constructor with string keys', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        local files = {
          ["names.lua"] = "do return {...} end\\n",
          ["err.lua"] = "B = 15; a = a + 1;",
          ["synerr.lua"] = "B =",
          ["A.lua"] = "",
          ["B.lua"] = "assert(...=='B');require 'A'",
          ["A.lc"] = "",
          ["A"] = "",
          ["L"] = "",
          ["XXxX"] = "",
          ["C.lua"] = "package.loaded[...] = 25; require'C'"
        }
      ''');

      var files = bridge.getGlobal('files') as Value;
      var filesMap = files.unwrap() as Map<dynamic, dynamic>;

      expect(
        filesMap['names.lua'],
        equals('do return {...} end\n'.replaceAll('\\n', '\n')),
      );
      expect(filesMap['err.lua'], equals('B = 15; a = a + 1;'));
      expect(filesMap['synerr.lua'], equals('B ='));
      expect(filesMap['A.lua'], equals(''));
      expect(filesMap['B.lua'], equals("assert(...=='B');require 'A'"));
      expect(filesMap['A.lc'], equals(''));
      expect(filesMap['A'], equals(''));
      expect(filesMap['L'], equals(''));
      expect(filesMap['XXxX'], equals(''));
      expect(filesMap['C.lua'], equals("package.loaded[...] = 25; require'C'"));
    });

    test('mixed table constructor with string and identifier keys', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        local mixed = {
          ["string.key"] = "string key value",
          normal_key = "normal key value",
          ["number"] = 42,
          boolean_value = true
        }
      ''');

      var mixed = bridge.getGlobal('mixed') as Value;
      var mixedMap = mixed.unwrap();
      expect(mixedMap['string.key'], equals('string key value'));
      expect(mixedMap['normal_key'], equals('normal key value'));
      expect(mixedMap['number'], equals(42));
      expect(mixedMap['boolean_value'], equals(true));
    });

    test('nested table constructors with string keys', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        nested = {
          ["outer.key"] = {
            ["inner.key"] = "inner value",
            normal = "normal value"
          },
          normal = {
            ["deep.key"] = "deep value"
          }
        }
      ''');

      var nested = bridge.getGlobal('nested') as Value;
      var nestedMap = nested.unwrap() as Map<dynamic, dynamic>;

      var outerKey = nestedMap['outer.key'] as Map<dynamic, dynamic>;
      expect(outerKey['inner.key'], equals('inner value'));
      expect(outerKey['normal'], equals('normal value'));

      var normal = nestedMap['normal'] as Map<dynamic, dynamic>;
      expect(normal['deep.key'], equals('deep value'));
    });
  });

  group('Table constructor with function calls', () {
    test('varargs at the start', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
local function func()
    return 3, 4
end

local function func2(...)
    return ...
end

local function print_table_contents(tbl)
    local t = '{'
    for k, v in pairs(tbl) do
        t = t .. tostring(k) .. ' = ' ..tostring(v) .. '  '
    end
    return t .. '}'
end
''');

      await bridge.asserts.runs('{ func() }', [3, 4]);
      await bridge.asserts.runs('{ func(), 1, 2}', [3, 1, 2]);
      await bridge.asserts.runs('{ 1,func(), 2, func()}', [1, 3, 2, 3, 4]);
      await bridge.asserts.runs('{func2(1,2,3,4)}', [1, 2, 3, 4]);
      await bridge.asserts.runs('{func2()}', []);
      await bridge.asserts.runs('{func2(1,2)}', [1, 2]);
      await bridge.asserts.runs('{func2(1,2), 3}', [1, 3]);
      await bridge.asserts.runs('{1, func2(2,3), func()}', [1, 2, 3, 4]);
      await bridge.asserts.runs(
        '{1, func2(2,3), inside =print_table_contents({111})}',
        [1, 2, " {1 = 111}"],
      );
    });
  });
}
