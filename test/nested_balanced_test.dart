import 'package:lualike/src/pattern.dart';

void main() {
  print('[${DateTime.now().toString().split('.').first}] Logging enabled');

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

  print('All nested balanced pattern tests completed');
}

void testNestedBalanced(String pattern, String text, String? expected) {
  print('Testing nested balanced pattern: "$pattern" on string: "$text"');

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
