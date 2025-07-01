@Tags(['core'])
import 'package:lualike/testing.dart';

void main() {
  group('CallStack', () {
    test('push, pop, and current frame', () {
      final callStack = CallStack();

      callStack.push("function1");
      expect(callStack.top?.functionName, equals("function1"));

      callStack.push("function2");
      expect(callStack.top?.functionName, equals("function2"));

      final popped = callStack.pop();
      expect(popped?.functionName, equals("function2"));

      expect(callStack.top?.functionName, equals("function1"));
    });
  });
}
