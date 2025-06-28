@Tags(['core'])
import 'package:test/test.dart';
import 'package:lualike/src/stack.dart';

void main() {
  group('Stack', () {
    test('push and pop operations', () {
      var stack = Stack<int>();
      stack.push(1);
      stack.push(2);
      stack.push(3);
      expect(stack.length, equals(3));
      expect(stack.pop(), equals(3));
      expect(stack.pop(), equals(2));
      expect(stack.pop(), equals(1));
      expect(stack.isEmpty, isTrue);
    });

    test('peek operation', () {
      var stack = Stack<String>();
      stack.push('a');
      stack.push('b');
      expect(stack.peek(), equals('b'));
      expect(stack.length, equals(2));
    });
  });
}
