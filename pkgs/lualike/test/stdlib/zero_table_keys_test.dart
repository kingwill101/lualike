import 'package:lualike_test/test.dart';

void main() {
  group('Zero Table Keys (Lua Interpreter)', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test(
      'negative zero and positive zero as table keys - direct assignment',
      () async {
        await bridge.execute('''
        local mz = -0.0
        local z = 0.0
        local t = {}
        t[mz] = 42
        result = t[z]
      ''');

        final result = bridge.getGlobal('result') as Value;
        expect(
          result.raw,
          equals(42),
          reason: 'Direct assignment: t[mz] = 42 should be accessible via t[z]',
        );
      },
    );

    test(
      'negative zero and positive zero as table keys - constructor syntax',
      () async {
        await bridge.execute('''
        local mz = -0.0
        local z = 0.0
        local t = {[mz] = 42}
        result = t[z]
      ''');

        final result = bridge.getGlobal('result') as Value;
        expect(
          result.raw,
          equals(42),
          reason:
              'Constructor syntax: {[mz] = 42} should be accessible via t[z]',
        );
      },
    );

    test(
      'positive zero and negative zero as table keys - constructor syntax',
      () async {
        await bridge.execute('''
        local mz = -0.0
        local z = 0.0
        local t = {[z] = 100}
        result = t[mz]
      ''');

        final result = bridge.getGlobal('result') as Value;
        expect(
          result.raw,
          equals(100),
          reason:
              'Constructor syntax: {[z] = 100} should be accessible via t[mz]',
        );
      },
    );

    test('zero variants equality in Lua', () async {
      await bridge.execute('''
        local mz = -0.0
        local z = 0.0
        result = mz == z
      ''');

      final result = bridge.getGlobal('result') as Value;
      expect(result.raw, equals(true), reason: '-0.0 should equal 0.0 in Lua');
    });

    test('math.lua specific assertion test', () async {
      await bridge.execute('''
        local mz = -0.0
        local z = 0.0
        local a = {[mz] = 1}
        result = a[z] == 1 and a[mz] == 1
      ''');

      final result = bridge.getGlobal('result') as Value;
      expect(
        result.raw,
        equals(true),
        reason: 'This is the exact assertion failing in math.lua',
      );
    });

    test('table key debugging - what keys exist', () async {
      await bridge.execute('''
        local mz = -0.0
        local z = 0.0
        local a = {[mz] = 1}
        
        num_keys = 0
        for k, v in pairs(a) do
          num_keys = num_keys + 1
          first_key = k
          first_value = v
        end
        
        access_via_mz = a[mz]
        access_via_z = a[z]
      ''');

      final numKeys = bridge.getGlobal('num_keys') as Value;
      expect(numKeys.raw, equals(1), reason: 'Should have exactly 1 key');
    });
  });
}
