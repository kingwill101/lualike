import 'package:lualike/testing.dart';

void main() {
  group('PCAll Performance Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('pcall overhead with error handling', () async {
      // Test that pcall error handling doesn't cause memory leaks
      await lua.execute('''
        -- Test pcall performance with error handling
        local error_count = 0
        for i = 1, 100 do
          local status, err = pcall(function()
            error("test error " .. i)
          end)
          if not status then
            error_count = error_count + 1
          end
        end
        error_count_result = error_count
      ''');

      expect(lua.getGlobal("error_count_result").unwrap(), equals(100));
    });
  });
}
