@Tags(['interop'])
import 'package:lualike/testing.dart';

void main() {
  group('Function Call Chaining', () {
    test('basic function call chaining (a()())', () async {
      final bridge = LuaLike();

      // Define a function that returns another function
      await bridge.runCode('''
        function createGreeter(prefix)
          return function(name)
            return prefix .. ", " .. name
          end
        end

        local result = createGreeter("Hello")("World")
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Hello, World"));
    });

    test('multiple chained function calls (a()()())', () async {
      final bridge = LuaLike();

      // Define functions that return other functions
      await bridge.runCode('''
        function level1()
          return function()
            return function()
              return "3 levels deep"
            end
          end
        end

        local result = level1()()()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("3 levels deep"));
    });

    test('function chaining with arguments', () async {
      final bridge = LuaLike();

      // Define more complex nested functions
      await bridge.runCode('''
        function adder(a)
          return function(b)
            return a + b
          end
        end

        local result = adder(5)(10)
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals(15));
    });

    test('function chaining in assignment', () async {
      final bridge = LuaLike();

      // Test function chaining in assignment
      await bridge.runCode('''
        function makeCounter(start)
          return function()
            start = start + 1
            return start
          end
        end

        counter = makeCounter(0)
        first = counter()
        second = counter()
      ''');

      var first = bridge.getGlobal('first');
      var second = bridge.getGlobal('second');

      expect((first as Value).raw, equals(1));
      expect((second as Value).raw, equals(2));
    });

    test('complex function call chain with table access', () async {
      final bridge = LuaLike();

      // Define functions that return tables with functions
      await bridge.runCode('''
        function makeLib()
          local lib = {}
          
          lib.create = function(name)
            local obj = {}
            obj.name = name
            obj.greet = function()
              return "Hello from " .. obj.name
            end
            return obj
          end
          
          return lib
        end

        local result = makeLib().create("MyLib").greet()
      ''');

      var result = bridge.getGlobal('result');
      expect((result as Value).raw, equals("Hello from MyLib"));
    });
  });
}
