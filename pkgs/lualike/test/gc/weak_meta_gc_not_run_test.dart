import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('GC weak-values metatable on metatable', () {
    test('__gc added under weak-values metatable must not run (no os.exit)', () async {
      final bridge = LuaLike();
      // Override os.exit in Lua to avoid process termination and to assert calls.
      await bridge.execute('''
        os_exit_called = false
        os.exit = function(code) os_exit_called = code or true end
        local u = setmetatable({}, { __gc = true })
        setmetatable(getmetatable(u), { __mode = 'v' })
        getmetatable(u).__gc = function(o)
          os.exit(1) -- should not be invoked if collector is ordered correctly
        end
        u = nil
        collectgarbage()
      ''');

      final called = bridge.getGlobal('os_exit_called') as Value;
      expect(called.raw, isFalse,
          reason: 'os.exit was called from __gc set under weak-values metatable; expected not invoked');
    });

    test('__gc added after metatable set (no __gc at set time) must not run', () async {
      final bridge = LuaLike();
      await bridge.execute('''
        os_exit_called_late = false
        os.exit = function(code) os_exit_called_late = code or true end
        local u2 = setmetatable({}, {}) -- no __gc at set time
        getmetatable(u2).__gc = function(o) os.exit(2) end -- added later; not eligible
        u2 = nil
        collectgarbage()
      ''');
      final calledLate = bridge.getGlobal('os_exit_called_late') as Value;
      expect(calledLate.raw, isFalse,
          reason: 'os.exit was called but object became finalizable only after metatable set');
    });
  });
}
