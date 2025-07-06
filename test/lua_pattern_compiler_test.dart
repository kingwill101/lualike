import 'package:lualike/testing.dart';
import 'package:lualike/src/lua_pattern_compiler.dart' as lp;
import 'package:petitparser/petitparser.dart';

void main() {
  group('Character classes', () {
    test('%a letters', () {
      final p = lp.compileLuaPattern('%a');
      expect(p.accept('K'), isTrue);
      expect(p.accept('9'), isFalse);
    });

    test('%A complement', () {
      final p = lp.compileLuaPattern('%A');
      expect(p.accept('9'), isTrue);
      expect(p.accept('b'), isFalse);
    });

    test('%d digits', () {
      final p = lp.compileLuaPattern('%d+');
      expect(p.parse('123456'), isA<Success>());
      expect(p.accept('abc'), isFalse);
    });

    test('%s space', () {
      final p = lp.compileLuaPattern('%s');
      expect(p.accept(' '), isTrue);
      expect(p.accept('\n'), isTrue);
      expect(p.accept('a'), isFalse);
    });
  });

  group('Dot and literal escapes', () {
    test('dot matches any single char', () {
      final p = lp.compileLuaPattern('.');
      expect(p.accept('x'), isTrue);
      expect(p.accept(''), isFalse);
    });

    test('escaped magic char %%', () {
      final p = lp.compileLuaPattern('%%');
      expect(p.accept('%'), isTrue);
      expect(p.accept('%%'), isTrue);
    });

    test('escaped dot %.', () {
      final p = lp.compileLuaPattern('%.');
      expect(p.accept('.'), isTrue);
      expect(p.accept('a'), isFalse);
    });
  });

  group('Bracket sets', () {
    test('[abc]', () {
      final p = lp.compileLuaPattern('[abc]');
      expect(p.accept('b'), isTrue);
      expect(p.accept('d'), isFalse);
    });

    test('[^abc] complement', () {
      final p = lp.compileLuaPattern('[^abc]');
      expect(p.accept('x'), isTrue);
      expect(p.accept('a'), isFalse);
    });

    test('[0-9A-F]', () {
      final p = lp.compileLuaPattern('[0-9A-F]+');
      expect(p.parse('1A9F'), isA<Success>());
      expect(p.accept('G'), isFalse);
    });

    test('[%w_]', () {
      final p = lp.compileLuaPattern('[%w_]+');
      expect(p.parse('var_123'), isA<Success>());
      expect(p.accept('@'), isFalse);
    });
  });

  group('Quantifiers', () {
    test('* and +', () {
      final pStar = lp.compileLuaPattern('%d*');
      final pPlus = lp.compileLuaPattern('%d+');
      expect(pStar.accept(''), isTrue);
      expect(pPlus.accept(''), isFalse);
      expect(pPlus.parse('42'), isA<Success>());
    });

    test('?', () {
      final p = lp.compileLuaPattern('a?');
      expect(p.accept(''), isTrue);
      expect(p.accept('a'), isTrue);
      expect(p.accept('aa'), isTrue);
    });

    test('Greedy vs non-greedy * vs -', () {
      final greedy = lp.compileLuaPattern('a.*b');
      expect(greedy.parse('aXXbYYb'), isA<Failure>());

      final nongreedy = lp.compileLuaPattern('a.-b');
      expect(nongreedy.parse('aXXbYYb'), isA<Failure>());
    });
  });

  group('Anchors', () {
    test('^ and \$', () {
      final p = lp.compileLuaPattern('^%d+\$');
      expect(p.accept('123'), isTrue);
      expect(p.accept('123a'), isFalse);
    });
  });

  group('Captures (basic)', () {
    test('simple capture pair', () {
      final p = lp.compileLuaPattern('(%a+)%s+(%d+)');
      final r = p.parse('abc 123');
      expect(r, isA<Success>());
      expect((r as Success).value, 'abc 123');
    });
  });

  group('Balanced patterns', () {
    test('%b() simple', () {
      final p = lp.compileLuaPattern('%b()');
      expect(p.parse('(a)').value, '(a)');
      expect(p.parse('(a(b)c)d').value, '(a(b)c)');
      expect(p.parse('nope'), isA<Failure>());
    });

    test('nested %b{}', () {
      final p = lp.compileLuaPattern('%b{}');
      expect(p.parse('{x{y}z}').value, '{x{y}z}');
    });
  });

  group('Back references', () {
    test('unimplemented back reference', () {
      expect(
        () => lp.compileLuaPattern('%1'),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('Frontier patterns', () {
    test('word boundary at start', () {
      final p = lp.compileLuaPattern('%f[%a]%w+');
      expect(p.parse('hello').value, 'hello');
      expect(p.parse('1hello'), isA<Failure>());
    });

    test('boundary between space and word', () {
      final p = lp.compileLuaPattern('%f[%a]world');
      expect(p.parse('world').value, 'world');
      expect(p.parse(' world'), isA<Failure>());
    });
  });
}
