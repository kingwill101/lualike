import 'package:lualike_test/test.dart';

void main() {
  group('Garbage Collection', () {
    test('object lifecycle', () async {
      final bridge = LuaLike();

      await bridge.execute('''
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
        -- A second collection is often needed in Lua to collect finalized objects
        collectgarbage("collect")

        local mem3 = collectgarbage("count")
        assert(mem3 < mem2, "Memory should decrease after collection")
      ''');

      Logger.setEnabled(false);
    });

    test('finalizers', () async {
      final bridge = LuaLike();

      await bridge.execute('''
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

    test('override gc', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        local ran = false
        local t = {}
        setmetatable(t, {
          __gc = function() ran = true end
        })
        t = nil  -- Allow t to be garbage collected
        collectgarbage("collect")  -- First collection marks for finalization and runs __gc
        assert(ran, "Finalizer should have run")
      ''');

      Logger.setEnabled(false);
    });
  });
}
