@Tags(['stdlib'])
import 'package:lualike/lualike.dart';
import 'package:lualike/src/interop.dart' show LuaLikeBridge;
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    Logger.setEnabled(true);
  });
  group('String Library', () {
    // Basic string operations
    test('string.len', () async {
      final bridge = LuaLikeBridge();
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
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local a = string.byte("ABCDE", 1)
        local b = string.byte("ABCDE", 2, 4)
        local c = string.byte("ABCDE", -1) -- negative index
      ''');

      expect(
        (bridge.getGlobal('a') as Value).unwrap(),
        equals(65),
      ); // ASCII for 'A'

      final bResult = (bridge.getGlobal('b') as Value).unwrap();
      expect(bResult, isList);
      final bList = bResult as List;
      expect(bList.length, equals(3));
      expect((bList[0] as Value).raw, equals(66)); // 'B'
      expect((bList[1] as Value).raw, equals(67)); // 'C'
      expect((bList[2] as Value).raw, equals(68)); // 'D'

      expect((bridge.getGlobal('c') as Value).raw, equals(69)); // 'E'
    });

    test('string.char', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local a = string.char(65, 66, 67, 68, 69)
        local b = string.char()
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("ABCDE"));
      expect((bridge.getGlobal('b') as Value).raw, equals(""));
    });

    test('string.sub', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local s = "abcdefghijklm"
        local a = string.sub(s, 3, 5)    -- "cde"
        local b = string.sub(s, 3)       -- "cdefghijklm"
        local c = string.sub(s, -5)      -- "ijklm"
        local d = string.sub(s, -5, -3)  -- "ijk"
        local e = string.sub(s, 10, 5)   -- "" (start > end)
        local f = string.sub(s, 100, 200) -- "" (start > string length)
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("cde"));
      expect((bridge.getGlobal('b') as Value).raw, equals("cdefghijklm"));
      expect((bridge.getGlobal('c') as Value).raw, equals("ijklm"));
      expect((bridge.getGlobal('d') as Value).raw, equals("ijk"));
      expect((bridge.getGlobal('e') as Value).raw, equals(""));
      expect((bridge.getGlobal('f') as Value).raw, equals(""));
    });

    test('string.upper and string.lower', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local a = string.upper("Hello, World!")
        local b = string.lower("Hello, World!")
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("HELLO, WORLD!"));
      expect((bridge.getGlobal('b') as Value).raw, equals("hello, world!"));
    });

    test('string.reverse', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local a = string.reverse("hello")
        local b = string.reverse("")
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("olleh"));
      expect((bridge.getGlobal('b') as Value).raw, equals(""));
    });

    test('string.rep', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local a = string.rep("abc", 3)
        local b = string.rep("abc", 3, "-")
        local c = string.rep("abc", 0)
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("abcabcabc"));
      expect((bridge.getGlobal('b') as Value).raw, equals("abc-abc-abc"));
      expect((bridge.getGlobal('c') as Value).raw, equals(""));
    });

    // Pattern matching
    test('string.find basic', () async {
      final bridge = LuaLikeBridge();
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
      expect((bridge.getGlobal('m') as Value).raw, equals(8));
      expect((bridge.getGlobal('n') as Value).raw, equals(8));
      expect(
        (bridge.getGlobal('plain_i') as Value).raw,
        isNull,
      ); // "o." not found as plain text
    });

    test('string.find with captures', () async {
      final bridge = LuaLikeBridge();
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
      final bridge = LuaLikeBridge();
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
    }, skip: 'Issue with pattern matching');

    test('string.gsub', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local s = "hello world from lua"
        local r1, n1 = string.gsub(s, "l", "L")
        local r2, n2 = string.gsub(s, "l", "L", 2) -- replace only 2 occurrences
        local r3, n3 = string.gsub(s, "(%w+)", "%1!")
      ''');

      expect(
        (bridge.getGlobal('r1') as Value).raw,
        equals("heLLo worLd from Lua"),
      );
      expect((bridge.getGlobal('n1') as Value).raw, equals(4));
      expect(
        (bridge.getGlobal('r2') as Value).raw,
        equals("heLLo world from lua"),
      );
      expect((bridge.getGlobal('n2') as Value).raw, equals(2));
      expect(
        (bridge.getGlobal('r3') as Value).raw,
        equals("hello! world! from! lua!"),
      );
      expect((bridge.getGlobal('n3') as Value).raw, equals(4));
    });

    test('string.gmatch', () async {
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
        local s = "hello world from lua"
        local words = {}
        local i = 1
        for w in string.gmatch(s, "%w+") do
          words[i] = w
          i = i + 1
        end

        local pairs = {}
        i = 1
        local s2 = "key1=value1 key2=value2"
        for k, v in string.gmatch(s2, "(%w+)=(%w+)") do
          pairs[i] = {k=k, v=v}
          i = i + 1
        end
      ''');

      // Check words array
      final words = (bridge.getGlobal('words') as Value).raw as Map;
      expect((words[1] as Value).raw, equals("hello"));
      expect((words[2] as Value).raw, equals("world"));
      expect((words[3] as Value).raw, equals("from"));
      expect((words[4] as Value).raw, equals("lua"));

      // Check key-value pairs
      final pairs = (bridge.getGlobal('pairs') as Value).raw as Map;
      final pair1 = pairs[1] as Map;
      final pair2 = pairs[2] as Map;
      expect((pair1['k'] as Value).raw, equals("key1"));
      expect((pair1['v'] as Value).raw, equals("value1"));
      expect((pair2['k'] as Value).raw, equals("key2"));
      expect((pair2['v'] as Value).raw, equals("value2"));
    });

    // Binary string operations
    test('string.pack/unpack roundtrip', () async {
      final bridge = LuaLikeBridge();

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
      expect(
        (pos as Value).raw,
        equals(8),
      ); // 1 + 2 + 4 + 1 (position after data)
    });

    test('string.packsize', () async {
      final bridge = LuaLikeBridge();

      await bridge.runCode('''
        local size = string.packsize("bhi")
      ''');

      var size = bridge.getGlobal('size');
      expect((size as Value).raw, equals(7)); // 1 + 2 + 4 bytes
    });

    test('string.dump basic functionality', () async {
      final bridge = LuaLikeBridge();

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
      final bridge = LuaLikeBridge();
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
      final bridge = LuaLikeBridge();
      await bridge.runCode('''
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
      ''');

      final tests = (bridge.getGlobal('tests') as Value).raw as Map;
      expect(tests['a1'], equals(Value("abc")));
      expect(tests['a2'], equals(Value("abc")));
      expect(tests['d1'], equals(Value("123")));
      expect(tests['d2'], equals(Value("123")));
      expect(tests['s1'], equals(Value(" ")));
      expect(tests['w1'], equals(Value("hello123")));
      expect(tests['p1'], equals(Value(",")));
      expect(tests['l1'], equals(Value("abc")));
      expect(tests['u1'], equals(Value("DEF")));
      expect(tests['A1'], equals(Value("123")));
      expect(tests['D1'], equals(Value("abc")));
    }, skip: 'Issue with pattern matching');

    // Pattern matching special items
    test('pattern matching special items', () async {
      Logger.setEnabled(true);
      final bridge = LuaLikeBridge();
      await bridge.runCode(r'''
        local tests = {}

        -- Anchors
        tests.anchor1 = string.match("hello world", "^hell")
        tests.anchor2 = string.match("hello world", "world\$")
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
      expect(tests['anchor3'], equals(Value(null)));

      expect(tests['rep1'], equals(Value("abbbc")));
      expect(tests['rep2'], equals(Value("ac")));
      expect(tests['rep3'], equals(Value("abbbc")));
      expect(tests['rep4'], equals(Value(null)));
      expect(tests['rep5'], equals(Value("abc")));

      expect(tests['balanced1'], equals(Value("(hello (world))")));
      expect(tests['balanced2'], equals(Value("{hello [world]}")));

      expect(tests['frontier1'], equals(Value("hello")));
    }, skip: 'Issue with pattern matching');

    test('string.format comprehensive', () async {
      final bridge = LuaLikeBridge();

      // Basic format specifiers
      await bridge.runCode('''
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
        ''');
      // Multiple format specifiers
      final tests = (bridge.getGlobal('tests') as Value).raw as Map;

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
  });
}
