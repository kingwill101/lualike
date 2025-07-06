import 'package:lualike/testing.dart';

void main() {
  // Test cases for balanced patterns
  testBalancedPattern('%b()', '(simple text)', '(simple text)');
  testBalancedPattern('%b()', '(nested (text) here)', '(nested (text) here)');
  testBalancedPattern('%b()', 'before (text) after', '(text)');
  testBalancedPattern('%b()', '(unclosed', null);
  testBalancedPattern('%b()', 'no parentheses', null);

  // Test with different delimiters
  testBalancedPattern('%b{}', '{curly braces}', '{curly braces}');
  testBalancedPattern('%b[]', '[square brackets]', '[square brackets]');
  testBalancedPattern('%b<>', '<angle brackets>', '<angle brackets>');

  // Test with nested balanced patterns
  testBalancedPattern('%b()', '(outer (inner) text)', '(outer (inner) text)');
  testBalancedPattern('%b()', '((double nested))', '((double nested))');

  // Test with mixed delimiters
  testBalancedPattern(
    '%b()',
    '(mixed [brackets] here)',
    '(mixed [brackets] here)',
  );

  Logger.debug('All balanced pattern tests completed');
}

void testBalancedPattern(String pattern, String text, String? expected) {
  test('balanced pattern: "$pattern" on string: "$text"', () {
    try {
      final regexPattern = LuaPattern.toRegExp(pattern);
      Logger.debug('Converted to RegExp: ${regexPattern.pattern}');

      final match = regexPattern.firstMatch(text);
      if (match != null) {
        final result = match.group(0);
        Logger.debug('Match found: "$result"');

        if (expected != null && result != expected) {
          Logger.debug('ERROR: Expected "$expected" but got "$result"');
        } else if (expected == null) {
          Logger.debug('ERROR: Expected no match but got "$result"');
        } else {
          Logger.debug('SUCCESS: Match is correct');
        }
      } else {
        Logger.debug('No match found');

        if (expected != null) {
          Logger.debug('ERROR: Expected "$expected" but no match was found');
        } else {
          Logger.debug('SUCCESS: No match expected, none found');
        }
      }
    } catch (e) {
      Logger.debug('ERROR: Exception occurred: $e');
      if (expected != null) {
        Logger.debug('ERROR: Expected "$expected" but got an exception');
      }
    }
  });

  Logger.debug('---');
}
