import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('String Literal Parsing Regression Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    group('High-Byte Character Preservation', () {
      test('single high-byte character (253)', () async {
        await lua.runCode(r'''
          local str = "\xFD"  -- This should be byte 253
          byte_value = string.byte(str)
        ''');

        expect(
          (lua.getGlobal('byte_value') as Value).raw,
          equals(253),
          reason: 'Byte 253 should be preserved as-is',
        );
      });

      test('multiple high-byte characters', () async {
        await lua.runCode(r'''
          local str = "\xFD\xFE\xFF"  -- bytes 253, 254, 255
          b1, b2, b3 = string.byte(str, 1, 3)
        ''');

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
        ];
        expect(
          bytes,
          equals([253, 254, 255]),
          reason: 'High bytes should be preserved in sequence',
        );
      });

      test('high bytes mixed with ASCII', () async {
        await lua.runCode(r'''
          local str = "a\xFDb\xFEc"  -- ASCII mixed with high bytes
          b1, b2, b3, b4, b5 = string.byte(str, 1, 5)
        ''');

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
        ];
        expect(
          bytes,
          equals([97, 253, 98, 254, 99]),
          reason: 'Mixed ASCII and high bytes should be preserved',
        );
      });
    });

    group('Escape Sequence Handling', () {
      test('hex escape sequences with high values', () async {
        await lua.runCode(r'''
          local str = "\xFD\xFE\xFF"
          b1, b2, b3 = string.byte(str, 1, 3)
        ''');

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
        ];
        expect(
          bytes,
          equals([253, 254, 255]),
          reason: 'Hex escapes should produce correct high bytes',
        );
      });

      test('decimal escape sequences with high values', () async {
        await lua.runCode(r'''
          local str = "\253\254\255"
          b1, b2, b3 = string.byte(str, 1, 3)
        ''');

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
        ];
        expect(
          bytes,
          equals([253, 254, 255]),
          reason: 'Decimal escapes should produce correct high bytes',
        );
      });

      test('mixed escape sequences and literals', () async {
        await lua.runCode(r'''
          local str = "a\xFDb\254c\xFD"  -- Mix of literal, hex, decimal, and high-byte char
          b1, b2, b3, b4, b5, b6 = string.byte(str, 1, 6)
        ''');

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
          (lua.getGlobal('b5') as Value).raw,
          (lua.getGlobal('b6') as Value).raw,
        ];
        expect(
          bytes,
          equals([97, 253, 98, 254, 99, 253]),
          reason: 'Mixed escape types should work correctly',
        );
      });
    });

    group('Null Byte Handling', () {
      test('null bytes in string literals', () async {
        await lua.runCode(r'''
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

      test('null bytes with high bytes', () async {
        await lua.runCode(r'''
          local str = "\xFD\0\xFE\0"  -- High bytes with null bytes
          length = #str
          b1, b2, b3, b4 = string.byte(str, 1, 4)
        ''');

        expect((lua.getGlobal('length') as Value).raw, equals(4));

        final bytes = [
          (lua.getGlobal('b1') as Value).raw,
          (lua.getGlobal('b2') as Value).raw,
          (lua.getGlobal('b3') as Value).raw,
          (lua.getGlobal('b4') as Value).raw,
        ];
        expect(
          bytes,
          equals([253, 0, 254, 0]),
          reason: 'Null bytes and high bytes should coexist',
        );
      });
    });

    group('String Format Round-Trip Tests', () {
      test('string.format %q round-trip with high bytes', () async {
        await lua.runCode(r'''
          local original = '"\xFDlo"\n\\'  -- The specific failing case with high byte
          local formatted = string.format('%q', original)
          local loaded = load('return ' .. formatted)()
          equal = original == loaded
          orig_len = #original
          loaded_len = #loaded
        ''');

        expect(
          (lua.getGlobal('equal') as Value).raw,
          isTrue,
          reason: 'Round-trip should preserve original string',
        );
        expect(
          (lua.getGlobal('orig_len') as Value).raw,
          equals((lua.getGlobal('loaded_len') as Value).raw),
          reason: 'Lengths should be identical',
        );
      });

      test('string.format %q with various special characters', () async {
        await lua.runCode(r'''
          local test_strings = {
            "simple",
            "with\nnewline",
            "with\ttab",
            "with\"quote",
            "with\\backslash",
            "with\xFDhighbyte",
            "\0null\0bytes\0",
            "\xFD\0\xFE\0mixed"
          }

          local results = {}
          for i, str in ipairs(test_strings) do
            local formatted = string.format('%q', str)
            local loaded = load('return ' .. formatted)()
            results[i] = (str == loaded)
          end

          r1, r2, r3, r4, r5, r6, r7, r8 = table.unpack(results)
        ''');

        final results = [
          (lua.getGlobal('r1') as Value).raw,
          (lua.getGlobal('r2') as Value).raw,
          (lua.getGlobal('r3') as Value).raw,
          (lua.getGlobal('r4') as Value).raw,
          (lua.getGlobal('r5') as Value).raw,
          (lua.getGlobal('r6') as Value).raw,
          (lua.getGlobal('r7') as Value).raw,
          (lua.getGlobal('r8') as Value).raw,
        ];
        for (int i = 0; i < results.length; i++) {
          expect(
            results[i],
            isTrue,
            reason: 'Test string $i should round-trip correctly',
          );
        }
      });
    });

    group('LuaString vs String Consistency', () {
      test('string operations return consistent types', () async {
        await lua.runCode(r'''
          local str = "test\xFDstring"  -- Contains high byte
          local upper = string.upper(str)
          local lower = string.lower(str)
          local rep = string.rep(str, 2)

          -- All should be LuaString objects that behave consistently
          type_str = type(str) == "string"
          type_upper = type(upper) == "string"
          type_lower = type(lower) == "string"
          type_rep = type(rep) == "string"
          byte_str = string.byte(str, 5) == 253
          byte_upper = string.byte(upper, 5) == 253
          byte_lower = string.byte(lower, 5) == 253
          byte_rep = string.byte(rep, 5) == 253
        ''');

        final checks = [
          (lua.getGlobal('type_str') as Value).raw,
          (lua.getGlobal('type_upper') as Value).raw,
          (lua.getGlobal('type_lower') as Value).raw,
          (lua.getGlobal('type_rep') as Value).raw,
          (lua.getGlobal('byte_str') as Value).raw,
          (lua.getGlobal('byte_upper') as Value).raw,
          (lua.getGlobal('byte_lower') as Value).raw,
          (lua.getGlobal('byte_rep') as Value).raw,
        ];
        for (int i = 0; i < checks.length; i++) {
          expect(checks[i], isTrue, reason: 'Consistency check $i should pass');
        }
      });

      test('string concatenation preserves bytes', () async {
        await lua.runCode(r'''
          local a = "hello"
          local b = "\xFDworld"  -- Contains high byte
          local c = a .. b

          length = #c
          byte6 = string.byte(c, 6)
          byte7 = string.byte(c, 7)
          byte8 = string.byte(c, 8)
        ''');

        expect(
          (lua.getGlobal('length') as Value).raw,
          equals(11),
          reason: 'Concatenated string should have correct length',
        );
        expect(
          (lua.getGlobal('byte6') as Value).raw,
          equals(253),
          reason: 'High byte should be preserved in concatenation',
        );
        expect(
          (lua.getGlobal('byte7') as Value).raw,
          equals(119),
          reason: 'Following ASCII should be correct (w)',
        );
        expect(
          (lua.getGlobal('byte8') as Value).raw,
          equals(111),
          reason: 'Following ASCII should be correct (o)',
        );
      });
    });

    group('Edge Cases and Error Conditions', () {
      test('very long strings with high bytes', () async {
        await lua.runCode(r'''
          local base = string.rep("\xFD", 100)  -- 100 high bytes
          local doubled = string.rep(base, 2)
          length = #doubled
          byte1 = string.byte(doubled, 1)
          byte100 = string.byte(doubled, 100)
          byte101 = string.byte(doubled, 101)
          byte200 = string.byte(doubled, 200)
        ''');

        expect(
          (lua.getGlobal('length') as Value).raw,
          equals(200),
          reason: 'Long string should have correct length',
        );
        expect(
          (lua.getGlobal('byte1') as Value).raw,
          equals(253),
          reason: 'First byte should be correct',
        );
        expect(
          (lua.getGlobal('byte100') as Value).raw,
          equals(253),
          reason: '100th byte should be correct',
        );
        expect(
          (lua.getGlobal('byte101') as Value).raw,
          equals(253),
          reason: '101st byte (start of second rep) should be correct',
        );
        expect(
          (lua.getGlobal('byte200') as Value).raw,
          equals(253),
          reason: 'Last byte should be correct',
        );
      });

      test('empty string operations', () async {
        await lua.runCode(r'''
          local empty = ""
          local rep_empty = string.rep(empty, 10)
          local concat_empty = empty .. "\xFDtest"

          len_empty = #empty
          len_rep = #rep_empty
          len_concat = #concat_empty
          first_byte = string.byte(concat_empty, 1)
        ''');

        expect((lua.getGlobal('len_empty') as Value).raw, equals(0));
        expect((lua.getGlobal('len_rep') as Value).raw, equals(0));
        expect((lua.getGlobal('len_concat') as Value).raw, equals(5));
        expect((lua.getGlobal('first_byte') as Value).raw, equals(253));
      });
    });
  });
}
