@Tags(['pm'])
import 'package:lualike/testing.dart';

void main() {
  group('LuaPattern', () {
    group('Basic pattern functionality', () {
      test('Empty patterns', () {
        // Empty patterns are tricky
        final emptyPattern = LuaPattern.toRegExp('');
        expect(emptyPattern.hasMatch(''), isTrue);
        expect(emptyPattern.stringMatch(''), equals(''));

        // Empty pattern matches at start of any string
        expect(LuaPattern.toRegExp('').firstMatch('alo')?.start, equals(0));
      });

      test('Plain character matching', () {
        // Match single character 'a'
        expect(LuaPattern.toRegExp('a').pattern, equals('a'));

        // Escape special characters
        expect(LuaPattern.toRegExp('.').pattern, equals('\\.'));
        expect(LuaPattern.toRegExp('*').pattern, equals('\\*'));
        expect(LuaPattern.toRegExp('+').pattern, equals('\\+'));
        expect(LuaPattern.toRegExp('?').pattern, equals('\\?'));
        expect(LuaPattern.toRegExp('(').pattern, equals('\\('));
        expect(LuaPattern.toRegExp(')').pattern, equals('\\)'));
        expect(LuaPattern.toRegExp('[').pattern, equals('\\['));
        expect(LuaPattern.toRegExp(']').pattern, equals('\\]'));

        // Literal percent sign
        expect(LuaPattern.toRegExp('%').pattern, equals('%'));
      });

      test('Anchors', () {
        expect(LuaPattern.toRegExp('^hello').pattern, equals('^hello'));
        expect(LuaPattern.toRegExp('world\$').pattern, equals('world\$'));
        expect(LuaPattern.toRegExp('^hello\$').pattern, equals('^hello\$'));
      });

      test('Dot patterns', () {
        expect(LuaPattern.toRegExp('.').pattern, equals('\\.'));
        expect(LuaPattern.toRegExp('...').pattern, equals('...'));
        expect(LuaPattern.toRegExp('%..').pattern, equals('\\.'));
        expect(LuaPattern.toRegExp('%.%.%.').pattern, equals('\\.\\.\\.'));
      });
    });

    group('Character classes', () {
      test('Standard character classes', () {
        expect(LuaPattern.toRegExp('%a').pattern, equals('\\w'));
        expect(LuaPattern.toRegExp('%A').pattern, equals('[^A-Za-z]'));
        expect(LuaPattern.toRegExp('%c').pattern, equals('[\\x00-\\x1F\\x7F]'));
        expect(LuaPattern.toRegExp('%d').pattern, equals('\\d'));
        expect(LuaPattern.toRegExp('%D').pattern, equals('\\D'));
        expect(LuaPattern.toRegExp('%g').pattern, equals('[\\P{Z}]'));
        expect(LuaPattern.toRegExp('%l').pattern, equals('[a-z]'));
        expect(LuaPattern.toRegExp('%L').pattern, equals('[^a-z]'));
        expect(LuaPattern.toRegExp('%p').pattern, equals('[\\p{P}]'));
        expect(LuaPattern.toRegExp('%P').pattern, equals('[^\\p{P}]'));
        expect(LuaPattern.toRegExp('%s').pattern, equals('\\s'));
        expect(LuaPattern.toRegExp('%S').pattern, equals('\\S'));
        expect(LuaPattern.toRegExp('%u').pattern, equals('[A-Z]'));
        expect(LuaPattern.toRegExp('%U').pattern, equals('[^A-Z]'));
        expect(LuaPattern.toRegExp('%w').pattern, equals('\\w'));
        expect(LuaPattern.toRegExp('%W').pattern, equals('\\W'));
        expect(LuaPattern.toRegExp('%x').pattern, equals('[0-9A-Fa-f]'));
        expect(LuaPattern.toRegExp('%X').pattern, equals('[^0-9A-Fa-f]'));
        expect(LuaPattern.toRegExp('%z').pattern, equals('\\0'));
        expect(LuaPattern.toRegExp('%Z').pattern, equals('[^\\0]'));
      });

      test('Custom character classes', () {
        expect(LuaPattern.toRegExp('[abc]').pattern, equals('[abc]'));
        expect(LuaPattern.toRegExp('[^abc]').pattern, equals('[^abc]'));
        expect(LuaPattern.toRegExp('[a-z]').pattern, equals('[a-z]'));
        expect(LuaPattern.toRegExp('[^a-z]').pattern, equals('[^a-z]'));
        expect(LuaPattern.toRegExp('[%w_]').pattern, equals('[\\w_]'));
        expect(LuaPattern.toRegExp('[%d%s]').pattern, equals('[\\d\\s]'));
        expect(LuaPattern.toRegExp('[%a%d]').pattern, equals('[A-Za-z\\d]'));
        expect(LuaPattern.toRegExp('[a%-z]').pattern, equals('[a-z]'));
        expect(
          LuaPattern.toRegExp('%[%^%[%-a%]%-b]').pattern,
          equals('[\\[\\^\\[-a\\]-b]'),
        );
      });
    });

    group('Pattern quantifiers', () {
      test('Standard quantifiers', () {
        // * (0 or more)
        expect(LuaPattern.toRegExp('a*b').pattern, equals('a*b'));
        expect(LuaPattern.toRegExp('a*').pattern, equals('a*'));

        // + (1 or more)
        expect(LuaPattern.toRegExp('a+b').pattern, equals('a+b'));
        expect(LuaPattern.toRegExp('a+').pattern, equals('a+'));

        // - (0 or more, non-greedy)
        expect(LuaPattern.toRegExp('a-b').pattern, equals('a-b'));
        expect(LuaPattern.toRegExp('a-').pattern, equals('a-'));

        // ? (0 or 1)
        expect(LuaPattern.toRegExp('a?b').pattern, equals('a?b'));
        expect(LuaPattern.toRegExp('a?').pattern, equals('a?'));
      });

      test('Character class with quantifiers', () {
        expect(LuaPattern.toRegExp('%a*').pattern, equals('[A-Za-z]*'));
        expect(LuaPattern.toRegExp('%a+').pattern, equals('\\w+'));
        expect(LuaPattern.toRegExp('%a?').pattern, equals('[A-Za-z]?'));
        expect(LuaPattern.toRegExp('%d*').pattern, equals('\\d*'));
        expect(LuaPattern.toRegExp('%s?').pattern, equals('\\s?'));
      });
    });

    group('Capture patterns', () {
      test('Basic captures', () {
        expect(LuaPattern.toRegExp('(a)').pattern, equals('(a)'));
        expect(LuaPattern.toRegExp('(%d+)').pattern, equals('(\\d+)'));
        expect(
          LuaPattern.toRegExp('(%a+)(%d+)').pattern,
          equals('([A-Za-z]+)(\\d+)'),
        );
        expect(
          LuaPattern.toRegExp('((%d+)(%a+))').pattern,
          equals('((\\d+)([A-Za-z]+))'),
        );
        expect(LuaPattern.toRegExp('(a)(b)').pattern, equals('(a)(b)'));
      });

      test('Backreferences', () {
        expect(LuaPattern.toRegExp('%1').pattern, equals('\\1'));
        expect(LuaPattern.toRegExp('%2').pattern, equals('\\2'));
        expect(
          LuaPattern.toRegExp('(%a+)%1').pattern,
          equals('([A-Za-z]+)\\1'),
        );
      });
    });

    group('Special pattern sequences', () {
      test('Balanced patterns', () {
        expect(LuaPattern.toRegExp('%b()').pattern, equals('\\([^\\(\\)]*\\)'));
        expect(LuaPattern.toRegExp('%b{}').pattern, equals('\\{[^\\{\\}]*\\}'));
        expect(LuaPattern.toRegExp('%b[]').pattern, equals('\\[[^\\[\\]]*\\]'));

        // Invalid balanced patterns
        expect(
          () => LuaPattern.toRegExp('%b'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LuaPattern.toRegExp('%b('),
          throwsA(isA<FormatException>()),
        );
      });

      test('Frontier patterns', () {
        expect(
          LuaPattern.toRegExp('%f[%a]').pattern,
          equals('(?<![A-Za-z])(?=[A-Za-z])'),
        );
        expect(
          LuaPattern.toRegExp('%f[%d]').pattern,
          equals('(?<![d])(?=[d])'),
        );
        expect(
          LuaPattern.toRegExp('%f[%w_]').pattern,
          equals('(?<![w_])(?=[w_])'),
        );

        // Invalid frontier patterns
        expect(
          () => LuaPattern.toRegExp('%f'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LuaPattern.toRegExp('%f['),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LuaPattern.toRegExp('%f[]'),
          throwsA(isA<FormatException>()),
        );
      });

      test('Escaping percent with percent', () {
        expect(LuaPattern.toRegExp('%%').pattern, equals('%'));
        expect(LuaPattern.toRegExp('%%%a').pattern, equals('%\\w'));
      });
    });

    group('Complex patterns from Lua test suite', () {
      test('Pattern matching examples', () {
        // Examples from the Lua test suite
        expect(LuaPattern.toRegExp('a*').pattern, equals('a*'));
        expect(LuaPattern.toRegExp('a+').pattern, equals('a+'));
        expect(LuaPattern.toRegExp('a?').pattern, equals('a?'));
        expect(LuaPattern.toRegExp('a-').pattern, equals('a-'));

        expect(LuaPattern.toRegExp('ab*a').pattern, equals('ab*a'));
        expect(LuaPattern.toRegExp('ab+a').pattern, equals('ab+a'));
        expect(LuaPattern.toRegExp('ab-a').pattern, equals('ab-a'));
        expect(LuaPattern.toRegExp('ab?a').pattern, equals('ab?a'));

        expect(LuaPattern.toRegExp('a\$a').pattern, equals('a\\\$a'));
        expect(LuaPattern.toRegExp('a%\$a').pattern, equals('a\\\$a'));

        expect(LuaPattern.toRegExp('b.*b').pattern, equals('b.*b'));
        expect(LuaPattern.toRegExp('b.-b').pattern, equals('b.-b'));
      });

      test('Character class examples', () {
        expect(LuaPattern.toRegExp('[^]]+').pattern, equals('[^\\]]+'));
        expect(LuaPattern.toRegExp('[^%]]+').pattern, equals('[^\\]]+'));
        expect(LuaPattern.toRegExp('%S%S*').pattern, equals('\\S\\S*'));
        expect(LuaPattern.toRegExp('%S*').pattern, equals('\\S*'));
      });

      test('Real-world pattern examples', () {
        // Email pattern
        expect(
          LuaPattern.toRegExp('^[%w%.%-]+@[%w%.%-]+%.%w+\$').pattern,
          equals('^[\\w.-]+@[\\w.-]+\\.\\w+\$'),
        );

        // URL pattern
        expect(
          LuaPattern.toRegExp('^https?://[%w%.%-]+%.%w+(/[%w%.%-]*)*').pattern,
          equals('^https?://[\\w.-]+\\.\\w+(/[\\w.-]*)*'),
        );

        // Assignment pattern
        expect(
          LuaPattern.toRegExp('^%s*(%w+)%s*=%s*(%d+)').pattern,
          equals('^\\s*(\\w+)\\s*=\\s*(\\d+)'),
        );

        // Date pattern
        expect(
          LuaPattern.toRegExp('^%d%d%d%d%-%d%d%-%d%d').pattern,
          equals('^\\d\\d\\d\\d-\\d\\d-\\d\\d'),
        );
      });

      test('Balanced parentheses pattern', () {
        // This tests for patterns that check balanced characters
        final pattern = LuaPattern.toRegExp('%b()');
        expect(pattern.hasMatch('(simple)'), isTrue);
        expect(pattern.hasMatch('(nested(two)levels)'), isTrue);
        expect(pattern.hasMatch('(unbalanced'), isFalse);

        // isbalanced from Lua test suite - checking if parentheses are balanced
        final isBalanced = RegExp(
          LuaPattern.toRegExp(
            '%b()',
          ).pattern.replaceAll(r'\(', '\\(').replaceAll(r'\)', '\\)'),
        );
        expect(isBalanced.hasMatch('(9 ((8))(0) 7)'), isTrue);
      });
    });

    group('Error handling', () {
      test('Malformed patterns', () {
        // Unfinished capture
        expect(
          () => LuaPattern.toRegExp('(.'),
          throwsA(isA<FormatException>()),
        );

        // Invalid pattern capture
        expect(
          () => LuaPattern.toRegExp('.)'),
          throwsA(isA<FormatException>()),
        );

        // Unclosed brackets
        expect(
          () => LuaPattern.toRegExp('[a'),
          throwsA(isA<FormatException>()),
        );
        expect(() => LuaPattern.toRegExp('['), throwsA(isA<FormatException>()));
        expect(
          () => LuaPattern.toRegExp('[^]'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LuaPattern.toRegExp('[a%'),
          throwsA(isA<FormatException>()),
        );

        // Invalid balanced/frontier patterns
        expect(
          () => LuaPattern.toRegExp('%b'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LuaPattern.toRegExp('%ba'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => LuaPattern.toRegExp('%f'),
          throwsA(isA<FormatException>()),
        );

        // Missing character after %
        expect(() => LuaPattern.toRegExp('%'), throwsA(isA<FormatException>()));

        // Invalid magic character
        expect(
          () => LuaPattern.toRegExp('%k'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  }, skip: 'legacy pattern translation');
}
