import 'package:lualike_test/test.dart';

// Mirrors gc.lua lines 647–664: inside a __gc finalizer, the kv weak table in
// the object's metatable must be empty.
void main() {
  test('__gc finalizer sees empty kv weak table', () async {
    final lua = LuaLike();
    final code = r'''
      local u = setmetatable({}, { __gc = true })
      local m = getmetatable(u)
      m.x = {[{}] = 1, [0] = {1}}
      setmetatable(m.x, { __mode = 'kv' })
      m.__gc = function(o)
        assert(next(getmetatable(o).x) == nil)
        m = 10
      end
      u, m = nil
      collectgarbage()
      return m
    ''';

    final result = await lua.execute(code) as Value;
    expect(result.unwrap(), equals(10));
  });
}
