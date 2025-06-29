@Tags(['interop'])
import 'package:lualike/testing.dart';

void main() {
  group('Function Return Arithmetic', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test(
      'arithmetic with function returns uses only the first return value',
      () async {
        await bridge.asserts.setup('''
        function f()
          return 10, 20, 30
        end
      ''');

        // Adding a number to a function call
        await bridge.asserts.runs('1 + f()', 11); // 1 + 10 = 11

        // Adding two function calls together
        await bridge.asserts.runs('f() + f()', 20); // 10 + 10 = 20

        // Adding function call to a number
        await bridge.asserts.runs('f() + 5', 15); // 10 + 5 = 15

        // Subtracting function calls
        await bridge.asserts.runs('f() - f()', 0); // 10 - 10 = 0

        // Multiplying function calls
        await bridge.asserts.runs('f() * f()', 100); // 10 * 10 = 100

        // Using function calls in complex expressions
        await bridge.asserts.runs('(f() + 5) * 2', 30); // (10 + 5) * 2 = 30

        // Using function calls with multiple operations
        await bridge.asserts.runs('f() + f() * 2', 30); // 10 + (10 * 2) = 30
      },
    );

    test('multi-return function in assignment captures all values', () async {
      await bridge.asserts.setup('''
        function f()
          return 10, 20, 30
        end

        local a, b, c = f()
      ''');

      bridge.asserts.global('a', 10);
      bridge.asserts.global('b', 20);
      bridge.asserts.global('c', 30);
    });

    test('parentheses limit return values to first only', () async {
      await bridge.asserts.setup('''
        function f()
          return 10, 20, 30
        end

        local a, b, c = (f())
      ''');

      bridge.asserts.global('a', 10);
      bridge.asserts.global('b', null);
      bridge.asserts.global('c', null);
    });

    test(
      'concatenation with function returns uses only the first return value',
      () async {
        await bridge.asserts.setup('''
        function f()
          return "hello", "world", "test"
        end
      ''');

        await bridge.asserts.runs('"prefix-" .. f()', "prefix-hello");
        await bridge.asserts.runs('f() .. "-suffix"', "hello-suffix");
        await bridge.asserts.runs('f() .. f()', "hellohello");
      },
    );
  });
}
