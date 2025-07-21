import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('literals.lua long string cases', () {
    test('execute long string snippets without errors', () async {
      final lua = LuaLike();
      await lua.execute(r'''
local function dostring(x) return assert(load(x), "")() end
local b = string.rep("0123456789", 96)
assert(#b == 960)
prog = [=[
local a1 = [["this is a 'string' with several 'quotes'"]]
local a2 = "'quotes'"
assert(string.find(a1, a2) == 34)
a1 = [==[temp = [[an arbitrary value]]; ]==]
assert(load(a1))()
assert(temp == 'an arbitrary value')
_G.temp = nil
local b = string.rep("0123456789", 96)
assert(#b == 960)
local a = string.rep("0123456789", 186) .. "012"
assert(#a == 1863)
assert(string.sub(a, 1, 40) == string.sub(b, 1, 40))
x = 1
]=]
_G.x = nil
dostring(prog)
assert(x)
_G.x = nil

local a = [==[]=]==]
assert(a == "]=")
a = [==[[===[[=[]]=][====[]]===]===]==]
assert(a == "[===[[=[]]=][====[]]===]===")
a = [====[[===[[=[]]=][====[]]===]===]====]
assert(a == "[===[[=[]]=][====[]]===]===")
a = [=[]]]]]]]]]=]
assert(a == "]]]]]]]]")
''');
    });
  });
}
