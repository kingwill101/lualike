import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  for (final mode in EngineMode.values) {
    test('remove_last_plus_one (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local reads,writes=0,0
local t=setmetatable({10,20},{__index=function(_,k) assert(k==3); reads=reads+1; return 42 end,__newindex=function(_,k,v) assert(k==3 and v==nil); writes=writes+1 end})
assert(table.remove(t,3)==42 and reads==1 and writes==1 and rawget(t,2)==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('remove_empty_zero (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local reads,writes=0,0
local t=setmetatable({},{__index=function(_,k) assert(k==0); reads=reads+1; return 42 end,__newindex=function(_,k,v) assert(k==0 and v==nil); writes=writes+1 end})
assert(table.remove(t)==42 and reads==1 and writes==1)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('remove_explicit_nil (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local t={10,20}; assert(table.remove(t,nil)==20 and #t==1)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('remove_invalid_bounds (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
for _,pos in ipairs({-1,0,4}) do local t={10,20}; assert(not pcall(table.remove,t,pos)); assert(t[1]==10 and t[2]==20) end
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('remove_write_error (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local marker={}; local t=setmetatable({10},{__index=function() return 42 end,__newindex=function() error(marker) end})
local ok,err=pcall(table.remove,t,2); assert(not ok and rawequal(err,marker) and rawget(t,1)==10)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('remove_proxy_shift (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local data={10,20,30}; local t=setmetatable({},{__len=function() return 3 end,__index=data,__newindex=data})
assert(table.remove(t,1)==10 and data[1]==20 and data[2]==30 and data[3]==nil)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
    test('remove_plain_boundary (${mode.name})', () async {
      final lua = LuaLike(engineMode: mode);
      await lua.execute(r'''
local t={10,20}; assert(table.remove(t,3)==nil and #t==2 and t[2]==20)
verification_result = 'ok'
''');
      expect(lua.getGlobal('verification_result').raw.toString(), 'ok');
    });
  }
}
