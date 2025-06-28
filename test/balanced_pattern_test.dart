import 'package:lualike/src/pattern.dart';

void main() {
  print('[${DateTime.now().toString().split('.').first}] Logging enabled');

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

  print('All balanced pattern tests completed');
}

void testBalancedPattern(String pattern, String text, String? expected) {
  print('Testing balanced pattern: "$pattern" on string: "$text"');

  try {
    final regexPattern = LuaPattern.toRegExp(pattern);
    print('Converted to RegExp: ${regexPattern.pattern}');

    final match = regexPattern.firstMatch(text);
    if (match != null) {
      final result = match.group(0);
      print('Match found: "$result"');

      if (expected != null && result != expected) {
        print('ERROR: Expected "$expected" but got "$result"');
      } else if (expected == null) {
        print('ERROR: Expected no match but got "$result"');
      } else {
        print('SUCCESS: Match is correct');
      }
    } else {
      print('No match found');

      if (expected != null) {
        print('ERROR: Expected "$expected" but no match was found');
      } else {
        print('SUCCESS: No match expected, none found');
      }
    }
  } catch (e) {
    print('ERROR: Exception occurred: $e');
    if (expected != null) {
      print('ERROR: Expected "$expected" but got an exception');
    }
  }

  print('---');
}
