import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('String Regression Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    group('String.rep High-Byte Handling', () {
      test('string.rep preserves high bytes (253) correctly', () async {
        // This was the specific failing case from strings.lua
        await lua.execute(r'''
          local input = 't\xFDs\00t\xFD'
          local result = string.rep(input, 2)
          local expected = 't\xFDs\0t\xFDt\xFDs\000t\xFD'
          equal = result == expected
          length = #result
          b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12 = string.byte(result, 1, -1)
        ''');

        expect(
          (lua.getGlobal('equal') as Value).raw,
          isTrue,
          reason: 'string.rep should preserve high bytes correctly',
        );
        expect(
          (lua.getGlobal('length') as Value).raw,
          equals(12),
          reason: 'Result length should be 12',
        );

        // Verify the exact byte sequence
        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
          (lua.getGlobal('b6') as Value).raw,
          (lua.getGlobal('b7') as Value).raw,
          (lua.getGlobal('b8') as Value).raw,
          (lua.getGlobal('b9') as Value).raw,
          (lua.getGlobal('b10') as Value).raw,
          (lua.getGlobal('b11') as Value).raw,
          (lua.getGlobal('b12') as Value).raw,
        ];
        final expected = [
          116,
          253,
          115,
          0,
          116,
          253,
          116,
          253,
          115,
          0,
          116,
          253,
        ];
        expect(
          bytes,
          equals(expected),
          reason: 'Bytes should match expected sequence',
        );
      });

      test('string.rep with high bytes and separator', () async {
        await lua.execute(r'''
          local input = 'a\xFDb'
          local result = string.rep(input, 3, ',')
          b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11 = string.byte(result, 1, -1)
        ''');

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
          (lua.getGlobal('b6') as Value).raw,
          (lua.getGlobal('b7') as Value).raw,
          (lua.getGlobal('b8') as Value).raw,
          (lua.getGlobal('b9') as Value).raw,
          (lua.getGlobal('b10') as Value).raw,
          (lua.getGlobal('b11') as Value).raw,
        ];
        // Expected: a(97)(253) b(98) ,(44) a(97)(253) b(98) ,(44) a(97)(253) b(98)
        final expected = [97, 253, 98, 44, 97, 253, 98, 44, 97, 253, 98];
        expect(bytes, equals(expected));
      });

      test('string.rep with count 1 preserves original', () async {
        await lua.execute(r'''
          local input = 't\xFDs\00t\xFD'
          local result = string.rep(input, 1)
          equal = input == result
          b1, b2, b3, b4, b5, b6 = string.byte(result, 1, -1)
        ''');

        expect(
          (lua.getGlobal('equal') as Value).raw,
          isTrue,
          reason: 'string.rep(str, 1) should equal original',
        );

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
          (lua.getGlobal('b6') as Value).raw,
        ];
        final expected = [116, 253, 115, 0, 116, 253];
        expect(bytes, equals(expected));
      });

      test('string.rep with count 0 returns empty string', () async {
        await lua.execute(r'''
          local input = 't\xFDs\00t\xFD'
          local result = string.rep(input, 0)
          is_empty = result == ''
          length = #result
        ''');

        expect((lua.getGlobal('is_empty') as Value).raw, isTrue);
        expect((lua.getGlobal('length') as Value).raw, equals(0));
      });
    });

    group('UTF-8 Double-Encoding Prevention', () {
      test('string literal parsing preserves raw bytes', () async {
        await lua.execute(r'''
          -- Test that string literals with high bytes are parsed correctly
          local str = "\xFD"  -- byte 253
          byte_value = string.byte(str)
        ''');

        expect(
          (lua.getGlobal('byte_value') as Value).raw,
          equals(253),
          reason: 'High byte should be preserved as-is',
        );
      });

      test('string.format %q preserves high bytes', () async {
        await lua.execute(r'''
          local x = '"\xFDlo"\n\\'
          local formatted = string.format('%q', x)
          -- Load the formatted string back and verify it matches
          local loaded = load('return ' .. formatted)()
          equal = x == loaded
          orig_byte = string.byte(x, 2)
          loaded_byte = string.byte(loaded, 2)
        ''');

        expect(
          (lua.getGlobal('equal') as Value).raw,
          isTrue,
          reason: 'Round-trip through string.format %q should preserve bytes',
        );
        expect(
          (lua.getGlobal('orig_byte') as Value).raw,
          equals((lua.getGlobal('loaded_byte') as Value).raw),
          reason: 'High bytes should be identical after round-trip',
        );
      });

      test('string operations preserve byte representation', () async {
        await lua.execute(r'''
          local str = '\xFD\xFE\xFF'  -- High bytes 253, 254, 255
          local upper = string.upper(str)
          local lower = string.lower(str)
          o1, o2, o3 = string.byte(str, 1, 3)
          u1, u2, u3 = string.byte(upper, 1, 3)
          l1, l2, l3 = string.byte(lower, 1, 3)
        ''');

        final original = [
          (lua.getGlobal('o1') as Value).raw,
          (lua.getGlobal('o2') as Value).raw,
          (lua.getGlobal('o3') as Value).raw,
        ];
        final upper = [
          (lua.getGlobal('u1') as Value).raw,
          (lua.getGlobal('u2') as Value).raw,
          (lua.getGlobal('u3') as Value).raw,
        ];
        final lower = [
          (lua.getGlobal('l1') as Value).raw,
          (lua.getGlobal('l2') as Value).raw,
          (lua.getGlobal('l3') as Value).raw,
        ];

        expect(original, equals([253, 254, 255]));
        expect(
          upper,
          equals([253, 254, 255]),
          reason: 'High bytes should not be affected by upper()',
        );
        expect(
          lower,
          equals([253, 254, 255]),
          reason: 'High bytes should not be affected by lower()',
        );
      });
    });

    group('String Interning with High Bytes', () {
      test('string interning works with ASCII content', () async {
        await lua.execute(r'''
          local str1 = string.rep("a", 10)
          local str2 = string.rep("aa", 5)
          -- In Lua, these should be the same string object (interned)
          equal = str1 == str2
          len1 = #str1
          len2 = #str2
        ''');

        expect(
          (lua.getGlobal('equal') as Value).raw,
          isTrue,
          reason: 'ASCII strings should intern correctly',
        );
        expect((lua.getGlobal('len1') as Value).raw, equals(10));
        expect((lua.getGlobal('len2') as Value).raw, equals(10));
      });

      test('string interning preserves high-byte content', () async {
        await lua.execute(r'''
          local str1 = string.rep("\xFD", 5)  -- byte 253 repeated
          local str2 = string.rep("\xFD\xFD", 2) .. "\xFD"  -- same content different construction
          equal = str1 == str2
          b1_1, b1_2, b1_3, b1_4, b1_5 = string.byte(str1, 1, 5)
          b2_1, b2_2, b2_3, b2_4, b2_5 = string.byte(str2, 1, 5)
        ''');

        expect(
          (lua.getGlobal('equal') as Value).raw,
          isTrue,
          reason: 'High-byte strings should compare correctly',
        );

        final bytes1 = [
          (lua.getGlobal('b1_1') as Value).raw,
          (lua.getGlobal('b1_2') as Value).raw,
          (lua.getGlobal('b1_3') as Value).raw,
          (lua.getGlobal('b1_4') as Value).raw,
          (lua.getGlobal('b1_5') as Value).raw,
        ];
        final bytes2 = [
          (lua.getGlobal('b2_1') as Value).raw,
          (lua.getGlobal('b2_2') as Value).raw,
          (lua.getGlobal('b2_3') as Value).raw,
          (lua.getGlobal('b2_4') as Value).raw,
          (lua.getGlobal('b2_5') as Value).raw,
        ];
        expect(
          bytes1,
          equals(bytes2),
          reason: 'Byte sequences should be identical',
        );
        expect(bytes1, equals([253, 253, 253, 253, 253]));
      });
    });

    group('Metamethod Fallback Behavior', () {
      test('__name metamethod fallback without hash', () async {
        await lua.execute(r'''
          local mt = {__name = "CustomType"}
          local obj = setmetatable({}, mt)
          local formatted = string.format("%s", obj)
          -- Should be "CustomType: " without hash code
          matches = formatted:match("^CustomType: $") ~= nil
        ''');

        expect(
          (lua.getGlobal('matches') as Value).raw,
          isTrue,
          reason: '__name fallback should not include hash code',
        );
        expect(
          (lua.getGlobal('formatted') as Value).raw.toString(),
          equals('CustomType: '),
          reason: 'Format should be exactly "CustomType: "',
        );
      });

      test('__tostring takes precedence over __name', () async {
        await lua.execute(r'''
          local mt = {
            __name = "CustomType",
            __tostring = function() return "custom string" end
          }
          local obj = setmetatable({}, mt)
          formatted = string.format("%s", obj)
        ''');

        expect(
          (lua.getGlobal('formatted') as Value).raw.toString(),
          equals('custom string'),
          reason: '__tostring should take precedence',
        );
      });

      test('nil __tostring falls back to __name', () async {
        await lua.execute(r'''
          local mt = {
            __name = "TestType",
            __tostring = nil
          }
          local obj = setmetatable({}, mt)
          formatted = string.format("%s", obj)
        ''');

        expect(
          (lua.getGlobal('formatted') as Value).raw.toString(),
          equals('TestType: '),
          reason: 'nil __tostring should fall back to __name',
        );
      });
    });

    group('String Literal Edge Cases', () {
      test('null bytes in string literals', () async {
        await lua.execute(r'''
          local str = "a\0b\0c"
          length = #str
          b1, b2, b3, b4, b5 = string.byte(str, 1, 5)
        ''');

        expect(
          (lua.getGlobal('length') as Value).raw,
          equals(5),
          reason: 'String with null bytes should have correct length',
        );

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
        ];
        expect(
          bytes,
          equals([97, 0, 98, 0, 99]),
          reason: 'Null bytes should be preserved',
        );
      });

      test('mixed ASCII and high bytes', () async {
        await lua.execute(r'''
          local str = "Hello\xFD\xFE\xFFWorld"
          length = #str
          b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13 = string.byte(str, 1, -1)
        ''');

        expect(
          (lua.getGlobal('length') as Value).raw,
          equals(13),
          reason: 'Mixed string should have correct length',
        );

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
          (lua.getGlobal('b6') as Value).raw,
          (lua.getGlobal('b7') as Value).raw,
          (lua.getGlobal('b8') as Value).raw,
          (lua.getGlobal('b9') as Value).raw,
          (lua.getGlobal('b10') as Value).raw,
          (lua.getGlobal('b11') as Value).raw,
          (lua.getGlobal('b12') as Value).raw,
          (lua.getGlobal('b13') as Value).raw,
        ]; // "Hello" + high bytes + "World"
        final expected = [
          72,
          101,
          108,
          108,
          111,
          253,
          254,
          255,
          87,
          111,
          114,
          108,
          100,
        ];
        expect(bytes, equals(expected));
      });

      test('escape sequences in string literals', () async {
        await lua.execute('''
          local str = "\\n\\t\\r\\\\"
          length = #str
          b1, b2, b3, b4 = string.byte(str, 1, 4)
        ''');

        expect(
          (lua.getGlobal('length') as Value).raw,
          equals(4),
          reason: 'Escaped string should have correct length',
        );

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
        ];
        expect(
          bytes,
          equals([10, 9, 13, 92]),
          reason: 'Escape sequences should be interpreted correctly',
        ); // \n, \t, \r, \\
      });
    });

    group('Large String Operations', () {
      test('string.rep with large count error handling', () async {
        await lua.execute(r'''
          local success, err = pcall(string.rep, 'aa', (1 << 30))
          has_error = not success
          has_too_large = err and err:find("too large") ~= nil
        ''');

        expect(
          (lua.getGlobal('has_error') as Value).raw,
          isTrue,
          reason: 'Large string.rep should fail',
        );
        expect(
          (lua.getGlobal('has_too_large') as Value).raw,
          isTrue,
          reason: 'Error should mention "too large"',
        );
      });

      test('string.rep with separator and large count', () async {
        await lua.execute(r'''
          local success, err = pcall(string.rep, 'a', (1 << 30), ',')
          has_error = not success
          has_too_large = err and err:find("too large") ~= nil
        ''');

        expect(
          (lua.getGlobal('has_error') as Value).raw,
          isTrue,
          reason: 'Large string.rep with separator should fail',
        );
        expect(
          (lua.getGlobal('has_too_large') as Value).raw,
          isTrue,
          reason: 'Error should mention "too large"',
        );
      });
    });
  });
}
