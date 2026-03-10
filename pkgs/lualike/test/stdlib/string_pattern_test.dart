@Tags(['pm'])
library;

import 'package:lualike_test/test.dart';

Object? _unwrapGlobal(LuaLike bridge, String name) {
  return (bridge.getGlobal(name) as Value).unwrap();
}

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
          r1 = string.match("aaab", ".*b")
          r2 = string.match("aaa", ".*a")
          r3 = string.match("b", ".*b")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("aaab"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("aaa"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("b"));
      });

      test('plus patterns', () async {
        // From pm.lua:
        // assert(string.match("aaab", ".+b") == "aaab")
        // assert(string.match("aaa", ".+a") == "aaa")
        // assert(not string.match("b", ".+b"))
        await bridge.execute('''
          r1 = string.match("aaab", ".+b")
          r2 = string.match("aaa", ".+a")
          r3 = string.match("b", ".+b")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("aaab"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("aaa"));
        expect(_unwrapGlobal(bridge, 'r3'), isNull);
      });

      test('optional patterns', () async {
        // From pm.lua:
        // assert(string.match("aaab", ".?b") == "ab")
        // assert(string.match("aaa", ".?a") == "aa")
        // assert(string.match("b", ".?b") == "b")
        await bridge.execute('''
          r1 = string.match("aaab", ".?b")
          r2 = string.match("aaa", ".?a")
          r3 = string.match("b", ".?b")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("ab"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("aa"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("b"));
      });

      test('non-greedy patterns', () async {
        await bridge.execute('''
          r1 = string.match("aaab", ".-b")
          r2 = string.match("aaa", ".-a")
          r3 = string.match("aaabc", "a.-c")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("aaab"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("a"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("aaabc"));
      });
    });

    group('character classes', () {
      test('basic character classes', () async {
        await bridge.execute('''
          r1 = string.match("abc123", "%a+")
          r2 = string.match("abc123", "%d+")
          r3 = string.match("abc123", "%w+")
          r4 = string.match("abc 123", "%s+")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("abc"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("123"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("abc123"));
        expect(_unwrapGlobal(bridge, 'r4'), equals(" "));
      });

      test('negated character classes', () async {
        await bridge.execute('''
          r1 = string.match("abc123", "%A+")
          r2 = string.match("abc123", "%D+")
          r3 = string.match("abc123", "%W+")
          r4 = string.match("abc 123", "%S+")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("123"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("abc"));
        expect(_unwrapGlobal(bridge, 'r3'), isNull);
        expect(_unwrapGlobal(bridge, 'r4'), equals("abc"));
      });

      test('custom character classes', () async {
        await bridge.execute('''
          r1 = string.match("abc123", "[a-z]+")
          r2 = string.match("abc123", "[0-9]+")
          r3 = string.match("abc123", "[^a-z]+")
          r4 = string.match("abc123", "[^0-9]+")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("abc"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("123"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("123"));
        expect(_unwrapGlobal(bridge, 'r4'), equals("abc"));
      });
    });

    group('captures', () {
      test('word captures', () async {
        // From pm.lua:
        // assert(string.match("alo xyzK", "(%w+)K") == "xyz")
        // assert(string.match("254 K", "(%d*)K") == "")
        await bridge.execute('''
          r1 = string.match("alo xyzK", "(%w+)K")
          r2 = string.match("254 K", "(%d*)K")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("xyz"));
        expect(_unwrapGlobal(bridge, 'r2'), equals(""));
      });

      test('end of string captures', () async {
        // From pm.lua:
        // assert(string.match("alo ", "(%w*)$") == "")
        // assert(not string.match("alo ", "(%w+)$"))
        await bridge.execute(r'''
          r1 = string.match("alo ", "(%w*)$")
          r2 = string.match("alo ", "(%w+)$")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals(""));
        expect(_unwrapGlobal(bridge, 'r2'), isNull);
      });

      test('basic captures', () async {
        await bridge.execute('''
          r1 = string.match("abc123", "(%a+)(%d+)")
          r2 = string.match("name = value", "(%w+)%s*=%s*(%w+)")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("abc"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("name"));
      });

      test('multiple captures', () async {
        await bridge.execute('''
          a, b = string.match("abc123", "(%a+)(%d+)")
          c, d = string.match("name = value", "(%w+)%s*=%s*(%w+)")
        ''');

        expect(_unwrapGlobal(bridge, 'a'), equals("abc"));
        expect(_unwrapGlobal(bridge, 'b'), equals("123"));
        expect(_unwrapGlobal(bridge, 'c'), equals("name"));
        expect(_unwrapGlobal(bridge, 'd'), equals("value"));
      });

      test('nested captures', () async {
        await bridge.execute('''
          a, b, c = string.match("abc123", "((%a+)(%d+))")
        ''');

        expect(_unwrapGlobal(bridge, 'a'), equals("abc123"));
        expect(_unwrapGlobal(bridge, 'b'), equals("abc"));
        expect(_unwrapGlobal(bridge, 'c'), equals("123"));
      });
    });

    group('special patterns', () {
      test('frontier patterns', () async {
        // From pm.lua:
        // k = string.match(" alo aalo allo", "%f[%S](.-%f[%s].-%f[%S])")
        await bridge.execute('''
          k = string.match(" alo aalo allo", "%f[%S](.-%f[%s].-%f[%S])")
        ''');

        expect(_unwrapGlobal(bridge, 'k'), equals("alo "));
      });

      test('zero patterns', () async {
        // From pm.lua:
        // assert(string.match("abc\\0\\1\\2c", "[\\0-\\2]+") == "\\0\\1\\2")
        // assert(string.match("abc\\0\\0\\0", "%\\0+") == "\\0\\0\\0")
        await bridge.execute('''
          r1 = string.match("abc\\0\\1\\2c", "[\\0-\\2]+")
          r2 = string.match("abc\\0\\0\\0", "%\\0+")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("\u0000\u0001\u0002"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("\u0000\u0000\u0000"));
      });

      test('balanced patterns', () async {
        // From pm.lua:
        // assert(string.match("abc\\0efg\\0\\1e\\1g", "%b\\0\\1") == "\\0efg\\0\\1e\\1")
        await bridge.execute('''
          r = string.match("abc\\0efg\\0\\1e\\1g", "%b\\0\\1")
        ''');

        expect(
          _unwrapGlobal(bridge, 'r'),
          equals("\u0000efg\u0000\u0001e\u0001"),
        );
      });

      test('anchors', () async {
        await bridge.execute(r'''
          r1 = string.match("hello world", "^%a+")
          r2 = string.match("hello world", "%a+$")
          r3 = string.match("hello", "^%a+$")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("hello"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("world"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("hello"));
      });
    });

    group('from Lua test suite', () {
      test('pm.lua examples', () async {
        await bridge.execute(r'''
          r1 = string.match("aaab", ".*b")
          r2 = string.match("aaa", ".*a")
          r3 = string.match("b", ".*b")
          r4 = string.match("aaab", ".+b")
          r5 = string.match("aaa", ".+a")
          r6 = string.match("b", ".+b")
          r7 = string.match("aaab", ".?b")
          r8 = string.match("aaa", ".?a")
          r9 = string.match("b", ".?b")
          r10 = string.match("alo xyzK", "(%w+)K")
          r11 = string.match("254 K", "(%d*)K")
          r12 = string.match("alo ", "(%w*)$")
          r13 = string.match("alo ", "(%w+)$")
          r14 = string.match(" alo aalo allo", "%f[%S](.-%f[%s].-%f[%S])")
          r15 = string.match("abc\0\1\2c", "[\0-\2]+")
          r16 = string.match("abc\0\0\0", "%\0+")
          r17 = string.match("abc\0efg\0\1e\1g", "%b\0\1")
        ''');

        expect(_unwrapGlobal(bridge, 'r1'), equals("aaab"));
        expect(_unwrapGlobal(bridge, 'r2'), equals("aaa"));
        expect(_unwrapGlobal(bridge, 'r3'), equals("b"));
        expect(_unwrapGlobal(bridge, 'r4'), equals("aaab"));
        expect(_unwrapGlobal(bridge, 'r5'), equals("aaa"));
        expect(_unwrapGlobal(bridge, 'r6'), isNull);
        expect(_unwrapGlobal(bridge, 'r7'), equals("ab"));
        expect(_unwrapGlobal(bridge, 'r8'), equals("aa"));
        expect(_unwrapGlobal(bridge, 'r9'), equals("b"));
        expect(_unwrapGlobal(bridge, 'r10'), equals("xyz"));
        expect(_unwrapGlobal(bridge, 'r11'), equals(""));
        expect(_unwrapGlobal(bridge, 'r12'), equals(""));
        expect(_unwrapGlobal(bridge, 'r13'), isNull);
        expect(_unwrapGlobal(bridge, 'r14'), equals("alo "));
        expect(_unwrapGlobal(bridge, 'r15'), equals("\u0000\u0001\u0002"));
        expect(_unwrapGlobal(bridge, 'r16'), equals("\u0000\u0000\u0000"));
        expect(
          _unwrapGlobal(bridge, 'r17'),
          equals("\u0000efg\u0000\u0001e\u0001"),
        );
      });
    });
  });
}
