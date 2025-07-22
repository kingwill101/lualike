import 'package:lualike/testing.dart';

void main() {
  group('LuaStringParser Error Messages', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    /// Helper function to test lexical errors like the Lua test suite
    Future<void> lexerror(String input, String expectedError) async {
      try {
        await lua.execute('return $input');
        fail('Expected parsing to fail for: $input');
      } catch (e) {
        final errorMsg = e.toString();
        expect(
          errorMsg,
          contains(expectedError),
          reason: 'Expected error "$expectedError" in message: $errorMsg',
        );
      }
    }

    group('Hexadecimal escape errors', () {
      test('hex escape at end with quote', () async {
        await lexerror('"abc\\x"', '\\x"');
      });

      test('hex escape at end without quote', () async {
        await lexerror('"abc\\x', '\\x');
      });

      test('hex escape at string start', () async {
        await lexerror('"\\x', '\\x');
      });

      test('hex escape with one invalid digit', () async {
        await lexerror('"\\x5"', '\\x5"');
      });

      test('hex escape with one digit no quote', () async {
        await lexerror('"\\x5', '\\x5');
      });

      test('hex escape with invalid first char', () async {
        await lexerror('"\\xr"', '\\xr');
      });

      test('hex escape with invalid first char no quote', () async {
        await lexerror('"\\xr', '\\xr');
      });

      test('hex escape with dot', () async {
        await lexerror('"\\x.', '\\x.');
      });

      test('hex escape with percent', () async {
        await lexerror('"\\x8%"', '\\x8%');
      });

      test('hex escape with invalid second char', () async {
        await lexerror('"\\xAG', '\\xAG');
      });
    });

    group('Invalid escape sequences', () {
      test('invalid escape g with quote', () async {
        await lexerror('"\\g"', '\\g');
      });

      test('invalid escape g without quote', () async {
        await lexerror('"\\g', '\\g');
      });

      test('invalid escape dot', () async {
        await lexerror('"\\."', '\\.');
      });
    });

    group('Decimal escape errors', () {
      test('decimal escape too large 999', () async {
        await lexerror('"\\999"', '\\999"');
      });

      test('decimal escape too large 300', () async {
        await lexerror('"xyz\\300"', '\\300"');
      });

      test('decimal escape too large 256', () async {
        await lexerror('"   \\256"', '\\256"');
      });
    });

    group('UTF-8 escape errors', () {
      test('UTF-8 value too large', () async {
        await lexerror('"abc\\u{100000000}"', 'abc\\u{100000000');
      });

      test('missing opening brace with invalid char', () async {
        await lexerror('"abc\\u11r"', 'abc\\u1');
      });

      test('missing opening brace at end', () async {
        await lexerror('"abc\\u"', 'abc\\u"');
      });

      test('missing closing brace with invalid char', () async {
        await lexerror('"abc\\u{11r"', 'abc\\u{11r');
      });

      test('missing closing brace with quote', () async {
        await lexerror('"abc\\u{11"', 'abc\\u{11"');
      });

      test('missing closing brace no quote', () async {
        await lexerror('"abc\\u{11', 'abc\\u{11');
      });

      test('no hex digits in braces', () async {
        await lexerror('"abc\\u{r"', 'abc\\u{r');
      });
    });

    group('Unfinished string errors', () {
      test('incomplete long bracket string level 0', () async {
        await lexerror('[=[alo]]', '<eof>');
      });

      test('incomplete long bracket string with equals', () async {
        await lexerror('[=[alo]=', '<eof>');
      });

      test('incomplete long bracket string no closing', () async {
        await lexerror('[=[alo]', '<eof>');
      });

      test('incomplete single quoted string', () async {
        await lexerror("'alo", '<eof>');
      });

      test('incomplete single quoted string with line continuation', () async {
        await lexerror("'alo \\z  \n\n", '<eof>');
      });

      test(
        'incomplete single quoted string with line continuation only',
        () async {
          await lexerror("'alo \\z", '<eof>');
        },
      );

      test('incomplete single quoted string with decimal escape', () async {
        await lexerror("'alo \\98", '<eof>');
      });

      test('incomplete double quoted string', () async {
        await lexerror('"alo', '<eof>');
      });

      test('incomplete double quoted string with escape', () async {
        await lexerror('"alo\\', '<eof>');
      });

      test('incomplete double quoted string with partial escape', () async {
        await lexerror('"alo\\n', '<eof>');
      });
    });

    group('String parsing success cases', () {
      test('valid hex escapes', () async {
        await lua.execute('local s = "\\x41\\x42"');
        // Should not throw
      });

      test('valid decimal escapes', () async {
        await lua.execute('local s = "\\65\\66"');
        // Should not throw
      });

      test('valid unicode escapes', () async {
        await lua.execute('local s = "\\u{41}\\u{42}"');
        // Should not throw
      });

      test('basic escape sequences', () async {
        await lua.execute('local s = "\\n\\t\\r\\\\\\""');
        // Should not throw
      });

      test('complete long bracket strings', () async {
        await lua.execute('local s = [[hello world]]');
        await lua.execute('local s = [=[nested]=]');
        await lua.execute('local s = [==[deep]==]');
        // Should not throw
      });

      test('complete quoted strings', () async {
        await lua.execute('local s = "hello world"');
        await lua.execute("local s = 'hello world'");
        // Should not throw
      });
    });
  });
}
