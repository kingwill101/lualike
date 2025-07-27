import 'package:lualike_test/test.dart';

void main() {
  group('Assignment with _ENV', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('local variable assignment when _ENV unchanged', () async {
      await bridge.execute('''
        local a = 10
        a = 20
        _G.result = a
      ''');

      final result = (bridge.getGlobal('result') as Value).raw;
      expect(result, equals(20));
    });

    test('local variable assignment when _ENV changed', () async {
      // This is the critical bug we fixed
      await bridge.execute('''
        local a = 10
        _ENV = setmetatable({}, {__index=_G})
        a = 20  -- Should update local 'a', not create _ENV.a
        _G.local_a = a
        _G.env_a_raw = rawget(_ENV, "a")  -- Check if "a" actually exists in _ENV table
      ''');

      final localA = (bridge.getGlobal('local_a') as Value).raw;
      final envARaw = (bridge.getGlobal('env_a_raw') as Value).raw;
      expect(localA, equals(20)); // local a should be 20
      expect(envARaw, equals(null)); // rawget(_ENV, "a") should be nil
    });

    test('global variable assignment when _ENV changed', () async {
      await bridge.execute('''
        X = 10
        _ENV = setmetatable({}, {__index=_G})
        X = 20  -- Should create _ENV.X, not update _G.X
        _G.env_x = X
        _G.global_x = _G.X
      ''');

      final envX = (bridge.getGlobal('env_x') as Value).raw;
      final globalX = (bridge.getGlobal('global_x') as Value).raw;
      expect(envX, equals(20)); // X (from _ENV) should be 20
      expect(globalX, equals(10)); // _G.X should remain 10
    });

    test('setmetatable assignment bug from events.lua', () async {
      // This reproduces the specific bug from events.lua
      await bridge.execute('''
        local a, t = {10, x="10"}, {}
        
        function f(table, key)
          return nil
        end
        
        t.__index = f
        
        -- This assignment was the bug - it should update local 'a'
        a = setmetatable({}, t)
        
        -- Check that 'a' is now the empty table with metatable
        -- If bug exists, a[1] would return 10 instead of nil
        _G.result_a1 = a[1]
        _G.result_tostring = tostring(a)
      ''');

      final resultA1 = (bridge.getGlobal('result_a1') as Value).raw;
      final resultTostring =
          (bridge.getGlobal('result_tostring') as Value).raw as String;
      expect(resultA1, equals(null)); // a[1] should be nil (empty table)
      expect(
        resultTostring,
        contains('table:'),
      ); // tostring(a) should contain "table:"
    });

    test(
      'complex scenario with multiple local and global assignments',
      () async {
        await bridge.execute('''
        local a, b = 1, 2
        c = 3
        
        _ENV = setmetatable({}, {__index=_G})
        
        a = 10  -- Update local a
        b = 20  -- Update local b  
        c = 30  -- Create _ENV.c
        d = 40  -- Create _ENV.d
        
        _G.local_a = a
        _G.local_b = b
        _G.env_c = c
        _G.env_d = d
        _G.env_a_raw = rawget(_ENV, "a")  -- Check if locals are NOT in _ENV
        _G.env_b_raw = rawget(_ENV, "b")
        _G.env_c_raw = rawget(_ENV, "c")  -- Check if globals ARE in _ENV
        _G.env_d_raw = rawget(_ENV, "d")
        _G.global_c = _G.c
      ''');

        final localA = (bridge.getGlobal('local_a') as Value).raw;
        final localB = (bridge.getGlobal('local_b') as Value).raw;
        final envC = (bridge.getGlobal('env_c') as Value).raw;
        final envD = (bridge.getGlobal('env_d') as Value).raw;
        final envARaw = (bridge.getGlobal('env_a_raw') as Value).raw;
        final envBRaw = (bridge.getGlobal('env_b_raw') as Value).raw;
        final envCRaw = (bridge.getGlobal('env_c_raw') as Value).raw;
        final envDRaw = (bridge.getGlobal('env_d_raw') as Value).raw;
        final globalC = (bridge.getGlobal('global_c') as Value).raw;

        expect(localA, equals(10)); // local a = 10
        expect(localB, equals(20)); // local b = 20
        expect(envC, equals(30)); // _ENV.c = 30
        expect(envD, equals(40)); // _ENV.d = 40
        expect(
          envARaw,
          equals(null),
        ); // rawget(_ENV, "a") = nil (local not in _ENV)
        expect(
          envBRaw,
          equals(null),
        ); // rawget(_ENV, "b") = nil (local not in _ENV)
        expect(envCRaw, equals(30)); // rawget(_ENV, "c") = 30 (global in _ENV)
        expect(envDRaw, equals(40)); // rawget(_ENV, "d") = 40 (global in _ENV)
        expect(globalC, equals(3)); // _G.c = 3 (original unchanged)
      },
    );

    test('nested scope with _ENV change', () async {
      await bridge.execute('''
        local a = 1
        
        do
          local b = 2
          _ENV = setmetatable({}, {__index=_G})
          
          a = 10  -- Should update outer local a
          b = 20  -- Should update inner local b
          c = 30  -- Should create _ENV.c
          
          _G.outer_a = a
          _G.inner_b = b
          _G.env_c = c
        end
      ''');

      final outerA = (bridge.getGlobal('outer_a') as Value).raw;
      final innerB = (bridge.getGlobal('inner_b') as Value).raw;
      final envC = (bridge.getGlobal('env_c') as Value).raw;

      expect(outerA, equals(10)); // outer local a = 10
      expect(innerB, equals(20)); // inner local b = 20
      expect(envC, equals(30)); // _ENV.c = 30
    });
  });
}
