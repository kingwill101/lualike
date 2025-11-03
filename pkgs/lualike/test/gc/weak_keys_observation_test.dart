import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test('weak-keys entries observable during __gc and cleared after', () async {
    final bridge = LuaLike();
    await bridge.execute('''
      local a = {}
      local t = {}
      local C = setmetatable({ key = t }, { __mode = 'v' })
      local C1 = setmetatable({ [t] = 1 }, { __mode = 'k' })
      a.x = t
      setmetatable(a, { __gc = function(u)
        assert(C.key == nil)
        assert(type(next(C1)) == 'table')
      end })
      a, t = nil
      collectgarbage(); collectgarbage()
      assert(next(C) == nil and next(C1) == nil)
    ''');
  });
}
