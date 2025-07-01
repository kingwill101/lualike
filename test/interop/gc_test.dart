import 'package:lualike/testing.dart';

void main() {
  group('Garbage Collection', () {
    test('object lifecycle', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        -- Create and abandon objects
        local function createObjects()
          local t1 = {value = "test1"}
          local t2 = {value = "test2"}
          -- t1 and t2 go out of scope
        end

        createObjects()
        collectgarbage("collect")

        -- Check memory usage
        local mem1 = collectgarbage("count")

        -- Create more objects and keep references
        local holder = {}
        for i = 1, 100 do
          holder[i] = {value = "test" .. i}
        end

        local mem2 = collectgarbage("count")
        assert(mem2 > mem1, "Memory should increase with new objects")

        -- Clear references and collect
        holder = nil
        collectgarbage("collect")

        local mem3 = collectgarbage("count")
        assert(mem3 < mem2, "Memory should decrease after collection")
      ''');

      Logger.setEnabled(false);
    });

    test('finalizers', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        local finalized = {}

        -- Create object with finalizer
        local obj = setmetatable({}, {
          __gc = function(self)
            table.insert(finalized, "finalized")
          end
        })

        -- Clear reference and force collection
        obj = nil
        collectgarbage("collect")

        assert(#finalized > 0, "Finalizer should have run")
      ''');

      Logger.setEnabled(false);
    });

    test('oveerroide gc', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
local t = {}
setmetatable(t, {
  __gc = function() print("Finalizer ran!") end
})
t = nil  -- Allow t to be garbage collected
collectgarbage()  -- Force a collection
      ''');

      Logger.setEnabled(false);
    });
  });
}
