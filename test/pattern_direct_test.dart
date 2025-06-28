import 'package:lualike/src/logger.dart';
import 'package:lualike/src/pattern.dart';

void main() {
  // Enable debug logging
  Logger.setEnabled(true);

  // Test function to check pattern conversion and matching
  void testPattern(String luaPattern, String testString, {bool plain = false}) {
    print('Testing pattern: "$luaPattern" on string: "$testString"');

    try {
      // Convert Lua pattern to RegExp
      final regex = LuaPattern.toRegExp(luaPattern, plain: plain);
      print('Converted to RegExp: ${regex.pattern}');

      // Test matching
      final match = regex.firstMatch(testString);
      if (match != null) {
        print('Match found: "${testString.substring(match.start, match.end)}"');

        // Print capture groups if any
        for (var i = 1; i < match.groupCount + 1; i++) {
          print('  Group $i: "${match.group(i)}"');
        }
      } else {
        print('No match found');
      }
    } catch (e) {
      print('Error: $e');
    }

    print('---');
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

  print('All tests completed');
}
