@Tags(['pm'])
library;

import 'package:lualike/testing.dart';

void main() {
  group('String Pattern Matching', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    group('basic patterns', () {
      test('greedy dot patterns', () async {
        // From pm.lua:
        // assert(string.match("aaab", ".*b") == "aaab")
        // assert(string.match("aaa", ".*a") == "aaa")
        // assert(string.match("b", ".*b") == "b")
        await bridge.execute('''
          local r1 = string.match("aaab", ".*b")
          local r2 = string.match("aaa", ".*a")
          local r3 = string.match("b", ".*b")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("aaab"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("aaa"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("b"));
      });

      test('plus patterns', () async {
        // From pm.lua:
        // assert(string.match("aaab", ".+b") == "aaab")
        // assert(string.match("aaa", ".+a") == "aaa")
        // assert(not string.match("b", ".+b"))
        await bridge.execute('''
          local r1 = string.match("aaab", ".+b")
          local r2 = string.match("aaa", ".+a")
          local r3 = string.match("b", ".+b")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("aaab"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("aaa"));
        expect((bridge.getGlobal('r3') as Value).raw, isNull);
      });

      test('optional patterns', () async {
        // From pm.lua:
        // assert(string.match("aaab", ".?b") == "ab")
        // assert(string.match("aaa", ".?a") == "aa")
        // assert(string.match("b", ".?b") == "b")
        await bridge.execute('''
          local r1 = string.match("aaab", ".?b")
          local r2 = string.match("aaa", ".?a")
          local r3 = string.match("b", ".?b")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("ab"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("aa"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("b"));
      });

      test('non-greedy patterns', () async {
        await bridge.execute('''
          local r1 = string.match("aaab", ".-b")
          local r2 = string.match("aaa", ".-a")
          local r3 = string.match("aaabc", "a.-c")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("aaab"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("a"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("aaabc"));
      });
    });

    group('character classes', () {
      test('basic character classes', () async {
        await bridge.execute('''
          local r1 = string.match("abc123", "%a+")
          local r2 = string.match("abc123", "%d+")
          local r3 = string.match("abc123", "%w+")
          local r4 = string.match("abc 123", "%s+")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("abc"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("123"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("abc123"));
        expect((bridge.getGlobal('r4') as Value).raw, equals(" "));
      });

      test('negated character classes', () async {
        await bridge.execute('''
          local r1 = string.match("abc123", "%A+")
          local r2 = string.match("abc123", "%D+")
          local r3 = string.match("abc123", "%W+")
          local r4 = string.match("abc 123", "%S+")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("123"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("abc"));
        expect((bridge.getGlobal('r3') as Value).raw, isNull);
        expect((bridge.getGlobal('r4') as Value).raw, equals("abc"));
      });

      test('custom character classes', () async {
        await bridge.execute('''
          local r1 = string.match("abc123", "[a-z]+")
          local r2 = string.match("abc123", "[0-9]+")
          local r3 = string.match("abc123", "[^a-z]+")
          local r4 = string.match("abc123", "[^0-9]+")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("abc"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("123"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("123"));
        expect((bridge.getGlobal('r4') as Value).raw, equals("abc"));
      });
    });

    group('captures', () {
      test('word captures', () async {
        // From pm.lua:
        // assert(string.match("alo xyzK", "(%w+)K") == "xyz")
        // assert(string.match("254 K", "(%d*)K") == "")
        await bridge.execute('''
          local r1 = string.match("alo xyzK", "(%w+)K")
          local r2 = string.match("254 K", "(%d*)K")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("xyz"));
        expect((bridge.getGlobal('r2') as Value).raw, equals(""));
      });

      test('end of string captures', () async {
        // From pm.lua:
        // assert(string.match("alo ", "(%w*)$") == "")
        // assert(not string.match("alo ", "(%w+)$"))
        await bridge.execute(r'''
          local r1 = string.match("alo ", "(%w*)$")
          local r2 = string.match("alo ", "(%w+)$")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals(""));
        expect((bridge.getGlobal('r2') as Value).raw, isNull);
      });

      test('basic captures', () async {
        await bridge.execute('''
          local r1 = string.match("abc123", "(%a+)(%d+)")
          local r2 = string.match("name = value", "(%w+)%s*=%s*(%w+)")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("abc"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("name"));
      });

      test('multiple captures', () async {
        await bridge.execute('''
          local a, b = string.match("abc123", "(%a+)(%d+)")
          local c, d = string.match("name = value", "(%w+)%s*=%s*(%w+)")
        ''');

        expect((bridge.getGlobal('a') as Value).raw, equals("abc"));
        expect((bridge.getGlobal('b') as Value).raw, equals("123"));
        expect((bridge.getGlobal('c') as Value).raw, equals("name"));
        expect((bridge.getGlobal('d') as Value).raw, equals("value"));
      });

      test('nested captures', () async {
        await bridge.execute('''
          local a, b, c = string.match("abc123", "((%a+)(%d+))")
        ''');

        expect((bridge.getGlobal('a') as Value).raw, equals("abc123"));
        expect((bridge.getGlobal('b') as Value).raw, equals("abc"));
        expect((bridge.getGlobal('c') as Value).raw, equals("123"));
      });
    });

    group('special patterns', () {
      test('frontier patterns', () async {
        // From pm.lua:
        // local k = string.match(" alo aalo allo", "%f[%S](.-%f[%s].-%f[%S])")
        await bridge.execute('''
          local k = string.match(" alo aalo allo", "%f[%S](.-%f[%s].-%f[%S])")
        ''');

        expect((bridge.getGlobal('k') as Value).raw, equals("alo "));
      });

      test('zero patterns', () async {
        // From pm.lua:
        // assert(string.match("abc\\0\\1\\2c", "[\\0-\\2]+") == "\\0\\1\\2")
        // assert(string.match("abc\\0\\0\\0", "%\\0+") == "\\0\\0\\0")
        await bridge.execute('''
          local r1 = string.match("abc\\0\\1\\2c", "[\\0-\\2]+")
          local r2 = string.match("abc\\0\\0\\0", "%\\0+")
        ''');

        expect(
          (bridge.getGlobal('r1') as Value).raw,
          equals("\u0000\u0001\u0002"),
        );
        expect(
          (bridge.getGlobal('r2') as Value).raw,
          equals("\u0000\u0000\u0000"),
        );
      });

      test('balanced patterns', () async {
        // From pm.lua:
        // assert(string.match("abc\\0efg\\0\\1e\\1g", "%b\\0\\1") == "\\0efg\\0\\1e\\1")
        await bridge.execute('''
          local r = string.match("abc\\0efg\\0\\1e\\1g", "%b\\0\\1")
        ''');

        expect(
          (bridge.getGlobal('r') as Value).raw,
          equals("\u0000efg\u0000\u0001e\u0001"),
        );
      });

      test('anchors', () async {
        await bridge.execute(r'''
          local r1 = string.match("hello world", "^%a+")
          local r2 = string.match("hello world", "%a+$")
          local r3 = string.match("hello", "^%a+$")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("hello"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("world"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("hello"));
      });
    });

    group('from Lua test suite', () {
      test('pm.lua examples', () async {
        await bridge.execute(r'''
          local r1 = string.match("aaab", ".*b")
          local r2 = string.match("aaa", ".*a")
          local r3 = string.match("b", ".*b")
          local r4 = string.match("aaab", ".+b")
          local r5 = string.match("aaa", ".+a")
          local r6 = string.match("b", ".+b")
          local r7 = string.match("aaab", ".?b")
          local r8 = string.match("aaa", ".?a")
          local r9 = string.match("b", ".?b")
          local r10 = string.match("alo xyzK", "(%w+)K")
          local r11 = string.match("254 K", "(%d*)K")
          local r12 = string.match("alo ", "(%w*)$")
          local r13 = string.match("alo ", "(%w+)$")
          local r14 = string.match(" alo aalo allo", "%f[%S](.-%f[%s].-%f[%S])")
          local r15 = string.match("abc\0\1\2c", "[\0-\2]+")
          local r16 = string.match("abc\0\0\0", "%\0+")
          local r17 = string.match("abc\0efg\0\1e\1g", "%b\0\1")
        ''');

        expect((bridge.getGlobal('r1') as Value).raw, equals("aaab"));
        expect((bridge.getGlobal('r2') as Value).raw, equals("aaa"));
        expect((bridge.getGlobal('r3') as Value).raw, equals("b"));
        expect((bridge.getGlobal('r4') as Value).raw, equals("aaab"));
        expect((bridge.getGlobal('r5') as Value).raw, equals("aaa"));
        expect((bridge.getGlobal('r6') as Value).raw, isNull);
        expect((bridge.getGlobal('r7') as Value).raw, equals("ab"));
        expect((bridge.getGlobal('r8') as Value).raw, equals("aa"));
        expect((bridge.getGlobal('r9') as Value).raw, equals("b"));
        expect((bridge.getGlobal('r10') as Value).raw, equals("xyz"));
        expect((bridge.getGlobal('r11') as Value).raw, equals(""));
        expect((bridge.getGlobal('r12') as Value).raw, equals(""));
        expect((bridge.getGlobal('r13') as Value).raw, isNull);
        expect((bridge.getGlobal('r14') as Value).raw, equals("alo "));
        expect(
          (bridge.getGlobal('r15') as Value).raw,
          equals("\u0000\u0001\u0002"),
        );
        expect(
          (bridge.getGlobal('r16') as Value).raw,
          equals("\u0000\u0000\u0000"),
        );
        expect(
          (bridge.getGlobal('r17') as Value).raw,
          equals("\u0000efg\u0000\u0001e\u0001"),
        );
      });
    });
  });
}
