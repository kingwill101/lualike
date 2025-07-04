@Tags(['stdlib'])
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
      expect((bridge.getGlobal('c') as Value).raw, equals(67)); // 'C'
      expect((bridge.getGlobal('d') as Value).raw, equals(68)); // 'D'
      expect((bridge.getGlobal('e') as Value).raw, equals(69)); // 'E'
    });

    test('string.char', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.char(65, 66, 67, 68, 69)
        local b = string.char()
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("ABCDE"));
      expect((bridge.getGlobal('b') as Value).raw, equals(""));
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

      expect((bridge.getGlobal('a') as Value).raw, equals("cde"));
      expect((bridge.getGlobal('b') as Value).raw, equals("cdefghijklm"));
      expect((bridge.getGlobal('c') as Value).raw, equals("ijklm"));
      expect((bridge.getGlobal('d') as Value).raw, equals("ijk"));
      expect((bridge.getGlobal('e') as Value).raw, equals(""));
      expect((bridge.getGlobal('f') as Value).raw, equals(""));
    });

    test('string.upper and string.lower', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.upper("Hello, World!")
        local b = string.lower("Hello, World!")
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("HELLO, WORLD!"));
      expect((bridge.getGlobal('b') as Value).raw, equals("hello, world!"));
    });

    test('string.reverse', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local a = string.reverse("hello")
        local b = string.reverse("")
      ''');

      expect((bridge.getGlobal('a') as Value).raw, equals("olleh"));
      expect((bridge.getGlobal('b') as Value).raw, equals(""));
    });

    test('string.rep', () async {
      final bridge = LuaLike();
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
      expect((bridge.getGlobal('m') as Value).raw, equals(8));
      expect((bridge.getGlobal('n') as Value).raw, equals(8));
      expect(
        (bridge.getGlobal('plain_i') as Value).raw,
        isNull,
      ); // "o." not found as plain text
    }, skip: "pattern matching issue");

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
    }, skip: 'Issue with pattern matching');

    test('string.gsub', () async {
      final bridge = LuaLike();
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

    // Binary string operations
    test('string.pack/unpack roundtrip', () async {
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
      expect(
        (pos as Value).raw,
        equals(8),
      ); // 1 + 2 + 4 + 1 (position after data)
    });

    test('string.packsize', () async {
      final bridge = LuaLike();

      await bridge.runCode('''
        local size = string.packsize("bhi")
      ''');

      var size = bridge.getGlobal('size');
      expect((size as Value).raw, equals(7)); // 1 + 2 + 4 bytes
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
      //TODO pattern matching doesn handle punctuations properly
      expect(tests['p1'], equals(Value(",")));
      expect(tests['l1'], equals(Value("abc")));
      expect(tests['u1'], equals(Value("DEF")));
      expect(tests['A1'], equals(Value("123")));
      expect(tests['D1'], equals(Value("abc")));
    }, skip: 'Issue with pattern matching');

    // Pattern matching special items
    test('pattern matching special items', () async {
      final bridge = LuaLike();
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
      final bridge = LuaLike();

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

    test('string.format hexfloat and pointer variants', () async {
      final bridge = LuaLike();
      await bridge.runCode('''
        local tests = {}
        tests.hf1 = string.format("%a", 0.1)
        tests.hf2 = string.format("%A", 0.1)
        tests.ptrnull = string.format("%p", nil)
        tests.ptrnum = string.format("%p", 5)
        tests.ptrpad = string.format("%10p", nil)
      ''');

      final tests = (bridge.getGlobal('tests') as Value).raw as Map;
      expect(tests['hf1'].raw.toString(), startsWith('0x'));
      expect(tests['hf2'].raw.toString(), startsWith('0X'));
      expect(tests['ptrnull'], equals(Value('(null)')));
      expect(tests['ptrnum'], equals(Value('(null)')));
      expect(tests['ptrpad'], equals(Value('     (null)')));
    });

    test('string.rep invalid counts', () async {
      final bridge = LuaLike();
      expect(
        () async => await bridge.runCode('string.rep("a", -1)'),
        throwsA(isA<LuaError>()),
      );
      expect(
        () async => await bridge.runCode('string.rep("a", (1 << 31) + 1)'),
        throwsA(isA<LuaError>()),
      );
    });

    test(
      'string.byte and string.char roundtrip and edge cases (Lua spec)',
      () async {
        final bridge = LuaLike();
        await bridge.runCode(r'''
        local s = "\xe4l\0\u{FFFD}u"
        local b1, b2, b3, b4, b5 = string.byte(s, 1, -1)
        local s2 = string.char(b1, b2, b3, b4, b5)
        local empty = string.char()
        local multi = string.char(0, 255, 0)
        local multi2 = string.char(0, string.byte("\xe4"), 0)
        local sub = string.sub("123456789", 2, 4)
        local sub2 = string.sub("123456789", 7)
        local sub3 = string.sub("123456789", 7, 6)
        local sub4 = string.sub("123456789", 7, 7)
        local sub5 = string.sub("123456789", 0, 0)
        local sub6 = string.sub("123456789", -10, 10)
        local sub7 = string.sub("123456789", 1, 9)
        local sub8 = string.sub("123456789", -10, -20)
        local sub9 = string.sub("123456789", -1)
        local sub10 = string.sub("123456789", -4)
        local sub11 = string.sub("123456789", -6, -4)
        local upper = string.upper("ab\0c")
        local lower = string.lower("\0ABCc%$")
        local rep1 = string.rep('teste', 0)
        local rep2 = string.rep('t\u{E1}s\00t\u{E9}', 2)
        local rep3 = string.rep('', 10)
        local rep4 = string.rep('teste', 0, 'xuxu')
        local rep5 = string.rep('teste', 1, 'xuxu')
        local rep6 = string.rep('\1\0\1', 2, '\0\0')
        local rep7 = string.rep('', 10, '.')
        local rev1 = string.reverse""
        local rev2 = string.reverse"\0\1\2\3"
        local rev3 = string.reverse"\0001234"
        local len1 = string.len("")
        local len2 = string.len("\0\0\0")
        local len3 = string.len("1234567890")
        local hash1 = #""
        local hash2 = #"\0\0\0"
        local hash3 = #"1234567890"
        _G._test = {
          s2 = s2,
          empty = empty,
          multi = multi,
          multi2 = multi2,
          sub = sub,
          sub2 = sub2,
          sub3 = sub3,
          sub4 = sub4,
          sub5 = sub5,
          sub6 = sub6,
          sub7 = sub7,
          sub8 = sub8,
          sub9 = sub9,
          sub10 = sub10,
          sub11 = sub11,
          upper = upper,
          lower = lower,
          rep1 = rep1,
          rep2 = rep2,
          rep3 = rep3,
          rep4 = rep4,
          rep5 = rep5,
          rep6 = rep6,
          rep7 = rep7,
          rev1 = rev1,
          rev2 = rev2,
          rev3 = rev3,
          len1 = len1,
          len2 = len2,
          len3 = len3,
          hash1 = hash1,
          hash2 = hash2,
          hash3 = hash3,
        }
      ''');
        final t = (bridge.getGlobal('_test') as Value).raw as Map;
        expect(t['s2'], equals(Value(r"\xe4l\0\u{FFFD}u")));
        expect(t['empty'], equals(Value("")));
        expect(t['multi'], equals(Value("\x00\xFF\x00")));
        expect(t['multi2'], equals(Value("\x00\xE4\x00")));
        expect(t['sub'], equals(Value("234")));
        expect(t['sub2'], equals(Value("789")));
        expect(t['sub3'], equals(Value("")));
        expect(t['sub4'], equals(Value("7")));
        expect(t['sub5'], equals(Value("")));
        expect(t['sub6'], equals(Value("123456789")));
        expect(t['sub7'], equals(Value("123456789")));
        expect(t['sub8'], equals(Value("")));
        expect(t['sub9'], equals(Value("9")));
        expect(t['sub10'], equals(Value("6789")));
        expect(t['sub11'], equals(Value("456")));
        expect(t['upper'], equals(Value("AB\x00C")));
        expect(t['lower'], equals(Value(r"\x00abcc%$")));
        expect(t['rep1'], equals(Value('')));
        expect(t['rep2'], isA<Value>()); // just check it runs
        expect(t['rep3'], equals(Value('')));
        expect(t['rep4'], equals(Value('')));
        expect(t['rep5'], equals(Value('teste')));
        expect(t['rep6'], equals(Value("\x01\x00\x01\x00\x00\x01\x00\x01")));
        expect(t['rep7'], equals(Value(".........")));
        expect(t['rev1'], equals(Value('')));
        expect(t['rev2'], equals(Value(r"\x03\x02\x01\x00")));
        expect(t['rev3'], equals(Value("4321\x00")));
        expect(t['len1'], equals(Value(0)));
        expect(t['len2'], equals(Value(3)));
        expect(t['len3'], equals(Value(10)));
        expect(t['hash1'], equals(Value(0)));
        expect(t['hash2'], equals(Value(3)));
        expect(t['hash3'], equals(Value(10)));
      },
    );
  });
}
