import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('String gsub empty replacement counting', () {
    test('gsub with empty replacement should count all matches', () async {
      final bridge = LuaLike();

      // Test case from the original bug report
      await bridge.execute('''
        -- Simple test with known pattern
        local test_str = "1234567890abcd5678efgh9012ijkl3456"
        result, count = string.gsub(test_str, "(%d%d%d%d)", "")
      ''');

      expect(
        (bridge.getGlobal('result') as dynamic).raw.toString(),
        equals("90abcdefghijkl"),
      );
      expect((bridge.getGlobal('count') as dynamic).raw, equals(5));
    });

    test('gsub with empty replacement on long string', () async {
      final bridge = LuaLike();

      // Test the exact failing case from a.lua
      await bridge.execute('''
        local x = "01234567890123456789012345678901234567890123456789012345678901234567890123456789"
        local s = ''
        local k = math.min(10, (math.maxinteger // 80) // 2) -- smaller k for test
        for n = 1, k do
          s = s .. x
        end
        s = string.sub(s, 1, 800) -- smaller string for test
        result, count = string.gsub(s, '(%d%d%d%d)', '')
      ''');

      expect(
        (bridge.getGlobal('count') as dynamic).raw,
        equals(200),
      ); // 800 // 4
    });

    test(
      'gsub empty replacement vs non-empty replacement count consistency',
      () async {
        final bridge = LuaLike();

        await bridge.execute('''
        local test_str = "123456789012"

        -- Count with empty replacement
        empty_result, empty_count = string.gsub(test_str, "(%d%d%d%d)", "")

        -- Count with non-empty replacement
        nonempty_result, nonempty_count = string.gsub(test_str, "(%d%d%d%d)", "X")
      ''');

        // Both should have the same count
        expect((bridge.getGlobal('empty_count') as dynamic).raw, equals(3));
        expect((bridge.getGlobal('nonempty_count') as dynamic).raw, equals(3));

        // Results should be different but counts the same
        expect(
          (bridge.getGlobal('empty_result') as dynamic).raw.toString(),
          equals(""),
        );
        expect(
          (bridge.getGlobal('nonempty_result') as dynamic).raw.toString(),
          equals("XXX"),
        );
      },
    );

    test('gsub empty replacement with capture groups', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        local test_str = "abc123def456ghi"
        result, count = string.gsub(test_str, "(%d+)", "")
      ''');

      expect(
        (bridge.getGlobal('result') as dynamic).raw.toString(),
        equals("abcdefghi"),
      );
      expect((bridge.getGlobal('count') as dynamic).raw, equals(2));
    });

    test('gsub empty replacement with zero matches', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        local test_str = "abcdef"
        result, count = string.gsub(test_str, "(%d+)", "")
      ''');

      expect(
        (bridge.getGlobal('result') as dynamic).raw.toString(),
        equals("abcdef"),
      );
      expect((bridge.getGlobal('count') as dynamic).raw, equals(0));
    });

    test('gsub empty replacement with limit parameter', () async {
      final bridge = LuaLike();

      await bridge.execute('''
        local test_str = "123456789012345"
        result, count = string.gsub(test_str, "(%d%d)", "", 2) -- limit to 2 replacements
      ''');

      expect(
        (bridge.getGlobal('result') as dynamic).raw.toString(),
        equals("56789012345"),
      );
      expect((bridge.getGlobal('count') as dynamic).raw, equals(2));
    });
  });
}
