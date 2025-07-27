import 'package:lualike_test/test.dart';

void main() {
  group('Math Random Range Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test(
      'math.random should produce values close to 0 and 1',
      timeout: Timeout(Duration(seconds: 30)),
      () async {
        await bridge.execute('''
        math.randomseed(1007)  -- Use same seed as the original test
        
        local min_val = 1.0
        local max_val = 0.0
        local max_iterations = 100000
        local found_range = false
        
        for i = 1, max_iterations do
          local r = math.random()
          
          if r < min_val then
            min_val = r
          end
          if r > max_val then
            max_val = r
          end
          
          -- Check if we've found values close enough to the boundaries
          if min_val < 0.001 and max_val > 0.999 then
            found_range = true
            break
          end
        end
        
        _G.min_val = min_val
        _G.max_val = max_val
        _G.found_range = found_range
      ''');

        final minVal = (bridge.getGlobal('min_val') as Value).raw as double;
        final maxVal = (bridge.getGlobal('max_val') as Value).raw as double;
        final foundRange =
            (bridge.getGlobal('found_range') as Value).raw as bool;

        print('Final results:');
        print('Min value: $minVal');
        print('Max value: $maxVal');
        print('Found suitable range: $foundRange');

        // The test should pass if we get values close to the boundaries
        expect(
          minVal,
          lessThan(0.001),
          reason: 'Should generate values very close to 0, got $minVal',
        );
        expect(
          maxVal,
          greaterThan(0.999),
          reason: 'Should generate values very close to 1, got $maxVal',
        );
        expect(
          foundRange,
          isTrue,
          reason:
              'Should find values close to both 0 and 1 within 100k iterations',
        );
      },
    );

    test(
      'math.random distribution test simplified',
      timeout: Timeout(Duration(seconds: 10)),
      () async {
        await bridge.execute('''
        math.randomseed(1007)
        
        -- Simple test: count how many values are in lower vs upper half
        local rounds = 10000
        local lower_half = 0
        local upper_half = 0
        
        for i = 1, rounds do
          local t = math.random()
          if t < 0.5 then
            lower_half = lower_half + 1
          else
            upper_half = upper_half + 1
          end
        end
        
        _G.lower_half = lower_half
        _G.upper_half = upper_half
        _G.rounds = rounds
      ''');

        final lowerHalf = (bridge.getGlobal('lower_half') as Value).raw as int;
        final upperHalf = (bridge.getGlobal('upper_half') as Value).raw as int;
        final rounds = (bridge.getGlobal('rounds') as Value).raw as int;

        expect(
          lowerHalf + upperHalf,
          equals(rounds),
          reason: 'All values should be counted',
        );

        // Each half should get roughly 50% of the values
        final expected = rounds / 2;
        const tolerance = 0.05; // 5% tolerance

        final lowerRatio = lowerHalf / expected;
        final upperRatio = upperHalf / expected;

        expect(
          lowerRatio,
          greaterThan(1.0 - tolerance),
          reason: 'Lower half too sparse: $lowerHalf (expected ~$expected)',
        );
        expect(
          lowerRatio,
          lessThan(1.0 + tolerance),
          reason: 'Lower half too dense: $lowerHalf (expected ~$expected)',
        );
        expect(
          upperRatio,
          greaterThan(1.0 - tolerance),
          reason: 'Upper half too sparse: $upperHalf (expected ~$expected)',
        );
        expect(
          upperRatio,
          lessThan(1.0 + tolerance),
          reason: 'Upper half too dense: $upperHalf (expected ~$expected)',
        );

        print('Distribution test passed: lower=$lowerHalf, upper=$upperHalf');
      },
    );

    test(
      'math.random basic range test',
      timeout: Timeout(Duration(seconds: 10)),
      () async {
        await bridge.execute('''
        math.randomseed(42)
        
        local all_in_range = true
        local count = 1000
        
        for i = 1, count do
          local r = math.random()
          if r < 0.0 or r >= 1.0 then
            all_in_range = false
            break
          end
        end
        
        _G.all_in_range = all_in_range
        _G.count = count
      ''');

        final allInRange =
            (bridge.getGlobal('all_in_range') as Value).raw as bool;
        final count = (bridge.getGlobal('count') as Value).raw as int;

        expect(
          allInRange,
          isTrue,
          reason: 'All $count random values should be in range [0, 1)',
        );
      },
    );
  });
}
