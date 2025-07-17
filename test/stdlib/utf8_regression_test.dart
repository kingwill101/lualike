import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('UTF-8 Regression Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    group('String Type Compatibility', () {
      test('utf8 functions work with regular Dart Strings', () async {
        await lua.execute('''
          local s = "hello"
          local s2 = string.upper(s)  -- This returns a regular Dart String

          -- utf8 functions should work with both LuaString and regular Strings
          len1 = utf8.len(s)
          len2 = utf8.len(s2)

          codes1 = {}
          for p, c in utf8.codes(s) do
            table.insert(codes1, c)
          end

          codes2 = {}
          for p, c in utf8.codes(s2) do
            table.insert(codes2, c)
          end

          cp1 = utf8.codepoint(s, 1, 1)
          cp2 = utf8.codepoint(s2, 1, 1)

          off1 = utf8.offset(s, 2)
          off2 = utf8.offset(s2, 2)
        ''');

        expect((lua.getGlobal('len1') as Value).raw, equals(5));
        expect((lua.getGlobal('len2') as Value).raw, equals(5));

        final codes1 = (lua.getGlobal('codes1') as Value).raw as Map;
        final codes2 = (lua.getGlobal('codes2') as Value).raw as Map;
        expect(codes1.length, equals(5));
        expect(codes2.length, equals(5));

        expect((lua.getGlobal('cp1') as Value).raw, equals(104)); // 'h'
        expect((lua.getGlobal('cp2') as Value).raw, equals(72)); // 'H'

        expect((lua.getGlobal('off1') as Value).raw, equals(2));
        expect((lua.getGlobal('off2') as Value).raw, equals(2));
      });

      test('utf8 functions work with LuaString objects', () async {
        await lua.execute(r'''
          -- Create strings with high bytes that should be LuaString objects
          local s = "\xC2\x80"  -- UTF-8 for U+0080

          len = utf8.len(s)
          cp = utf8.codepoint(s, 1, 1)
          off = utf8.offset(s, 1)

          codes = {}
          for p, c in utf8.codes(s) do
            table.insert(codes, c)
          end
        ''');

        expect((lua.getGlobal('len') as Value).raw, equals(1));
        expect((lua.getGlobal('cp') as Value).raw, equals(128)); // U+0080
        expect((lua.getGlobal('off') as Value).raw, equals(1));

        final codes = (lua.getGlobal('codes') as Value).raw as Map;
        expect(codes.length, equals(1));
        expect((codes[Value(1)] as Value).raw, equals(128));
      });
    });

    group('Error Handling', () {
      test('utf8.codes throws error on invalid UTF-8', () async {
        await lua.execute(r'''
          function test_invalid_utf8(s)
            local success, err = pcall(function()
              for c in utf8.codes(s) do
                -- This should trigger an error
              end
            end)
            return success, err
          end

          -- Test various invalid UTF-8 sequences
          s1, e1 = test_invalid_utf8("\xFF")           -- Invalid byte
          s2, e2 = test_invalid_utf8("\x80")           -- Continuation byte
          s3, e3 = test_invalid_utf8("ab\xFF")         -- Invalid byte in middle
          s4, e4 = test_invalid_utf8("\xC2")           -- Incomplete sequence
        ''');

        // All should fail (success = false)
        expect((lua.getGlobal('s1') as Value).raw, equals(false));
        expect((lua.getGlobal('s2') as Value).raw, equals(false));
        expect((lua.getGlobal('s3') as Value).raw, equals(false));
        expect((lua.getGlobal('s4') as Value).raw, equals(false));

        // All errors should contain "invalid UTF-8 code"
        final e1 = (lua.getGlobal('e1') as Value).raw.toString();
        final e2 = (lua.getGlobal('e2') as Value).raw.toString();
        final e3 = (lua.getGlobal('e3') as Value).raw.toString();
        final e4 = (lua.getGlobal('e4') as Value).raw.toString();

        expect(e1, contains('invalid UTF-8 code'));
        expect(e2, contains('invalid UTF-8 code'));
        expect(e3, contains('invalid UTF-8 code'));
        expect(e4, contains('invalid UTF-8 code'));
      });

      test('utf8.len returns error position for invalid UTF-8', () async {
        await lua.execute(r'''
          -- Test error position reporting
          len1, pos1 = utf8.len("abc\xFF")     -- Invalid at position 4
          len2, pos2 = utf8.len("\x80hello")   -- Invalid at position 1
          len3, pos3 = utf8.len("hel\x80lo")   -- Invalid at position 4
        ''');

        // All should return nil for length
        expect((lua.getGlobal('len1') as Value).raw, equals(null));
        expect((lua.getGlobal('len2') as Value).raw, equals(null));
        expect((lua.getGlobal('len3') as Value).raw, equals(null));

        // Positions should be correct
        expect((lua.getGlobal('pos1') as Value).raw, equals(4));
        expect((lua.getGlobal('pos2') as Value).raw, equals(1));
        expect((lua.getGlobal('pos3') as Value).raw, equals(4));
      });

      test('utf8.offset throws error for continuation bytes', () async {
        await lua.execute(r'''
          function test_continuation_error(s, n, i)
            local success, err = pcall(utf8.offset, s, n, i)
            return success, err
          end

          -- Test continuation byte errors
          s1, e1 = test_continuation_error("\xC2\x80", 1, 2)  -- Position 2 is continuation
          s2, e2 = test_continuation_error("\x80", 1)         -- Position 1 is continuation
        ''');

        expect((lua.getGlobal('s1') as Value).raw, equals(false));
        expect((lua.getGlobal('s2') as Value).raw, equals(false));

        final e1 = (lua.getGlobal('e1') as Value).raw.toString();
        final e2 = (lua.getGlobal('e2') as Value).raw.toString();

        expect(e1, contains('continuation byte'));
        expect(e2, contains('continuation byte'));
      });

      test('utf8 functions throw error for out of bounds', () async {
        await lua.execute(r'''
          function test_bounds_error(func, ...)
            local success, err = pcall(func, ...)
            return success, err
          end

          -- Test various out of bounds errors
          s1, e1 = test_bounds_error(utf8.len, "abc", 0, 2)     -- Start < 1
          s2, e2 = test_bounds_error(utf8.len, "abc", 1, 4)     -- End > length
          s3, e3 = test_bounds_error(utf8.offset, "abc", 1, 5)  -- Position > length + 1
          s4, e4 = test_bounds_error(utf8.offset, "abc", 1, -4) -- Position < -(length + 1)
          s5, e5 = test_bounds_error(utf8.codepoint, "abc", 5)  -- Position > length
        ''');

        // All should fail
        expect((lua.getGlobal('s1') as Value).raw, equals(false));
        expect((lua.getGlobal('s2') as Value).raw, equals(false));
        expect((lua.getGlobal('s3') as Value).raw, equals(false));
        expect((lua.getGlobal('s4') as Value).raw, equals(false));
        expect((lua.getGlobal('s5') as Value).raw, equals(false));

        // All errors should contain "out of bounds" or "position out of bounds"
        final errors = [
          (lua.getGlobal('e1') as Value).raw.toString(),
          (lua.getGlobal('e2') as Value).raw.toString(),
          (lua.getGlobal('e3') as Value).raw.toString(),
          (lua.getGlobal('e4') as Value).raw.toString(),
          (lua.getGlobal('e5') as Value).raw.toString(),
        ];

        for (final error in errors) {
          expect(
            error,
            anyOf(
              contains('out of bounds'),
              contains('position out of bounds'),
            ),
          );
        }
      });
    });

    group('UTF-8 Character Processing', () {
      test('utf8.char creates valid UTF-8 sequences', () async {
        await lua.execute('''
          -- Test basic ASCII
          s1 = utf8.char(65, 66, 67)  -- "ABC"
          len1 = utf8.len(s1)
          cp1 = {utf8.codepoint(s1, 1, -1)}

          -- Test UTF-8 characters
          s2 = utf8.char(0x80, 0x7FF, 0x800)  -- Various UTF-8 ranges
          len2 = utf8.len(s2)
          cp2 = {utf8.codepoint(s2, 1, -1)}

          -- Test empty
          s3 = utf8.char()
          len3 = utf8.len(s3)
        ''');

        expect((lua.getGlobal('len1') as Value).raw, equals(3));
        final cp1 = (lua.getGlobal('cp1') as Value).raw as Map;
        expect([
          (cp1[Value(1)] as Value).raw,
          (cp1[Value(2)] as Value).raw,
          (cp1[Value(3)] as Value).raw,
        ], equals([65, 66, 67]));

        expect((lua.getGlobal('len2') as Value).raw, equals(3));
        final cp2 = (lua.getGlobal('cp2') as Value).raw as Map;
        expect([
          (cp2[Value(1)] as Value).raw,
          (cp2[Value(2)] as Value).raw,
          (cp2[Value(3)] as Value).raw,
        ], equals([0x80, 0x7FF, 0x800]));

        expect((lua.getGlobal('len3') as Value).raw, equals(0));
      });

      test('utf8.char throws error for invalid codepoints', () async {
        await lua.execute('''
          function test_char_error(cp)
            local success, err = pcall(utf8.char, cp)
            return success, err
          end

          -- Test invalid codepoints
          s1, e1 = test_char_error(-1)              -- Negative
          s2, e2 = test_char_error(0x7FFFFFFF + 1)  -- Too large
        ''');

        expect((lua.getGlobal('s1') as Value).raw, equals(false));
        expect((lua.getGlobal('s2') as Value).raw, equals(false));

        final e1 = (lua.getGlobal('e1') as Value).raw.toString();
        final e2 = (lua.getGlobal('e2') as Value).raw.toString();

        expect(e1, contains('value out of range'));
        expect(e2, contains('value out of range'));
      });
    });

    group('UTF-8 Pattern Matching', () {
      test('utf8.charpattern matches UTF-8 characters', () async {
        await lua.execute(r'''
          -- Test ASCII characters
          count1 = 0
          for c in string.gmatch("hello", utf8.charpattern) do
            count1 = count1 + 1
          end

          -- Test with high bytes (using hex escapes)
          count2 = 0
          for c in string.gmatch("\xC2\x80\xDF\xBF", utf8.charpattern) do
            count2 = count2 + 1
          end

          -- Test mixed content
          count3 = 0
          for c in string.gmatch("a\xC2\x80b", utf8.charpattern) do
            count3 = count3 + 1
          end
        ''');

        expect(
          (lua.getGlobal('count1') as Value).raw,
          equals(5),
        ); // 5 ASCII chars
        expect(
          (lua.getGlobal('count2') as Value).raw,
          equals(2),
        ); // 2 UTF-8 chars
        expect(
          (lua.getGlobal('count3') as Value).raw,
          equals(3),
        ); // a + UTF-8 + b
      });
    });

    group('Edge Cases', () {
      test('utf8 functions handle empty strings', () async {
        await lua.execute('''
          s = ""
          len = utf8.len(s)

          codes = {}
          for p, c in utf8.codes(s) do
            table.insert(codes, c)
          end

          cp = {utf8.codepoint(s, 1, 0)}  -- Empty range
          off = utf8.offset(s, 1)         -- Should return nil
        ''');

        expect((lua.getGlobal('len') as Value).raw, equals(0));

        final codes = (lua.getGlobal('codes') as Value).raw as Map;
        expect(codes.length, equals(0));

        final cp = (lua.getGlobal('cp') as Value).raw as Map;
        expect(cp.length, equals(0));

        expect(
          (lua.getGlobal('off') as Value).raw,
          equals(1),
        ); // Position 1 for empty string
      });

      test('utf8.offset handles special cases', () async {
        await lua.execute(r'''
          s = "\xC2\x80\xC2\x81"  -- Two 2-byte UTF-8 characters

          -- Test n=0 (find character start)
          off1 = utf8.offset(s, 0, 1)  -- Should return 1
          off2 = utf8.offset(s, 0, 3)  -- Should return 3

          -- Test negative n (backward)
          off3 = utf8.offset(s, -1, 5)  -- From end, go back 1 char

          -- Test beyond end
          off4 = utf8.offset(s, 3)      -- Should return nil (only 2 chars)
        ''');

        expect((lua.getGlobal('off1') as Value).raw, equals(1));
        expect((lua.getGlobal('off2') as Value).raw, equals(3));
        expect((lua.getGlobal('off3') as Value).raw, equals(3));
        expect(
          (lua.getGlobal('off4') as Value).raw,
          equals(5),
        ); // Position after last byte
      });
    });
  });
}
