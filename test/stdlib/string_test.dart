@Tags(['stdlib'])
library;

import 'package:lualike/testing.dart';

void main() {
  group('String Library', () {
    // Basic string operations
    test('string.len', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.len("hello")
        local b = string.len("")
        local c = string.len("hello\\0world") -- embedded zeros are counted
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals(5));
      expect((bridge.getGlobal('b') as Value).raw, equals(0));
      expect((bridge.getGlobal('c') as Value).raw, equals(11));
    });

    test('string.byte', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.byte("ABCDE", 1)
        local b,c,d = string.byte("ABCDE", 2, 4)
        local e = string.byte("ABCDE", -1) -- negative index
      ''');

      expect(
        (bridge.getGlobal('a') as Value).unwrap(),
        equals(65),
      ); // ASCII for 'A'

      expect((bridge.getGlobal('b') as Value).raw, equals(66)); // 'B'
      expect((bridge.getGlobal('c') as Value).raw, equals(67)); // 'E'
      expect((bridge.getGlobal('d') as Value).raw, equals(68)); // 'E'
      expect((bridge.getGlobal('e') as Value).raw, equals(69)); // 'E'
    });

    test('string.char', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.char(65, 66, 67, 68, 69)
        local b = string.char()
      ''');

      expect((bridge.getGlobal('a') as Value).raw.toString(), equals("ABCDE"));
      expect((bridge.getGlobal('b') as Value).raw.toString(), equals(""));
    });

    test('string.sub', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "abcdefghijklm"
        local a = string.sub(s, 3, 5)    -- "cde"
        local b = string.sub(s, 3)       -- "cdefghijklm"
        local c = string.sub(s, -5)      -- "ijklm"
        local d = string.sub(s, -5, -3)  -- "ijk"
        local e = string.sub(s, 10, 5)   -- "" (start > end)
        local f = string.sub(s, 100, 200) -- "" (start > string length)
      ''');

      expect((bridge.getGlobal('a') as Value).raw.toString(), equals("cde"));
      expect(
        (bridge.getGlobal('b') as Value).raw.toString(),
        equals("cdefghijklm"),
      );
      expect((bridge.getGlobal('c') as Value).raw.toString(), equals("ijklm"));
      expect((bridge.getGlobal('d') as Value).raw.toString(), equals("ijk"));
      expect((bridge.getGlobal('e') as Value).raw.toString(), equals(""));
      expect((bridge.getGlobal('f') as Value).raw.toString(), equals(""));
    });

    test('string.upper and string.lower', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.upper("Hello, World!")
        local b = string.lower("Hello, World!")
      ''');

      expect(
        (bridge.getGlobal('a') as Value).raw.toString(),
        equals("HELLO, WORLD!"),
      );
      expect(
        (bridge.getGlobal('b') as Value).raw.toString(),
        equals("hello, world!"),
      );
    });

    test('string.reverse', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.reverse("hello")
        local b = string.reverse("")
      ''');

      expect((bridge.getGlobal('a') as Value).raw.toString(), equals("olleh"));
      expect((bridge.getGlobal('b') as Value).raw.toString(), equals(""));
    });

    test('string.rep', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.rep("abc", 3)
        local b = string.rep("abc", 3, "-")
        local c = string.rep("abc", 0)
      ''');

      expect(
        (bridge.getGlobal('a') as Value).raw.toString(),
        equals("abcabcabc"),
      );
      expect(
        (bridge.getGlobal('b') as Value).raw.toString(),
        equals("abc-abc-abc"),
      );
      expect((bridge.getGlobal('c') as Value).raw.toString(), equals(""));
    });

    // Pattern matching
    test('string.find basic', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "hello world"
        local i, j = string.find(s, "world")
        local k, l = string.find(s, "bye")
        local m, n = string.find(s, "o", 5) -- start from position 5
        local plain_i, plain_j = string.find(s, "o.", 1, true) -- plain search
      ''');

      expect((bridge.getGlobal('i') as Value).raw, equals(7));
      expect((bridge.getGlobal('j') as Value).raw, equals(11));
      expect((bridge.getGlobal('k') as Value).raw, isNull);
      expect((bridge.getGlobal('l') as Value).raw, isNull);
      expect((bridge.getGlobal('m') as Value).raw, equals(5));
      expect((bridge.getGlobal('n') as Value).raw, equals(5));
      expect(
        (bridge.getGlobal('plain_i') as Value).raw,
        isNull,
      ); // "o." not found as plain text
    });

    test('string.find with captures', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "hello world from lua"
        local i, j, first = string.find(s, "(%w+)%s+(%w+)")
        local _, _, second = string.find(s, "%w+%s+(%w+)")
      ''');

      expect((bridge.getGlobal('i') as Value).raw, equals(1));
      expect((bridge.getGlobal('j') as Value).raw, equals(11));
      expect((bridge.getGlobal('first') as Value).raw, equals("hello"));
      expect((bridge.getGlobal('second') as Value).raw, equals("world"));
    });

    test('string.match', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "hello world from lua"
        local word = string.match(s, "%w+")
        local w1, w2 = string.match(s, "(%w+)%s+(%w+)")
        local no_match = string.match(s, "bye")
      ''');

      expect((bridge.getGlobal('word') as Value).raw, equals("hello"));
      expect((bridge.getGlobal('w1') as Value).raw, equals("hello"));
      expect((bridge.getGlobal('w2') as Value).raw, equals("world"));
      expect((bridge.getGlobal('no_match') as Value).raw, isNull);
    });

    test('string.gsub', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "hello world from lua"
        local r1, n1 = string.gsub(s, "l", "L")
        local r2, n2 = string.gsub(s, "l", "L", 2) -- replace only 2 occurrences
        local r3, n3 = string.gsub(s, "(%w+)", "%1!")
      ''');

      final r1 = (bridge.getGlobal('r1') as Value).raw;
      final r1String = r1 is LuaString ? r1.toString() : r1.toString();
      expect(r1String, equals("heLLo worLd from Lua"));
      expect((bridge.getGlobal('n1') as Value).raw, equals(4));
      final r2 = (bridge.getGlobal('r2') as Value).raw;
      final r2String = r2 is LuaString ? r2.toString() : r2.toString();
      expect(r2String, equals("heLLo world from lua"));
      expect((bridge.getGlobal('n2') as Value).raw, equals(2));
      final r3 = (bridge.getGlobal('r3') as Value).raw;
      final r3String = r3 is LuaString ? r3.toString() : r3.toString();
      expect(r3String, equals("hello! world! from! lua!"));
      expect((bridge.getGlobal('n3') as Value).raw, equals(4));
    });

    test('string.gsub zero-length pattern', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s, n = string.gsub("abc", "", "-")
      ''');
      expect((bridge.getGlobal('s') as Value).unwrap(), equals("-a-b-c-"));
      expect((bridge.getGlobal('n') as Value).unwrap(), equals(4));
    });

    test('string.gmatch', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "hello world from lua"
        local words = {}
        local i = 1
        for w in string.gmatch(s, "%w+") do
          words[i] = w
          i = i + 1
        end
      ''');

      // Check words array
      final words = (bridge.getGlobal('words') as Value).raw as Map;
      expect((words[1] as Value).raw, equals("hello"));
      expect((words[2] as Value).raw, equals("world"));
      expect((words[3] as Value).raw, equals("from"));
      expect((words[4] as Value).raw, equals("lua"));

      await bridge.runCode('''
        local pairs = {}
        i = 1
        local s2 = "key1=value1 key2=value2"
        for k, v in string.gmatch(s2, "(%w+)=(%w+)") do
          pairs[i] = {k=k, v=v}
          i = i + 1
        end

      ''');

      // Check key-value pairs
      final pairs = (bridge.getGlobal('pairs') as Value).raw as Map;
      final pair1 = pairs[1];
      final pair2 = pairs[2];
      expect((pair1['k'] as Value).raw, equals("key1"));
      expect((pair1['v'] as Value).raw, equals("value1"));
      expect((pair2['k'] as Value).raw, equals("key2"));
      expect((pair2['v'] as Value).raw, equals("value2"));
    });

    test('string.gmatch zero-length pattern', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local t = {}
        for w in string.gmatch("abc", "") do
          table.insert(t, w or "")
        end
      ''');
      final t = (bridge.getGlobal('t') as Value).raw as Map;
      expect(t.length, equals(4));
    });

    // Binary Pack/Unpack Operations
    group('string.pack/unpack', () {
      test('basic integer types roundtrip', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("bhi", 100, 30000, -50000)
          local b, h, i, pos = string.unpack("bhi", s)
        ''');

        var b = bridge.getGlobal('b');
        var h = bridge.getGlobal('h');
        var i = bridge.getGlobal('i');
        var pos = bridge.getGlobal('pos');

        expect((b as Value).raw, equals(100));
        expect((h as Value).raw, equals(30000));
        expect((i as Value).raw, equals(-50000));
        expect((pos as Value).raw, equals(8)); // 1 + 2 + 4 + 1
      });

      test('long types (l, L)', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("lL", -1000, 1000)
          local a, b, pos = string.unpack("lL", s)
        ''');

        var a = bridge.getGlobal('a');
        var b = bridge.getGlobal('b');
        var pos = bridge.getGlobal('pos');

        expect((a as Value).raw, equals(-1000));
        expect((b as Value).raw, equals(1000));
        expect((pos as Value).raw, equals(17)); // 8 + 8 + 1
      });

      test('lua_Integer types (j, J)', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("jJ", -2000, 2000)
          local a, b, pos = string.unpack("jJ", s)
        ''');

        var a = bridge.getGlobal('a');
        var b = bridge.getGlobal('b');
        var pos = bridge.getGlobal('pos');

        expect((a as Value).raw, equals(-2000));
        expect((b as Value).raw, equals(2000));
        expect((pos as Value).raw, equals(17)); // 8 + 8 + 1
      });

      test('size_t type (T)', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("T", 42)
          local a, pos = string.unpack("T", s)
        ''');

        var a = bridge.getGlobal('a');
        var pos = bridge.getGlobal('pos');

        expect((a as Value).raw, equals(42));
        expect((pos as Value).raw, equals(9)); // 8 + 1
      });

      test('float types (f, d, n)', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("fdn", 3.14, 2.71, 1.41)
          local a, b, c, pos = string.unpack("fdn", s)
        ''');

        var a = bridge.getGlobal('a');
        var b = bridge.getGlobal('b');
        var c = bridge.getGlobal('c');
        var pos = bridge.getGlobal('pos');

        expect((a as Value).raw, closeTo(3.14, 1e-6));
        expect((b as Value).raw, closeTo(2.71, 1e-15));
        expect((c as Value).raw, closeTo(1.41, 1e-15));
        expect((pos as Value).raw, equals(21)); // 4 + 8 + 8 + 1
      });

      test('unsigned handling', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("L", -1)
          local a, pos = string.unpack("L", s)
        ''');

        var a = bridge.getGlobal('a');
        var pos = bridge.getGlobal('pos');

        // Lua returns signed values even for unsigned formats
        expect((a as Value).raw, equals(-1));
        expect((pos as Value).raw, equals(9)); // 8 + 1
      });

      test('explicit integer sizes', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s1 = string.pack("i1i2i4i8", 127, 32767, 2147483647, 9223372036854775807)
          local a, b, c, d, pos = string.unpack("i1i2i4i8", s1)

          local s2 = string.pack("I1I2I4I8", 255, 65535, 4294967295, 18446744073709551615)
          local e, f, g, h, pos2 = string.unpack("I1I2I4I8", s2)

          local s3 = string.pack("j1j2j4j8", 127, 32767, 2147483647, 9223372036854775807)
          local i, j, k, l, pos3 = string.unpack("j1j2j4j8", s3)
        ''');

        // Test explicit signed integer sizes
        expect((bridge.getGlobal('a') as Value).raw, equals(127));
        expect((bridge.getGlobal('b') as Value).raw, equals(32767));
        expect((bridge.getGlobal('c') as Value).raw, equals(2147483647));
        expect(
          (bridge.getGlobal('d') as Value).raw,
          equals(9223372036854775807),
        );
        expect((bridge.getGlobal('pos') as Value).raw, equals(16)); // 1+2+4+8+1

        // Test explicit unsigned integer sizes (still return signed in Lua)
        expect((bridge.getGlobal('e') as Value).raw, equals(255));
        expect((bridge.getGlobal('f') as Value).raw, equals(65535));
        expect((bridge.getGlobal('g') as Value).raw, equals(4294967295));
        expect(
          (bridge.getGlobal('h') as Value).raw,
          equals(9223372036854775807),
        ); // Max 8-byte signed value
        expect(
          (bridge.getGlobal('pos2') as Value).raw,
          equals(16),
        ); // 1+2+4+8+1

        // Test explicit lua_Integer sizes
        expect((bridge.getGlobal('i') as Value).raw, equals(127));
        expect((bridge.getGlobal('j') as Value).raw, equals(32767));
        expect((bridge.getGlobal('k') as Value).raw, equals(2147483647));
        expect(
          (bridge.getGlobal('l') as Value).raw,
          equals(9223372036854775807),
        );
        expect(
          (bridge.getGlobal('pos3') as Value).raw,
          equals(33),
        ); // Currently uses default j size (8) for all, so 8+8+8+8+1 = 33
      });

      test('endianness support', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s_little = string.pack("<I4", 0x12345678)
          local s_big = string.pack(">I4", 0x12345678)
          local s_host = string.pack("=I4", 0x12345678)

          local a, pos_a = string.unpack("<I4", s_little)
          local b, pos_b = string.unpack(">I4", s_big)
          local c, pos_c = string.unpack("=I4", s_host)
        ''');

        expect((bridge.getGlobal('a') as Value).raw, equals(0x12345678));
        expect((bridge.getGlobal('b') as Value).raw, equals(0x12345678));
        expect((bridge.getGlobal('c') as Value).raw, equals(0x12345678));
        expect((bridge.getGlobal('pos_a') as Value).raw, equals(5));
        expect((bridge.getGlobal('pos_b') as Value).raw, equals(5));
        expect((bridge.getGlobal('pos_c') as Value).raw, equals(5));
      });

      test('alignment support', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s1 = string.pack("!1bI4", 1, 0x12345678)
          local s2 = string.pack("!2bI4", 1, 0x12345678)
          local s4 = string.pack("!4bI4", 1, 0x12345678)
          local s8 = string.pack("!8bI4", 1, 0x12345678)

          local a1, b1, pos1 = string.unpack("!1bI4", s1)
          local a2, b2, pos2 = string.unpack("!2bI4", s2)
          local a4, b4, pos4 = string.unpack("!4bI4", s4)
          local a8, b8, pos8 = string.unpack("!8bI4", s8)
        ''');

        // All should unpack correctly
        expect((bridge.getGlobal('a1') as Value).raw, equals(1));
        expect((bridge.getGlobal('b1') as Value).raw, equals(0x12345678));
        expect((bridge.getGlobal('a2') as Value).raw, equals(1));
        expect((bridge.getGlobal('b2') as Value).raw, equals(0x12345678));
        expect((bridge.getGlobal('a4') as Value).raw, equals(1));
        expect((bridge.getGlobal('b4') as Value).raw, equals(0x12345678));
        expect((bridge.getGlobal('a8') as Value).raw, equals(1));
        expect((bridge.getGlobal('b8') as Value).raw, equals(0x12345678));

        // Different alignments produce different sizes
        expect(
          (bridge.getGlobal('pos1') as Value).raw,
          equals(6),
        ); // 1 + 4 + 1 (no padding)
        expect(
          (bridge.getGlobal('pos2') as Value).raw,
          equals(7),
        ); // 1 + 1 pad + 4 + 1
        expect(
          (bridge.getGlobal('pos4') as Value).raw,
          equals(9),
        ); // 1 + 3 pad + 4 + 1
        expect(
          (bridge.getGlobal('pos8') as Value).raw,
          equals(9),
        ); // 1 + 3 pad + 4 + 1 (I4 max align is 4)
      });

      test('padding bytes (x, X)', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s1 = string.pack("bxI4", 1, 0x12345678)
          local s2 = string.pack("bxxI4", 1, 0x12345678)
          local s3 = string.pack("bxxxI4", 1, 0x12345678)

          local a1, b1, pos1 = string.unpack("bxI4", s1)
          local a2, b2, pos2 = string.unpack("bxxI4", s2)
          local a3, b3, pos3 = string.unpack("bxxxI4", s3)
        ''');

        expect((bridge.getGlobal('a1') as Value).raw, equals(1));
        expect((bridge.getGlobal('b1') as Value).raw, equals(0x12345678));
        expect(
          (bridge.getGlobal('pos1') as Value).raw,
          equals(7),
        ); // 1 + 1 pad + 4 + 1

        expect((bridge.getGlobal('a2') as Value).raw, equals(1));
        expect((bridge.getGlobal('b2') as Value).raw, equals(0x12345678));
        expect(
          (bridge.getGlobal('pos2') as Value).raw,
          equals(8),
        ); // 1 + 2 pad + 4 + 1

        expect((bridge.getGlobal('a3') as Value).raw, equals(1));
        expect((bridge.getGlobal('b3') as Value).raw, equals(0x12345678));
        expect(
          (bridge.getGlobal('pos3') as Value).raw,
          equals(9),
        ); // 1 + 3 pad + 4 + 1
      });

      group('string formats', () {
        test('fixed-length strings (c)', () async {
          final bridge = LuaLike();

          await bridge.runCode('''
            local s1 = string.pack("c5", "hello")
            local s2 = string.pack("c10", "hello")
            local s3 = string.pack("c3", "hello")

            local a1, pos1 = string.unpack("c5", s1)
            local a2, pos2 = string.unpack("c10", s2)
            local a3, pos3 = string.unpack("c3", s3)
          ''');

          expect((bridge.getGlobal('a1') as Value).raw, equals("hello"));
          expect((bridge.getGlobal('pos1') as Value).raw, equals(6)); // 5 + 1

          expect(
            (bridge.getGlobal('a2') as Value).raw,
            equals("hello\u0000\u0000\u0000\u0000\u0000"),
          );
          expect((bridge.getGlobal('pos2') as Value).raw, equals(11)); // 10 + 1

          expect((bridge.getGlobal('a3') as Value).raw, equals("hel"));
          expect((bridge.getGlobal('pos3') as Value).raw, equals(4)); // 3 + 1
        });

        test('zero-terminated strings (z)', () async {
          final bridge = LuaLike();

          await bridge.runCode('''
            local s1 = string.pack("z", "hello")
            local s2 = string.pack("z", "")
            local s3 = string.pack("zz", "hello", "world")

            local a1, pos1 = string.unpack("z", s1)
            local a2, pos2 = string.unpack("z", s2)
            local a3, b3, pos3 = string.unpack("zz", s3)
          ''');

          expect((bridge.getGlobal('a1') as Value).raw, equals("hello"));
          expect(
            (bridge.getGlobal('pos1') as Value).raw,
            equals(7),
          ); // 5 + 1 null + 1

          expect((bridge.getGlobal('a2') as Value).raw, equals(""));
          expect(
            (bridge.getGlobal('pos2') as Value).raw,
            equals(2),
          ); // 0 + 1 null + 1

          expect((bridge.getGlobal('a3') as Value).raw, equals("hello"));
          expect((bridge.getGlobal('b3') as Value).raw, equals("world"));
          expect(
            (bridge.getGlobal('pos3') as Value).raw,
            equals(13),
          ); // 5 + 1 + 5 + 1 + 1
        });

        test('size-prefixed strings (s)', () async {
          final bridge = LuaLike();

          await bridge.runCode('''
            local s1 = string.pack("s", "hello")
            local s2 = string.pack("s1", "hello")
            local s3 = string.pack("s2", "hello")
            local s4 = string.pack("s4", "hello")
            local s8 = string.pack("s8", "hello")

            local a1, pos1 = string.unpack("s", s1)
            local a2, pos2 = string.unpack("s1", s2)
            local a3, pos3 = string.unpack("s2", s3)
            local a4, pos4 = string.unpack("s4", s4)
            local a8, pos8 = string.unpack("s8", s8)
          ''');

          // All should unpack to the same string
          expect((bridge.getGlobal('a1') as Value).raw, equals("hello"));
          expect((bridge.getGlobal('a2') as Value).raw, equals("hello"));
          expect((bridge.getGlobal('a3') as Value).raw, equals("hello"));
          expect((bridge.getGlobal('a4') as Value).raw, equals("hello"));
          expect((bridge.getGlobal('a8') as Value).raw, equals("hello"));

          // But different sizes due to different length prefixes
          expect(
            (bridge.getGlobal('pos1') as Value).raw,
            equals(14),
          ); // 8 + 5 + 1
          expect(
            (bridge.getGlobal('pos2') as Value).raw,
            equals(7),
          ); // 1 + 5 + 1
          expect(
            (bridge.getGlobal('pos3') as Value).raw,
            equals(8),
          ); // 2 + 5 + 1
          expect(
            (bridge.getGlobal('pos4') as Value).raw,
            equals(10),
          ); // 4 + 5 + 1
          expect(
            (bridge.getGlobal('pos8') as Value).raw,
            equals(14),
          ); // 8 + 5 + 1
        });

        test('empty and special strings', () async {
          final bridge = LuaLike();

          await bridge.runCode('''
             local s1 = string.pack("s", "")
             local s2 = string.pack("z", "")
             local s3 = string.pack("c1", "")
             local s4 = string.pack("s", "hello\\0world")

             local a1, pos1 = string.unpack("s", s1)
             local a2, pos2 = string.unpack("z", s2)
             local a3, pos3 = string.unpack("c1", s3)
             local a4, pos4 = string.unpack("s", s4)
           ''');

          expect((bridge.getGlobal('a1') as Value).raw, equals(""));
          expect(
            (bridge.getGlobal('pos1') as Value).raw,
            equals(9),
          ); // 8 + 0 + 1

          expect((bridge.getGlobal('a2') as Value).raw, equals(""));
          expect(
            (bridge.getGlobal('pos2') as Value).raw,
            equals(2),
          ); // 0 + 1 null + 1

          expect((bridge.getGlobal('a3') as Value).raw, equals("\u0000"));
          expect((bridge.getGlobal('pos3') as Value).raw, equals(2)); // 1 + 1

          expect(
            (bridge.getGlobal('a4') as Value).raw,
            equals("hello\u0000world"),
          );
          expect(
            (bridge.getGlobal('pos4') as Value).raw,
            equals(20),
          ); // 8 + 11 + 1
        });

        test('unicode and binary strings', () async {
          final bridge = LuaLike();

          await bridge.runCode('''
            local s1 = string.pack("s", "héllo")
            local s2 = string.pack("z", "世界")
            local s3 = string.pack("c6", "héllo")

            local a1, pos1 = string.unpack("s", s1)
            local a2, pos2 = string.unpack("z", s2)
            local a3, pos3 = string.unpack("c6", s3)
          ''');

          expect((bridge.getGlobal('a1') as Value).raw, equals("héllo"));
          expect((bridge.getGlobal('a2') as Value).raw, equals("世界"));
          expect((bridge.getGlobal('a3') as Value).raw, equals("héllo"));
        });
      });

      test('packsize calculations', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local size_basic = string.packsize("bBhH")
          local size_long = string.packsize("lLjJT")
          local size_float = string.packsize("fdn")
          local size_comprehensive = string.packsize("bBhHlLjJTfdn")
          local size_explicit = string.packsize("i1i2i4i8I1I2I4I8")
          local size_aligned = string.packsize("!4bI4")
          local size_padded = string.packsize("bxxxI4")
        ''');

        expect(
          (bridge.getGlobal('size_basic') as Value).raw,
          equals(6),
        ); // 1+1+2+2
        expect(
          (bridge.getGlobal('size_long') as Value).raw,
          equals(40),
        ); // 8+8+8+8+8
        expect(
          (bridge.getGlobal('size_float') as Value).raw,
          equals(20),
        ); // 4+8+8
        expect(
          (bridge.getGlobal('size_comprehensive') as Value).raw,
          equals(66),
        ); // 1+1+2+2+8+8+8+8+8+4+8+8
        expect(
          (bridge.getGlobal('size_explicit') as Value).raw,
          equals(30),
        ); // 1+2+4+8+1+2+4+8
        expect(
          (bridge.getGlobal('size_aligned') as Value).raw,
          equals(8),
        ); // 1+3 pad+4
        expect(
          (bridge.getGlobal('size_padded') as Value).raw,
          equals(8),
        ); // 1+3 pad+4 (no alignment for x)
      });

      test('comprehensive mixed format', () async {
        final bridge = LuaLike();

        await bridge.runCode('''
          local s = string.pack("bBhHlLjJTfdn", 127, 255, -1000, 1000, -2000, 2000, -3000, 3000, 42, 3.14, 2.71, 1.41)
          local a,b,c,d,e,f,g,h,i,j,k,l,pos = string.unpack("bBhHlLjJTfdn", s)
        ''');

        expect((bridge.getGlobal('a') as Value).raw, equals(127));
        expect((bridge.getGlobal('b') as Value).raw, equals(255));
        expect((bridge.getGlobal('c') as Value).raw, equals(-1000));
        expect((bridge.getGlobal('d') as Value).raw, equals(1000));
        expect((bridge.getGlobal('e') as Value).raw, equals(-2000));
        expect((bridge.getGlobal('f') as Value).raw, equals(2000));
        expect((bridge.getGlobal('g') as Value).raw, equals(-3000));
        expect((bridge.getGlobal('h') as Value).raw, equals(3000));
        expect((bridge.getGlobal('i') as Value).raw, equals(42));
        expect((bridge.getGlobal('j') as Value).raw, closeTo(3.14, 1e-6));
        expect((bridge.getGlobal('k') as Value).raw, closeTo(2.71, 1e-15));
        expect((bridge.getGlobal('l') as Value).raw, closeTo(1.41, 1e-15));
        expect(
          (bridge.getGlobal('pos') as Value).raw,
          equals(67),
        ); // 1+1+2+2+8+8+8+8+8+4+8+8+1
      });

      test('error conditions', () async {
        final bridge = LuaLike();

        // Test invalid format
        await expectLater(
          () async => await bridge.runCode('string.pack("q", 1)'),
          throwsA(isA<LuaError>()),
        );

        // Test missing size for c
        await expectLater(
          () async => await bridge.runCode('string.pack("c", "hello")'),
          throwsA(isA<LuaError>()),
        );

        // Test unpack out of bounds
        await expectLater(
          () async => await bridge.runCode('''
            local s = string.pack("i", 42)
            string.unpack("ii", s)
          '''),
          throwsA(isA<LuaError>()),
        );

        // Test packsize with variable length
        await expectLater(
          () async => await bridge.runCode('string.packsize("s")'),
          throwsA(isA<LuaError>()),
        );

        await expectLater(
          () async => await bridge.runCode('string.packsize("z")'),
          throwsA(isA<LuaError>()),
        );
      });
    });

    test('string.dump basic functionality', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        local f = function(x) return x * 2 end
        local s = string.dump(f)
      ''');

      var s = bridge.getGlobal('s');
      expect(s, isNotNull);
      expect((s as Value).raw, isA<String>());
    });

    // Object-oriented style tests
    test('string methods in OO style', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local s = "Hello World"
        local len = s:len()
        local upper = s:upper()
        local first_char_code = s:byte(1)
        local sub = s:sub(1, 5)
      ''');

      expect((bridge.getGlobal('len') as Value).raw, equals(11));
      expect((bridge.getGlobal('upper') as Value).raw, equals("HELLO WORLD"));
      expect(
        (bridge.getGlobal('first_char_code') as Value).raw,
        equals(72),
      ); // 'H'
      expect((bridge.getGlobal('sub') as Value).raw, equals("Hello"));
    });

    // Pattern matching character classes
    test('pattern matching character classes', () async {
      final bridge = LuaLike();
      final result = await bridge.runCode('''
        local tests = {}

        -- %a (letters)
        tests.a1 = string.match("abc123", "%a+")
        tests.a2 = string.match("123abc", "%a+")

        -- %d (digits)
        tests.d1 = string.match("abc123", "%d+")
        tests.d2 = string.match("123abc", "%d+")

        -- %s (whitespace)
        tests.s1 = string.match("hello world", "%s+")

        -- %w (alphanumeric)
        tests.w1 = string.match("hello123", "%w+")

        -- %p (punctuation)
        tests.p1 = string.match("hello, world!", "%p+")

        -- %l (lowercase)
        tests.l1 = string.match("abcDEF", "%l+")

        -- %u (uppercase)
        tests.u1 = string.match("abcDEF", "%u+")

        -- Character classes with negation
        tests.A1 = string.match("abc123", "%A+") -- not letters
        tests.D1 = string.match("abc123", "%D+") -- not digits
        return tests
      ''');

      final tests = (result as Value).raw as Map;
      expect(tests['a1'], equals(Value("abc")));
      expect(tests['a2'], equals(Value("abc")));
      expect(tests['d1'], equals(Value("123")));
      expect(tests['d2'], equals(Value("123")));
      expect(tests['s1'], equals(Value(" ")));
      expect(tests['w1'], equals(Value("hello123")));
      //TODO pattern matching doesn handle punctuations properly
      expect(tests['p1'], equals(Value(",")));
      expect(tests['l1'], equals(Value("abc")));
      expect(tests['u1'], equals(Value("DEF")));
      expect(tests['A1'], equals(Value("123")));
      expect(tests['D1'], equals(Value("abc")));
    });

    // Pattern matching special items
    test('pattern matching special items', () async {
      final bridge = LuaLike();
      await bridge.runCode(r'''
        tests = {}

        -- Anchors
        tests.anchor1 = string.match("hello world", "^hell")
        tests.anchor2 = string.match("hello world", "world$")
        tests.anchor3 = string.match("hello world", "^world")

        -- Repetition
        tests.rep1 = string.match("abbbc", "ab*c")
        tests.rep2 = string.match("ac", "ab*c")
        tests.rep3 = string.match("abbbc", "ab+c")
        tests.rep4 = string.match("ac", "ab+c")
        tests.rep5 = string.match("abbbc", "ab?c")

        -- Balanced expressions
        tests.balanced1 = string.match("(hello (world))", "%b()")
        tests.balanced2 = string.match("{hello [world]}", "%b{}")

        -- Frontier pattern
        tests.frontier1 = string.match("hello world", "%f[%w]hello")
      ''');

      final tests = (bridge.getGlobal('tests') as Value).raw as Map;
      expect(tests['anchor1'], equals(Value("hell")));
      expect(tests['anchor2'], equals(Value("world")));
      // Keys assigned nil should be removed entirely
      expect(tests['anchor3'], isNull);

      expect(tests['rep1'], equals(Value("abbbc")));
      expect(tests['rep2'], equals(Value("ac")));
      expect(tests['rep3'], equals(Value("abbbc")));
      // Keys assigned nil should be removed entirely
      expect(tests['rep4'], isNull);
      // "ab?c" does not match "abbbc" in Lua, so the key is removed
      expect(tests['rep5'], isNull);

      expect(tests['balanced1'], equals(Value("(hello (world))")));
      expect(tests['balanced2'], equals(Value("{hello [world]}")));

      expect(tests['frontier1'], equals(Value("hello")));
    });

    test('string.format comprehensive', () async {
      final bridge = LuaLike();

      // Basic format specifiers
      final result = await bridge.runCode('''
          local tests = {}

          -- Basic format specifiers
          tests.basic1 = string.format("%d", 42)
          tests.basic2 = string.format("%i", -42)
          tests.basic3 = string.format("%u", 42)
          tests.basic4 = string.format("%f", 3.14)
          tests.basic5 = string.format("%s", "hello")

          -- Multiple format specifiers
          tests.multi1 = string.format("%d %d", 1, 2)
          tests.multi2 = string.format("%s %s", "hello", "world")
          tests.multi3 = string.format("%d %f %s", 42, 3.14, "test")

          -- Width specifier
          tests.width1 = string.format("%5d", 42)
          tests.width2 = string.format("%10s", "test")

          -- Precision specifier
          tests.prec1 = string.format("%.2f", 3.14159)
          tests.prec2 = string.format("%.0f", 3.14159)

          -- Flags
          tests.flags1 = string.format("%+d", 42)
          tests.flags2 = string.format("%+d", -42)
          tests.flags3 = string.format("%-5d", 42)
          tests.flags4 = string.format("%05d", 42)
          tests.flags5 = string.format("% d", 42)

          -- q specifier
          tests.q1 = string.format("%q", "hello")
          tests.q2 = string.format("%q", "hello\\nworld")
          tests.q3 = string.format("%q", "quotes \\"here\\"")
          tests.q4 = string.format("%q", true)
          tests.q5 = string.format("%q", false)
          tests.q6 = string.format("%q", nil)

          -- Hexadecimal specifiers
          tests.hex1 = string.format("%x", 255)
          tests.hex2 = string.format("%X", 255)
          tests.hex3 = string.format("%#x", 255)
          tests.hex4 = string.format("%#X", 255)

          -- Octal specifier
          tests.oct1 = string.format("%o", 63)
          tests.oct2 = string.format("%#o", 63)

          -- Scientific notation
          tests.sci1 = string.format("%.2e", 12345.6789)
          tests.sci2 = string.format("%.2E", 12345.6789)

          -- Combination of width and precision
          tests.combo1 = string.format("%8.2f", 3.14159)
          tests.combo2 = string.format("%8.2e", 3.14159)

          -- Zero padding with precision
          tests.zero1 = string.format("%08.2f", 3.14159)

          -- Character specifier
          tests.char1 = string.format("%c", 65)
          tests.char2 = string.format("%c", 97)

          -- Pointer specifier
          tests.ptr1 = string.format("%p", "test")
          return tests
        ''');
      // Multiple format specifiers
      final tests = (result as Value).raw as Map;

      expect(tests['basic1'], equals(Value('42')));
      expect(tests['basic2'], equals(Value('-42')));
      expect(tests['basic3'], equals(Value('42')));
      expect(tests['basic4'], equals(Value('3.140000')));
      expect(tests['basic5'], equals(Value('hello')));

      expect(tests['multi1'], equals(Value('1 2')));
      expect(tests['multi2'], equals(Value('hello world')));
      expect(tests['multi3'], equals(Value('42 3.140000 test')));

      expect(tests['width1'], equals(Value('   42')));
      expect(tests['width2'], equals(Value('      test')));

      expect(tests['prec1'], equals(Value('3.14')));
      expect(tests['prec2'], equals(Value('3')));

      expect(tests['flags1'], equals(Value('+42')));
      expect(tests['flags2'], equals(Value('-42')));
      expect(tests['flags3'], equals(Value('42   ')));
      expect(tests['flags4'], equals(Value('00042')));
      expect(tests['flags5'], equals(Value(' 42')));

      expect(tests['q1'], equals(Value('"hello"')));
      expect(tests['q2'], equals(Value('"hello\\nworld"')));
      expect(tests['q3'], equals(Value('"quotes \\"here\\""')));
      expect(tests['q4'], equals(Value('true')));
      expect(tests['q5'], equals(Value('false')));
      expect(tests['q6'], equals(Value('nil')));

      expect(tests['hex1'], equals(Value('ff')));
      expect(tests['hex2'], equals(Value('FF')));
      expect(tests['hex3'], equals(Value('0xff')));
      expect(tests['hex4'], equals(Value('0xFF')));

      expect(tests['oct1'], equals(Value('77')));
      expect(tests['oct2'], equals(Value('077')));

      expect(tests['sci1'], equals(Value('1.23e+04')));
      expect(tests['sci2'], equals(Value('1.23E+04')));

      expect(tests['combo1'], equals(Value('    3.14')));
      expect(tests['combo2'], equals(Value(' 3.14e+00')));

      expect(tests['zero1'], equals(Value('00003.14')));

      expect(tests['char1'], equals(Value('A')));
      expect(tests['char2'], equals(Value('a')));

      expect(tests['ptr1'].raw.toString(), matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('Lua strings.lua: %q%s complex case', () async {
      final bridge = LuaLike();
      final script = r'''
        local x = '"\225lo"\n\\'
        result = string.format('%q%s', x, x)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).raw.toString();
      // The expected string matches Lua's actual behavior: %q shows byte 225 as \225 (escaped),
      // and %s shows byte 225 as replacement character � when converted to string
      // Note: the \n in %q format is escaped as backslash followed by actual newline
      final expected = '"\\"\\225lo\\"\\\n\\\\""�lo"\n\\';
      expect(result, equals(expected));
    });

    test('Lua strings.lua: %q with null byte', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('%q', "\0")
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('"\\0"'));
    });

    test('Lua strings.lua: empty format string', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('')
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals(''));
    });

    test('Lua strings.lua: %c and concatenation', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%c",34)..string.format("%c",48)..string.format("%c",90)..string.format("%c",100)
        expected = string.format("%1c%-c%-1c%c", 34, 48, 90, 100)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      final expected = (bridge.getGlobal('expected') as Value).unwrap();
      expect(result, equals(expected));
    });

    test('Lua strings.lua: %s\\0 is not \\0%s', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%s\0 is not \0%s", 'not be', 'be')
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('not be\x00 is not \x00be'));
    });

    test('Lua strings.lua: %%%d %010d', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%%%d %010d", 10, 23)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('%10 0000000023'));
    });

    test('Lua strings.lua: %f float', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%f", 10.3)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(double.parse(result), closeTo(10.3, 1e-6));
    });

    test('Lua strings.lua: quoted string with width', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('"%-50s"', 'a')
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('"a${' ' * 49}"'));
    });

    test('Lua strings.lua: -%.20s.20s', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("-%.20s.20s", string.rep("%", 2000))
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('-${'%' * 20}.20s'));
    });

    test('Lua strings.lua: quoted long string', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format('"-%20s.20s"', string.rep("%", 2000))
        expected = string.format("%q", "-"..string.rep("%", 2000)..".20s")
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      final expected = (bridge.getGlobal('expected') as Value).unwrap();
      expect(result, equals(expected));
    });

    test('Lua strings.lua: %s %s nil true', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%s %s", nil, true)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('nil true'));
    });

    test('Lua strings.lua: %s %.4s false true', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%s %.4s", false, true)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('false true'));
    });

    test('Lua strings.lua: %.3s %.3s false true', () async {
      final bridge = LuaLike();
      final script = r'''
        result = string.format("%.3s %.3s", false, true)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('fal tru'));
    });

    test('Lua strings.lua: %s %.10s with metatable __tostring', () async {
      final bridge = LuaLike();
      final script = r'''
        local m = setmetatable({}, {__tostring = function () return "hello" end, __name = "hi"})
        result = string.format("%s %.10s", m, m)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('hello hello'));
    });

    test('Lua strings.lua: %.4s with metatable __name', () async {
      final bridge = LuaLike();
      final script = r'''
        local m = setmetatable({}, {__tostring = function () return "hello" end, __name = "hi"})
        getmetatable(m).__tostring = nil
        result = string.format("%.4s", m)
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, equals('hi: '));
    });

    // Error cases
    test('Lua strings.lua: error on invalid conversion', () async {
      final bridge = LuaLike();
      final script = r'''
        local ok, err = pcall(function() string.format('%t', 10) end)
        result = err
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, contains('invalid conversion'));
    });

    test('Lua strings.lua: error on too long format', () async {
      final bridge = LuaLike();
      final script = r'''
        local aux = string.rep('0', 600)
        local ok, err = pcall(function() string.format('%1'..aux..'d', 10) end)
        result = err
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, contains('too long'));
    });

    test('Lua strings.lua: error on no value', () async {
      final bridge = LuaLike();
      final script = r'''
        local ok, err = pcall(function() string.format('%d %d', 10) end)
        result = err
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, contains('no value'));
    });

    test('Lua strings.lua: error on cannot have modifiers for %q', () async {
      final bridge = LuaLike();
      final script = r'''
        local ok, err = pcall(function() string.format('%10q', 'foo') end)
        result = err
      ''';
      await bridge.runCode(script);
      final result = (bridge.getGlobal('result') as Value).unwrap();
      expect(result, contains('cannot have modifiers'));
    });
  });
}
