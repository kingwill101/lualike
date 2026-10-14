import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  for (final mode in EngineMode.values) {
    test('math_table_order (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local mt={__lt=function(a,b) return a.n<b.n end};local a,b,c=setmetatable({n=3},mt),setmetatable({n=1},mt),setmetatable({n=2},mt)
assert(rawequal(math.min(a,b),b) and rawequal(math.max(a,b),a));assert(rawequal(math.min(a,b,c),b) and rawequal(math.max(b,c,a),a))
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_strings (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
assert(math.min('9','10')=='10' and math.max('9','10')=='9');assert(math.min('b','a','c')=='a')
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_single (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local t={};assert(rawequal(math.min(t),t) and rawequal(math.max(t),t));assert(math.min(false)==false and math.max(nil)==nil)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_ties (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local a,b={},{};local mt={__lt=function() return false end};setmetatable(a,mt);setmetatable(b,mt);assert(rawequal(math.min(a,b),a) and rawequal(math.max(a,b),a)); assert(math.type(math.min(1,1.0))=='integer' and math.type(math.max(1.0,1))=='float')
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_right_lt (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local a={n=1};local b=setmetatable({n=2},{__lt=function(x,y) return x.n<y.n end});assert(rawequal(math.min(a,b),a) and rawequal(math.max(a,b),b))
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_return_truth (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local a,b={},{};setmetatable(a,{__lt=function() return 0,false end});assert(rawequal(math.min(a,b),b));setmetatable(a,{__lt=function() return false,true end});assert(rawequal(math.max(a,b),a))
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_error_object (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local marker={};local a=setmetatable({},{__lt=function() error(marker) end});for _,f in ipairs({math.min,math.max}) do local ok,e=pcall(f,a,{});assert(not ok and rawequal(e,marker)) end
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_mixed_error (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
assert(not pcall(math.min,1,'2'));assert(not pcall(math.max,'2',1));assert(not pcall(math.min));assert(not pcall(math.max))
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_nan (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local nan=0/0; assert(math.min(1,nan)==1 and math.max(1,nan)==1);assert(math.min(nan,1)~=math.min(nan,1))
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('math_numeric (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
assert(math.min(3,1,2)==1 and math.max(3,1,2)==3);assert(math.min(9007199254740993,9007199254740992.0)==9007199254740992.0)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
  }
}
