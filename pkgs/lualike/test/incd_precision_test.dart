import 'package:lualike_test/test.dart';

void main() {
  group('INCD Algorithm Precision Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('floatbits calculation matches reference Lua', () async {
      final code = '''
        local floatbits = 24
        local p = 2.0^floatbits
        while p < p + 1.0 do
          p = p * 2.0
          floatbits = floatbits + 1
        end
        result = floatbits
      ''';

      await bridge.execute(code);
      final result = bridge.getGlobal('result');

      expect(result.raw, equals(53));
    });

    test('extra bits check with specific values from reference Lua', () async {
      final code = '''
        math.randomseed(1007)  -- Same seed as reference
        local floatbits = 53
        local mult = 2^floatbits
        
        results = {}
        local count = 0
        
        -- Test first 50 random values to see success rate
        for i = 1, 50 do
          local r = math.random()
          local extraBitsCheck = (r * mult) % 1 == 0
          results[i] = {
            value = r,
            mult_result = r * mult,
            mod_result = (r * mult) % 1,
            passes_check = extraBitsCheck
          }
          if extraBitsCheck then
            count = count + 1
          end
        end
        
        success_rate = count / 50
      ''';

      await bridge.execute(code);
      final results = bridge.getGlobal('results');
      final successRate = bridge.getGlobal('success_rate');

      print('Success rate: ${successRate.raw}');

      final resultsMap = results.raw as Map;
      for (int i = 1; i <= 10; i++) {
        // Show first 10 results
        final resultMap = (resultsMap[i] as Map);
        final value = resultMap['value']?.raw;
        final multResult = resultMap['mult_result']?.raw;
        final modResult = resultMap['mod_result']?.raw;
        final passesCheck = resultMap['passes_check']?.raw;

        print(
          'Test $i: value=$value, mult_result=$multResult, mod_result=$modResult, passes=$passesCheck',
        );
      }

      // The success rate should be > 0 for the algorithm to work
      expect(successRate.raw, greaterThan(0.0));
    });

    test('bit pattern test with values that pass extra bits check', () async {
      final code = '''
        math.randomseed(1007)
        local floatbits = 53
        local mult = 2^floatbits
        
        -- Find values that pass the extra bits check
        local validValues = {}
        local attempts = 0
        
        while #validValues < 5 and attempts < 1000 do
          attempts = attempts + 1
          local r = math.random()
          if (r * mult) % 1 == 0 then
            table.insert(validValues, r)
          end
        end
        
        results = {}
        for i, t in ipairs(validValues) do
          local bitResults = {}
          for bit = 0, 10 do  -- Test first 11 bits
            local bitTest = (t * 2^bit) % 1
            local isSet = bitTest >= 0.5
            bitResults[bit] = {
              mult_result = t * 2^bit,
              mod_result = bitTest,
              is_set = isSet
            }
          end
          results[i] = {
            value = t,
            bits = bitResults
          }
        end
        
        valid_count = #validValues
        total_attempts = attempts
      ''';

      await bridge.execute(code);
      final results = bridge.getGlobal('results');
      final validCount = bridge.getGlobal('valid_count');
      final totalAttempts = bridge.getGlobal('total_attempts');

      print(
        'Found ${validCount.raw} valid values in ${totalAttempts.raw} attempts',
      );

      final resultsMap = results.raw as Map;
      if ((validCount.raw as num) > 0) {
        // Show the bit pattern for the first valid value
        final firstResult = resultsMap[1] as Map;
        final value = firstResult['value']?.raw;
        final bitsMap = firstResult['bits'] as Map;

        print('First valid value: $value');

        for (int bit = 0; bit <= 5; bit++) {
          final bitData = bitsMap[bit] as Map;
          final multResult = bitData['mult_result']?.raw;
          final modResult = bitData['mod_result']?.raw;
          final isSet = bitData['is_set']?.raw;

          print('  Bit $bit: mult=$multResult, mod=$modResult, set=$isSet');
        }
      }

      expect(validCount.raw, greaterThan(0));
    });
  });
}
