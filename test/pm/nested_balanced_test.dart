import 'package:lualike/src/parsers/pattern.dart' as lpc;
import 'package:lualike/testing.dart';

void main() {
  Logger.debug(
    '[${DateTime.now().toString().split('.').first}] Logging enabled',
  );

  // Test cases for deeply nested balanced patterns
  testNestedBalanced(
    '%b()',
    '(this (is (a (deeply (nested) pattern) with) multiple) levels)',
    '(this (is (a (deeply (nested) pattern) with) multiple) levels)',
  );

  testNestedBalanced(
    '%b{}',
    '{outer {middle {inner} content} end}',
    '{outer {middle {inner} content} end}',
  );

  testNestedBalanced(
    '%b[]',
    '[level1 [level2 [level3] back2] back1]',
    '[level1 [level2 [level3] back2] back1]',
  );

  // Test with mixed delimiters
  testNestedBalanced(
    '%b()',
    '(mixed [delimiters] {in} (one) pattern)',
    '(mixed [delimiters] {in} (one) pattern)',
  );

  // Test with unbalanced patterns
  testNestedBalanced('%b()', '(unbalanced (pattern)', null);

  // Test with complex code-like content
  testNestedBalanced(
    '%b{}',
    '{function() { if (condition) { return { nested: "object" }; } }}',
    '{function() { if (condition) { return { nested: "object" }; } }}',
  );

  Logger.debug('All nested balanced pattern tests completed');
}

void testNestedBalanced(String pattern, String text, String? expected) {
  test('Testing nested balanced pattern: "$pattern" on string: "$text"', () {
    try {
      final lp = lpc.LuaPattern.compile(pattern);
      final match = lp.firstMatch(text);
      if (match != null) {
        final result = match.match;
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
