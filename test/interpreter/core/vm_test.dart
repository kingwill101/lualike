@Tags(['core'])
import 'package:lualike/testing.dart';

void main() {
  late Interpreter vm;

  setUp(() {
    vm = Interpreter();
  });

  group('VM basic operations', () {
    test('simple arithmetic', () async {
      try {
        await vm.evaluate('return 1 + 2 * 3 - 1 +(19/2)');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(15.5));
      }
    });

    test('variable assignment and access', () async {
      await vm.evaluate('x = 42');
      try {
        await vm.evaluate('return x');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(42));
      }
    });

    test('local variables', () async {
      try {
        await vm.evaluate('''
          local a = 10
          local b = 20
          return a + b
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(30));
      }
    });
  });

  group('Function handling', () {
    test('function definition and call', () async {
      await vm.evaluate('''
        function add(a, b)
          return a + b
        end
      ''');
      try {
        await vm.evaluate('return add(5, 3)');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(8));
      }
    });

    test('local function', () async {
      try {
        await vm.evaluate('''
          local function multiply(a, b)
            return a * b
          end
          return multiply(4, 5)
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(20));
      }
    });
  });

  group('load() and dofile()', () {
    test('load from string', () async {
      try {
        await vm.evaluate('''
          local f = load("return 1 + 1")
          return f()
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(2));
      }
    });

    test('virtual file loading', () async {
      vm.fileManager.registerVirtualFile('test.lua', 'return 42');
      try {
        await vm.evaluate('return dofile("test.lua")');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(42));
      }
    });
  });

  group('Table operations', () {
    test('table creation and access', () async {
      try {
        await vm.evaluate('''
          local t = {x = 10, y = 20}
          return t.x + t.y
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(30));
      }
    });

    test('table array style access', () async {
      try {
        await vm.evaluate('''
          local t = {1, 2, 3, 4, 5}
          return t[3]
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(3));
      }
    });
  });

  group('Metatables', () {
    test('basic metamethods', () async {
      try {
        await vm.evaluate('''
          local t1 = {value = 5}
          local t2 = {value = 3}
          local mt = {
            __add = function(a, b)
              return {value = a.value + b.value}
            end
          }
          setmetatable(t1, mt)
          setmetatable(t2, mt)
          result = t1 + t2
          return result.value
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(8));
      } catch (e, s) {
        print(e);
        print(s);
        rethrow;
      }
    });
  });

  group('require and modules', () {
    test('basic module loading', () async {
      vm.fileManager.registerVirtualFile('mymodule.lua', '''
        local M = {}
        function M.double(x)
          return x * 2
        end
        return M
      ''');

      try {
        await vm.evaluate('''
          local m = require("mymodule")
          return m.double(21)
        ''');
      } on ReturnException catch (e) {
        expect((e.value as Value).raw, equals(42));
      }
    });

    test('module caching', () async {
      vm.fileManager.registerVirtualFile('counter.lua', '''
        local count = 0
        return function()
          count = count + 1
          return count
        end
      ''');

      await vm.evaluate('''
        local counter1 = require("counter")
        local counter2 = require("counter")
        result1 = counter1()
        result2 = counter1()
        result3 = counter2()
      ''');

      // Should share state because require caches modules
      var result1 = vm.globals.get('result1') as Value;
      expect(result1.raw, equals(1));
      var result2 = vm.globals.get('result2') as Value;
      expect(result2.raw, equals(2));
      var result3 = vm.globals.get('result3') as Value;
      expect(result3.raw, equals(3));
    });
  });

  group('Standard library', () {
    test('math functions', () async {
      try {
        await vm.evaluate('''
          return math.abs(-42), math.sin(math.pi/2), math.max(1,2,3)
        ''');
      } on ReturnException catch (e) {
        var values = (e.value as Value).unwrap();
        expect(values[0], equals(42));
        expect(values[1], closeTo(1, 1e-10));
        expect(values[2], equals(3));
      }
    });

    test('string functions', () async {
      try {
        await vm.evaluate('''
          return string.upper("hello"), string.len("world"), string.sub("hello", 2, 4)
        ''');
      } on ReturnException catch (e) {
        var values = (e.value as Value).unwrap();
        expect(values[0], equals("HELLO"));
        expect(values[1], equals(5));
        expect(values[2], equals("ell"));
      }
    });

    test('table functions', () async {
      try {
        await vm.evaluate('''
          local t = {1, 2, 3}
          table.insert(t, 4)
          table.remove(t, 2)
          return t[1], t[2], t[3]
        ''');
      } on ReturnException catch (e) {
        var values = (e.value as Value).unwrap();
        expect(values[0], equals(1));
        expect(values[1], equals(3));
        expect(values[2], equals(4));
      }
    });
  });

  group('scoping', () {
    test('closure variable scoping', () async {
      await vm.evaluate('''
    local count = 0

    local increment = function()
      count = count + 1
      return count
    end

    function reset()
    print("reset called")
    print("-----count before reset: " .. count)
      count = 0
      print("-----count after reset: " .. count)
    end

    result1 = increment()
    result2 = increment()
    result3 = increment()
  ''');

      var result1 = vm.globals.get('result1') as Value;
      var result2 = vm.globals.get('result2') as Value;
      var result3 = vm.globals.get('result3') as Value;

      expect(result1.raw, equals(1));
      expect(result2.raw, equals(2));
      expect(result3.raw, equals(3));

      // Test that reset function can access and modify the same count
      await vm.evaluate('reset()');
      await vm.evaluate('result4 = increment()');

      var result4 = vm.globals.get('result4') as Value;
      expect(
        result4.raw,
        equals(1),
        reason: 'After reset, count should start from 1 again',
      );
    });

    // And let's add another test case for nested closures
    test('nested closure scoping', () async {
      await vm.evaluate('''
    local function counter()
      local count = 0
      return function()
        count = count + 1
        return count
      end
    end

    local c1 = counter()
    local c2 = counter()

    r1 = c1()
    r2 = c1()
    r3 = c2()
    r4 = c2()
  ''');

      var r1 = vm.globals.get('r1') as Value;
      var r2 = vm.globals.get('r2') as Value;
      var r3 = vm.globals.get('r3') as Value;
      var r4 = vm.globals.get('r4') as Value;

      expect(r1.raw, equals(1), reason: 'First counter first call');
      expect(r2.raw, equals(2), reason: 'First counter second call');
      expect(r3.raw, equals(1), reason: 'Second counter first call');
      expect(r4.raw, equals(2), reason: 'Second counter second call');
    });
  });
}
