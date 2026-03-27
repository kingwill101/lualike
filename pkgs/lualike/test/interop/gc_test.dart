import 'package:lualike_test/test.dart';

void main() {
  group('Garbage Collection', () {
    test('object lifecycle', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        -- `collectgarbage("count")` is allocator- and accounting-dependent, so
        -- use weak references to assert object liveness directly instead of
        -- assuming heap usage must fall monotonically after a collection.
        local refs = setmetatable({}, {__mode = "v"})

        do
          local holder = {}
          for i = 1, 100 do
            local obj = {value = i}
            holder[i] = obj
            refs[i] = obj
          end

          assert(refs[1] ~= nil and refs[100] ~= nil,
            "Weak table should see live objects while strong references exist")
        end

        collectgarbage("collect")
        collectgarbage("collect")
        assert(next(refs) == nil,
          "Objects should disappear once only weak references remain")
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
