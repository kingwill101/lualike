@Tags(['core'])
library;

import 'package:lualike_test/test.dart';

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

    test('finds the newest recursive frame without copying the stack', () {
      final callStack = CallStack();
      final callable = Value(<Object?, Object?>{});
      final other = Value(<Object?, Object?>{});

      callStack.push('outer', callable: callable);
      final outer = callStack.top;
      callStack.push('other', callable: other);
      callStack.push('recursive', callable: callable);
      final recursive = callStack.top;

      expect(callStack.findLatestFrameForCallable(callable), same(recursive));
      expect(callStack.findLatestFrameForCallable(other), isNotNull);

      callStack.pop();
      expect(callStack.findLatestFrameForCallable(callable), same(outer));
    });
  });
}
