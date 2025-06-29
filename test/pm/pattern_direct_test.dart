@Tags(['pm'])
import 'package:lualike/src/pattern.dart';
import 'package:lualike/testing.dart';

void main() {
  // Test function to check pattern conversion and matching
  void testPattern(String luaPattern, String testString, {bool plain = false}) {
    test('Testing pattern: "$luaPattern" on string: "$testString"', () {
      try {
        // Convert Lua pattern to RegExp
        final regex = LuaPattern.toRegExp(luaPattern, plain: plain);
        Logger.debug('Converted to RegExp: ${regex.pattern}');

        // Test matching
        final match = regex.firstMatch(testString);
        if (match != null) {
          Logger.debug(
            'Match found: "${testString.substring(match.start, match.end)}"',
          );

          // Logger.debug capture groups if any
          for (var i = 1; i < match.groupCount + 1; i++) {
            Logger.debug('  Group $i: "${match.group(i)}"');
          }
        } else {
          Logger.debug('No match found');
        }
      } catch (e) {
        Logger.debug('Error: $e');
      }
    });

    Logger.debug('---');
  }

  // Test basic patterns
  testPattern('a', 'abc');
  testPattern('b', 'abc');
  testPattern('c', 'abc');
  testPattern('d', 'abc');

  // Test character classes
  testPattern('%a', 'abc');
  testPattern('%d', '123');
  testPattern('%s', ' \t\n');
  testPattern('[abc]', 'def');
  testPattern('[abc]', 'abc');
  testPattern('[^abc]', 'def');

  // Test quantifiers
  testPattern('a*', 'aaa');
  testPattern('a+', 'aaa');
  testPattern('a?', 'aaa');
  testPattern('a.-b', 'axyzb');

  // Test frontier patterns
  testPattern('%f[%a]a', '!abc');
  testPattern('%f[%s]a', 'a ');

  // Test balanced patterns
  testPattern('%b()', '(text)');
  testPattern('%b{}', '{text}');

  // Test capture groups
  testPattern('(%a+)', 'abc123');
  testPattern('(%a+)(%d+)', 'abc123');

  // Test complex patterns
  testPattern('%f[%S](.-%f[%s].-%f[%S])', ' word in the middle ');

  Logger.debug('All tests completed');
}
