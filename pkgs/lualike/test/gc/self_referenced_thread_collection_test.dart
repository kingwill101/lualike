import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  test(
    'self-referenced suspended thread is collected when unreachable',
    () async {
      final lua = LuaLike();

      await lua.execute(r'''
      collected = false
      collectgarbage()
      collectgarbage("stop")

      do
        local function f(param)
          ;(function()
            param = {param, f}
            setmetatable(param, {__gc = function() collected = true end})
            coroutine.yield(100)
          end)()
        end

        local co = coroutine.create(f)
        assert(coroutine.resume(co, co))
      end

      collectgarbage()
      collectgarbage("restart")
    ''');

      expect(lua.getGlobal('collected').unwrap(), isTrue);
    },
  );
}
