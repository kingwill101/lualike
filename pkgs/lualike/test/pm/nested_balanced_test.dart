import 'package:lualike/src/parsers/pattern.dart' as lpc;
import 'package:lualike_test/test.dart';

void main() {
  Logger.debugLazy(
    () => '[${DateTime.now().toString().split('.').first}] Logging enabled',
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

  Logger.debugLazy(() => 'All nested balanced pattern tests completed');
}

void testNestedBalanced(String pattern, String text, String? expected) {
  test('Testing nested balanced pattern: "$pattern" on string: "$text"', () {
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
