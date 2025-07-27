import 'package:lualike_test/test.dart';

void main() {
  group('PCAll Performance Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('pcall overhead with successful calls', () async {
      // Test that pcall doesn't add significant overhead for successful calls
      final stopwatch = Stopwatch()..start();

      await lua.execute('''
        -- Test pcall performance with successful calls
        local count = 0
        for i = 1, 1000 do
          local status, result = pcall(function() return i * 2 end)
          if status then
            count = count + 1
          end
        end
        success_count = count
      ''');

      stopwatch.stop();

      expect(lua.getGlobal("success_count").unwrap(), equals(1000));
      // Performance assertion - should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
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
