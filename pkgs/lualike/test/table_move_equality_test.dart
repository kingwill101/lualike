import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  for (final mode in EngineMode.values) {
    test('move_equal_proxy (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local data={10,20}; local n=0
local mt={__index=data,__newindex=data,__eq=function(a,b) n=n+1; return true end}
local a,b=setmetatable({},mt),setmetatable({},mt)
assert(rawequal(table.move(a,1,2,2,b),b)); assert(n==1 and data[1]==10 and data[2]==10 and data[3]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_right_eq (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local data={10,20}; local n=0
local a=setmetatable({},{__index=data,__newindex=data})
local b=setmetatable({},{__index=data,__newindex=data,__eq=function(x,y) assert(rawequal(x,a)); n=n+1; return true end})
table.move(a,1,2,2,b); assert(n==1 and data[3]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_identical (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local t=setmetatable({10,20},{__eq=function() error('unused') end})
assert(rawequal(table.move(t,1,2,2),t)); assert(t[2]==10 and t[3]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_false_eq (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local a,b={10,20},{}; setmetatable(a,{__eq=function() return false,true end})
table.move(a,1,2,2,b); assert(b[2]==10 and b[3]==20 and a[2]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_truthy_eq (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local data={10,20};local mt={__index=data,__newindex=data,__eq=function() return 0,false end}
local a,b=setmetatable({},mt),setmetatable({},mt); table.move(a,1,2,2,b);assert(data[3]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_eq_error (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local marker={};local a=setmetatable({10,20},{__eq=function() error(marker) end}); local b={}
local ok,err=pcall(table.move,a,1,2,2,b); assert(not ok and rawequal(err,marker) and next(b)==nil)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_no_overlap (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local a=setmetatable({10,20},{__eq=function() error('unused') end});local b={}
table.move(a,1,2,3,b);assert(b[3]==10 and b[4]==20)
table.move(a,1,2,1,b);assert(b[1]==10 and b[2]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('move_empty (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local a=setmetatable({},{__eq=function() error('unused') end});local b={};assert(rawequal(table.move(a,2,1,2,b),b))
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
  }
}
