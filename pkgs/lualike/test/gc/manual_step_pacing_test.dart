import 'package:lualike/src/config.dart';
import 'package:lualike/src/executor.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  const source = r'''
    local function dosteps(size)
      collectgarbage("collect")
      local live = {}
      for i = 1, 100 do
        live[i] = {{}}
        local dead = {}
      end
      local count = 0
      repeat
        count = count + 1
        assert(count < 10000)
      until collectgarbage("step", size)
      return count
    end

    collectgarbage("stop")
    local large = dosteps(10)
    local small = dosteps(2)
    collectgarbage("restart")
    return large, small
  ''';

  for (final mode in [EngineMode.ir, EngineMode.luaBytecode]) {
    test('$mode preserves manual step-size pacing', () async {
      final result = await executeCode(source, mode: mode) as Value;
      final values = result.raw as List<dynamic>;
      final large = rawLuaSlot(values[0]) as int;
      final small = rawLuaSlot(values[1]) as int;

      expect(large, greaterThan(1));
      expect(small, greaterThan(large));
    });
  }
}
