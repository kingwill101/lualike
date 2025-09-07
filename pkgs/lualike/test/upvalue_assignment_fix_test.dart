import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('Upvalue Assignment Fix Tests', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('dumped function upvalue assignment', () async {
      const script = '''
        local a, b = 10, 20
        local f = function()
          a = a + b  -- Should update upvalue a to 30
          b = b - 5  -- Should update upvalue b to 15
        end
        
        local dumped = string.dump(f)
        local loaded = load(dumped, "", "b", nil)
        
        -- Set up upvalues
        debug.setupvalue(loaded, 1, 10)  -- a = 10
        debug.setupvalue(loaded, 2, 20)  -- b = 20
        
        -- Execute assignment
        loaded()
        
        -- Check results
        local name1, value1 = debug.getupvalue(loaded, 1)
        local name2, value2 = debug.getupvalue(loaded, 2)
        
        return {value1, value2}
      ''';

      final result = await lua.evaluate(script);
      final values = result.raw as Map;
      
      expect(values[1].raw, equals(30)); // a should be 30 (10 + 20)
      expect(values[2].raw, equals(15)); // b should be 15 (20 - 5)
    });

    test('calls.lua scenario reproduction', () async {
      const script = '''
        local a, b = 20, 30
        local x = load(string.dump(function(x)
            if x == "set" then
                a = 10 + b; b = b + 1
            else
                return a
            end
        end), "", "b", nil)
        
        -- Initial setup
        assert(x() == nil)
        assert(debug.setupvalue(x, 1, "hi") == "a")
        assert(x() == "hi")
        assert(debug.setupvalue(x, 2, 13) == "b")
        
        -- Test assignments
        x("set")
        assert(x() == 23)  -- Should be 23 (10 + 13)
        
        x("set") 
        assert(x() == 24)  -- Should be 24 (23 + 1)
        
        return true
      ''';

      final result = await lua.evaluate(script);
      expect(result.raw, equals(true));
    });

    test('original function assignments still work', () async {
      const script = '''
        local a = 10
        local f = function()
          a = 20
        end
        
        f()
        return a
      ''';

      final result = await lua.evaluate(script);
      expect(result.raw, equals(20));
    });

    test('no upvalue assignment when no upvalues exist', () async {
      const script = '''
        local f = function()
          nonexistent = 42  -- Should create global, not crash
        end
        
        f()
        return _G.nonexistent
      ''';

      final result = await lua.evaluate(script);
      expect(result.raw, equals(42));
    });

    test('complex upvalue assignment with multiple operations', () async {
      const script = '''
        local p, q = 100, 200
        local f = function()
          p = p + q  -- Should be 300
          q = q - 50 -- Should be 150
        end
        
        local dumped = string.dump(f)
        local loaded = load(dumped, "", "b", nil)
        
        -- Set up upvalues
        debug.setupvalue(loaded, 1, 100)  -- p = 100
        debug.setupvalue(loaded, 2, 200)  -- q = 200
        
        -- Execute assignment
        loaded()
        
        -- Check results
        local name1, value1 = debug.getupvalue(loaded, 1)
        local name2, value2 = debug.getupvalue(loaded, 2)
        
        return {value1, value2}
      ''';

      final result = await lua.evaluate(script);
      final values = result.raw as Map;
      
      expect(values[1].raw, equals(300)); // p should be 300 (100 + 200)
      expect(values[2].raw, equals(150)); // q should be 150 (200 - 50)
    });

    test('upvalue assignment with mixed local and upvalue variables', () async {
      const script = '''
        local upval = 10
        local f = function()
          local localvar = 5
          upval = upval + localvar  -- Should update upvalue to 15
          localvar = localvar * 2   -- Should update local to 10
          return {upval, localvar}
        end
        
        local dumped = string.dump(f)
        local loaded = load(dumped, "", "b", nil)
        
        -- Set up upvalue
        debug.setupvalue(loaded, 1, 10)  -- upval = 10
        
        -- Execute and get results
        local results = loaded()
        
        -- Check upvalue was updated
        local name, upvalValue = debug.getupvalue(loaded, 1)
        
        return {upvalValue, results[1], results[2]}
      ''';

      final result = await lua.evaluate(script);
      final values = result.raw as Map;
      
      expect(values[1].raw, equals(15)); // upval should be 15 (10 + 5)
      expect(values[2].raw, equals(15)); // returned upval should be 15
      expect(values[3].raw, equals(10)); // returned localvar should be 10 (5 * 2)
    });

    test('nested function upvalue assignments', () async {
      const script = '''
        local outer = 1
        local f = function()
          local inner = function()
            outer = outer * 2
          end
          
          local dumped = string.dump(inner)
          local loaded = load(dumped, "", "b", nil)
          
          -- Set up upvalue for inner function
          debug.setupvalue(loaded, 1, outer)
          
          -- Execute inner function
          loaded()
          
          -- Check upvalue was updated
          local name, value = debug.getupvalue(loaded, 1)
          return value
        end
        
        return f()
      ''';

      final result = await lua.evaluate(script);
      expect(result.raw, equals(2)); // outer should be 2 (1 * 2)
    });

    test('upvalue assignment with nil values', () async {
      const script = '''
        local a = nil
        local f = function()
          a = 42
        end
        
        local dumped = string.dump(f)
        local loaded = load(dumped, "", "b", nil)
        
        -- Set up upvalue as nil
        debug.setupvalue(loaded, 1, nil)
        
        -- Execute assignment
        loaded()
        
        -- Check upvalue was updated
        local name, value = debug.getupvalue(loaded, 1)
        
        return value
      ''';

      final result = await lua.evaluate(script);
      expect(result.raw, equals(42)); // a should be 42
    });

    test('upvalue assignment with string values', () async {
      const script = '''
        local str = "hello"
        local f = function()
          str = str .. " world"
        end
        
        local dumped = string.dump(f)
        local loaded = load(dumped, "", "b", nil)
        
        -- Set up upvalue
        debug.setupvalue(loaded, 1, "hello")
        
        -- Execute assignment
        loaded()
        
        -- Check upvalue was updated
        local name, value = debug.getupvalue(loaded, 1)
        
        return value
      ''';

      final result = await lua.evaluate(script);
      expect(result.raw.toString(), equals("hello world")); // str should be "hello world"
    });
  });
}
