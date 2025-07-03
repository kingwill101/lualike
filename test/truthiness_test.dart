import 'package:lualike/testing.dart';

void main() {
  group('Lua Truthiness Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('not operator follows Lua truthiness rules', () async {
      final code = '''
        results = {}
        
        -- Test various values with 'not' operator
        results[1] = not true     -- should be false
        results[2] = not false    -- should be true
        results[3] = not nil      -- should be true
        results[4] = not 0        -- should be false (0 is truthy in Lua)
        results[5] = not 1        -- should be false
        results[6] = not 0.001    -- should be false
        results[7] = not ""       -- should be false (empty string is truthy in Lua)
        results[8] = not "hello"  -- should be false
        results[9] = not {}       -- should be false (empty table is truthy in Lua)
        
        -- Test the specific case that was causing the incd.lua bug
        limit = 0.001
        results[10] = not limit   -- should be false
      ''';

      await bridge.runCode(code);
      final results = bridge.getGlobal('results');
      
      final map = results.raw as Map;
      final list = List.generate(map.length, (i) => map[i + 1]);

      // Expected results according to Lua truthiness rules
      final expected = [
        false, // not true
        true,  // not false  
        true,  // not nil
        false, // not 0
        false, // not 1
        false, // not 0.001
        false, // not ""
        false, // not "hello"
        false, // not {}
        false, // not limit (0.001)
      ];

      expect(list.length, equals(expected.length));
      for (int i = 0; i < expected.length; i++) {
        expect(list[i].raw, equals(expected[i]), 
               reason: 'Test case ${i+1} failed');
      }
    });

    test('and/or operators use correct truthiness', () async {
      final code = '''
        results = {}
        
        -- Test 'and' operator
        results[1] = 0.001 and "yes"      -- should be "yes" (0.001 is truthy)
        results[2] = false and "yes"      -- should be false
        results[3] = nil and "yes"        -- should be nil
        
        -- Test 'or' operator  
        results[4] = 0.001 or "no"        -- should be 0.001 (first truthy value)
        results[5] = false or "yes"       -- should be "yes"
        results[6] = nil or "yes"         -- should be "yes"
      ''';

      await bridge.runCode(code);
      final results = bridge.getGlobal('results');
      
      final map = results.raw as Map;
      final list = List.generate(map.length, (i) => map[i + 1]);

      expect(list[0].raw, equals("yes"));     // 0.001 and "yes"
      expect(list[1].raw, equals(false));     // false and "yes"
      expect(list[2].raw, equals(null));      // nil and "yes"
      expect(list[3].raw, equals(0.001));     // 0.001 or "no"
      expect(list[4].raw, equals("yes"));     // false or "yes"
      expect(list[5].raw, equals("yes"));     // nil or "yes"
    });

    test('eq function from incd.lua now works correctly', () async {
      final code = '''
        local function eq(a, b, limit)
          if not limit then
            limit = 1E-5
          end
          return a == b or math.abs(a-b) <= limit
        end
        
        -- Test the specific case that was failing
        up = 0.9999553292479069
        low = 0.000032781725642694326
        
        result1 = eq(up, 1, 0.001)
        result2 = eq(low, 0, 0.001)
        combined = result1 and result2
      ''';

      await bridge.runCode(code);
      
      final result1 = bridge.getGlobal('result1');
      final result2 = bridge.getGlobal('result2');  
      final combined = bridge.getGlobal('combined');

      expect(result1.raw, isTrue);
      expect(result2.raw, isTrue);
      expect(combined.raw, isTrue);
    });
  });
}
