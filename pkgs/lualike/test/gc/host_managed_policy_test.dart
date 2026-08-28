import 'package:lualike/lualike.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:test/test.dart';

Object? globalRaw(LuaLike lua, String name) => rawLuaSlot(lua.getGlobal(name));

void main() {
  group('host-managed GC policy', () {
    test('default policy retains the Lua-compatible collector', () {
      final lua = LuaLike();

      expect(lua.vm.gc.policy, LuaGcPolicy.luaCompatible);
      expect(lua.vm.gc.isHostManaged, isFalse);
      expect(lua.vm.gc.youngGen.objects, isNotEmpty);
    });

    for (final mode in EngineMode.values) {
      test(
        '$mode leaves reclamation to Dart without dropping API calls',
        () async {
          final lua = LuaLike(
            engineMode: mode,
            gcPolicy: LuaGcPolicy.hostManaged,
          );

          await lua.execute(r'''
          weak = setmetatable({}, {__mode = "v"})
          do
            local candidate = {}
            weak[1] = candidate
          end

          finalized = false
          do
            local doomed = setmetatable({}, {
              __gc = function() finalized = true end,
            })
          end

          closed = false
          do
            local resource <close> = setmetatable({}, {
              __close = function() closed = true end,
            })
          end

          collect_result = collectgarbage("collect")
          count_result = collectgarbage("count")
          running_result = collectgarbage("isrunning")
          step_result = collectgarbage("step")
          weak_survives = weak[1] ~= nil
        ''');

          expect(lua.vm.gc.policy, LuaGcPolicy.hostManaged);
          expect(lua.vm.gc.isStopped, isTrue);
          expect(lua.vm.gc.youngGen.objects, isEmpty);
          expect(lua.vm.gc.oldGen.objects, isEmpty);
          expect(lua.vm.gc.estimateMemoryUse(), 0);
          expect(globalRaw(lua, 'collect_result'), isTrue);
          expect(globalRaw(lua, 'count_result'), 0.0);
          expect(globalRaw(lua, 'running_result'), isFalse);
          expect(globalRaw(lua, 'step_result'), isFalse);
          expect(globalRaw(lua, 'weak_survives'), isTrue);
          expect(globalRaw(lua, 'finalized'), isFalse);
          expect(globalRaw(lua, 'closed'), isTrue);
        },
      );
    }
  });
}
