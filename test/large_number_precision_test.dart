import 'package:lualike/testing.dart';
import 'dart:math' as math;

void main() {
  group('Large Number Precision Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('2^53 multiplication and modulo precision', () async {
      final code = '''
        local mult = 2^53
        mult_value = mult
        
        -- Test some specific values
        test_values = {0.5, 0.25, 0.75, 0.1, 0.3547270967464816}
        results = {}
        
        for i, val in ipairs(test_values) do
          local product = val * mult
          local mod_result = product % 1
          local equals_zero = mod_result == 0
          results[i] = {
            original = val,
            product = product,
            mod_result = mod_result,
            equals_zero = equals_zero
          }
        end
      ''';

      await bridge.runCode(code);
      
      final multValue = bridge.getGlobal('mult_value');
      final results = bridge.getGlobal('results');
      
      print('mult = 2^53 = ${multValue.raw}');
      
      final resultsMap = results.raw as Map;
      for (int i = 1; i <= 5; i++) {
        final resultMap = resultsMap[i] as Map;
        final original = resultMap['original']?.raw;
        final product = resultMap['product']?.raw;
        final modResult = resultMap['mod_result']?.raw;
        final equalsZero = resultMap['equals_zero']?.raw;
        
        print('Value $original: product=$product, mod=$modResult, equals_zero=$equalsZero');
        
        // For most random values, (val * 2^53) % 1 should NOT equal 0
        // Only values that are exact multiples of 1/2^53 should give mod == 0
      }
      
      // Compare with Dart's native calculation
      final mult = math.pow(2, 53).toDouble();
      print('\nDart native calculations:');
      final testValues = [0.5, 0.25, 0.75, 0.1, 0.3547270967464816];
      for (final val in testValues) {
        final product = val * mult;
        final modResult = product % 1.0;
        final equalsZero = modResult == 0.0;
        print('Value $val: product=$product, mod=$modResult, equals_zero=$equalsZero');
      }
    });

    test('random number precision with 2^53 multiplication', () async {
      final code = '''
        math.randomseed(1007)
        local mult = 2^53
        
        results = {}
        local zero_count = 0
        local total_count = 10
        
        for i = 1, total_count do
          local r = math.random()
          local product = r * mult
          local mod_result = product % 1
          local equals_zero = mod_result == 0
          
          if equals_zero then
            zero_count = zero_count + 1
          end
          
          results[i] = {
            random_value = r,
            product = product,
            mod_result = mod_result,
            equals_zero = equals_zero
          }
        end
        
        zero_ratio = zero_count / total_count
      ''';

      await bridge.runCode(code);
      
      final results = bridge.getGlobal('results');
      final zeroRatio = bridge.getGlobal('zero_ratio');
      
      print('Zero ratio: ${zeroRatio.raw}');
      
      final resultsMap = results.raw as Map;
      for (int i = 1; i <= 10; i++) {
        final resultMap = resultsMap[i] as Map;
        final randomValue = resultMap['random_value']?.raw;
        final product = resultMap['product']?.raw;
        final modResult = resultMap['mod_result']?.raw;
        final equalsZero = resultMap['equals_zero']?.raw;
        
        print('Random $i: value=$randomValue, product=$product, mod=$modResult, equals_zero=$equalsZero');
      }
      
      // In a correct implementation, zero_ratio should be much less than 1.0
      // Most random values should NOT result in (value * 2^53) % 1 == 0
    });
  });
}
