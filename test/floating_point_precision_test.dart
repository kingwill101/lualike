import 'package:lualike/testing.dart';

void main() {
  group('Floating Point Precision Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('modulo operations match Lua reference behavior', () async {
      final code = '''
        results = {}
        local test_cases = {
          {3.7, 1}, {5.5, 1}, {2.3, 1}, {7.9, 1}, {1.1, 1},
          {4.6, 1}, {8.2, 1}, {9.8, 1}, {0.7, 1}, {0.3, 1}, {0.9, 1}
        }
        
        for i, case in ipairs(test_cases) do
          local a, b = case[1], case[2]
          results[i] = a % b
        end
      ''';

      await bridge.runCode(code);
      final result = bridge.getGlobal('results');
      final map = result.raw as Map;
      final list = List.generate(map.length, (i) => map[i + 1]);

      // Expected values from reference Lua (with 17 decimal precision)
      final expected = [
        0.70000000000000018,
        0.50000000000000000,
        0.29999999999999982,
        0.90000000000000036,
        0.10000000000000009,
        0.59999999999999964,
        0.19999999999999929,
        0.80000000000000071,
        0.69999999999999996,
        0.29999999999999999,
        0.90000000000000002,
      ];

      expect(list.length, equals(expected.length));
      for (int i = 0; i < expected.length; i++) {
        expect(list[i].raw, closeTo(expected[i], 1e-16));
      }
    });

    test('multiplication and modulo operations', () async {
      final code = '''
        results = {}
        local base_values = {0.7, 0.3, 0.5}
        local idx = 1
        
        for _, t in ipairs(base_values) do
          for power = 0, 3 do
            local mult = 2^power
            results[idx] = (t * mult) % 1
            idx = idx + 1
          end
        end
      ''';

      await bridge.runCode(code);
      final result = bridge.getGlobal('results');
      final map = result.raw as Map;
      final list = List.generate(map.length, (i) => map[i + 1]);

      // Expected values from reference Lua
      final expected = [
        // 0.7 series
        0.69999999999999996,
        0.39999999999999991,
        0.79999999999999982,
        0.59999999999999964,
        // 0.3 series
        0.29999999999999999,
        0.59999999999999998,
        0.19999999999999996,
        0.39999999999999991,
        // 0.5 series
        0.50000000000000000,
        0.00000000000000000,
        0.00000000000000000,
        0.00000000000000000,
      ];

      expect(list.length, equals(expected.length));
      for (int i = 0; i < expected.length; i++) {
        expect(list[i].raw, closeTo(expected[i], 1e-16));
      }
    });

    test('bit test pattern from incd.lua', () async {
      final code = '''
        results = {}
        local test_values = {0.5, 0.25, 0.75}
        local idx = 1
        
        for _, t in ipairs(test_values) do
          for bit = 0, 2 do
            local result = (t * 2^bit) % 1
            local is_set = result >= 0.5
            results[idx] = {result, is_set}
            idx = idx + 1
          end
        end
      ''';

      await bridge.runCode(code);
      final result = bridge.getGlobal('results');
      final map = result.raw as Map;
      final list = List.generate(map.length, (i) => map[i + 1]);

      // Expected values from reference Lua
      final expectedResults = [
        0.50000000000000000, 0.00000000000000000, 0.00000000000000000,  // 0.5 series
        0.25000000000000000, 0.50000000000000000, 0.00000000000000000,  // 0.25 series
        0.75000000000000000, 0.50000000000000000, 0.00000000000000000,  // 0.75 series
      ];
      
      final expectedBits = [
        true, false, false,   // 0.5 series
        false, true, false,   // 0.25 series
        true, true, false,    // 0.75 series
      ];

      expect(list.length, equals(9));
      for (int i = 0; i < 9; i++) {
        final pairMap = list[i].raw as Map;
        final pair = [pairMap[1], pairMap[2]];
        expect(pair[0].raw, closeTo(expectedResults[i], 1e-16));
        expect(pair[1].raw, equals(expectedBits[i]));
      }
    });

    test('math.fmod matches modulo operator', () async {
      final code = '''
        results = {}
        local test_cases = {3.7, 5.5, 2.3, 7.9}
        
        for i, a in ipairs(test_cases) do
          local mod_result = a % 1
          local fmod_result = math.fmod(a, 1)
          results[i] = {mod_result, fmod_result, mod_result == fmod_result}
        end
      ''';

      await bridge.runCode(code);
      final result = bridge.getGlobal('results');
      final map = result.raw as Map;
      final list = List.generate(map.length, (i) => map[i + 1]);

      expect(list.length, equals(4));
      for (int i = 0; i < 4; i++) {
        final tripleMap = list[i].raw as Map;
        final triple = [tripleMap[1], tripleMap[2], tripleMap[3]];
        final modResult = triple[0].raw;
        final fmodResult = triple[1].raw;
        final areEqual = triple[2].raw;
        
        expect(modResult, closeTo(fmodResult, 1e-16));
        expect(areEqual, isTrue);
      }
    });
  });
}
