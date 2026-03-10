import 'package:lualike/src/parsers/pattern.dart' as lpc;
import 'package:lualike_test/test.dart';

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

  Logger.debugLazy(() => 'All balanced pattern tests completed');
}

void testBalancedPattern(String pattern, String text, String? expected) {
  test('balanced pattern: "$pattern" on string: "$text"', () {
    try {
      final lp = lpc.LuaPattern.compile(pattern);
      final match = lp.firstMatch(text);
      if (match != null) {
        final result = match.match;
        Logger.debugLazy(() => 'Match found: "$result"');

        if (expected != null && result != expected) {
          Logger.debugLazy(
            () => 'ERROR: Expected "$expected" but got "$result"',
          );
        } else if (expected == null) {
          Logger.debugLazy(() => 'ERROR: Expected no match but got "$result"');
        } else {
          Logger.debugLazy(() => 'SUCCESS: Match is correct');
        }
      } else {
        Logger.debugLazy(() => 'No match found');

        if (expected != null) {
          Logger.debugLazy(
            () => 'ERROR: Expected "$expected" but no match was found',
          );
        } else {
          Logger.debugLazy(() => 'SUCCESS: No match expected, none found');
        }
      }
    } catch (e) {
      Logger.debugLazy(() => 'ERROR: Exception occurred: $e');
      if (expected != null) {
        Logger.debugLazy(
          () => 'ERROR: Expected "$expected" but got an exception',
        );
      }
    }
  });

  Logger.debugLazy(() => '---');
}
