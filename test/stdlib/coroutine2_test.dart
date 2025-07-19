import 'package:lualike/testing.dart';

void main() {
  group('Coroutine Tests', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
      Logger.setEnabled(true); // Re-enable debug logs
    });

    test('Basic coroutine creation and execution', () async {
      await bridge.execute('''
      co = coroutine.create(function(a, b)
        return a + b
      end)
      result = {coroutine.resume(co, 2, 3)}
      ''');

      final result = fromLuaValue(bridge.getGlobal('result') as Value);

      expect(result, isNotNull);
      expect(result[0], equals(true)); // Success flag
      expect(result[1], equals(5)); // Return value (2+3)
    });

    test('Coroutine with yield', () async {
      await bridge.execute('''
      co = coroutine.create(function(x)
        local y = coroutine.yield(x + 1)
        return x + y
      end)

      first = {coroutine.resume(co, 10)}
      second = {coroutine.resume(co, 20)}
      ''');

      final first = fromLuaValue(bridge.getGlobal('first'));
      final second = fromLuaValue(bridge.getGlobal('second'));

      expect(first[0], equals(true)); // First element is the success flag
      expect(
        first[1],
        equals(11),
      ); // Second element is the yielded value (10+1)

      expect(second[0], equals(true)); // First element is the success flag
      expect(
        second[1],
        equals(30),
      ); // Second element is the return value (10+20)
    });

    test('Coroutine status', () async {
      await bridge.execute('''
      co = coroutine.create(function()
        coroutine.yield()
      end)

      s1 = coroutine.status(co)
      coroutine.resume(co)
      s2 = coroutine.status(co)
      coroutine.resume(co)
      s3 = coroutine.status(co)
      ''');

      expect(bridge.getGlobal('s1').raw, equals('suspended'));
      expect(bridge.getGlobal('s2').raw, equals('suspended'));
      expect(bridge.getGlobal('s3').raw, equals('dead'));
    });

    test('Main thread status and operations', () async {
      await bridge.execute('''
      local main, ismain = coroutine.running()
      mainthread_status = coroutine.status(main)
      can_resume_main = pcall(coroutine.resume, main)
      is_main_yieldable = coroutine.isyieldable(main)
      can_yield = pcall(coroutine.yield)
      ''');

      expect(fromLuaValue(bridge.getGlobal('ismain')), isTrue);
      expect(bridge.getGlobal('mainthread_status').raw, equals('running'));
      expect(fromLuaValue(bridge.getGlobal('can_resume_main')), isTrue);
      expect(
        fromLuaValue(bridge.getGlobal('is_main_yieldable')),
        isFalse,
      ); // Main thread can't yield
      expect(
        fromLuaValue(bridge.getGlobal('can_yield')),
        isFalse,
      ); // Can't yield from main thread
    });

    test('Coroutine wrap', () async {
      await bridge.execute('''
      f = coroutine.wrap(function(a, b)
        return a + b
      end)

      result = f(5, 7)
      ''');

      expect(bridge.getGlobal('result').raw, equals(12)); // 5+7
    });

    test('Coroutine wrap with yield', () async {
      await bridge.execute('''
      co = coroutine.wrap(function()
        local x = 0
        for i = 1, 3 do
          x = x + i
          x = coroutine.yield(x)
        end
        return x
      end)

      r1 = co()
      r2 = co(10)
      r3 = co(20)
      r4 = co(30)
      ''');

      expect(bridge.getGlobal('r1').raw, equals(1));
      expect(bridge.getGlobal('r2').raw, equals(12)); // 2 + 10
      expect(bridge.getGlobal('r3').raw, equals(23)); // 3 + 20
      expect(bridge.getGlobal('r4').raw, equals(30));
    });

    test('Multiple yield/resume arguments', () async {
      await bridge.execute('''
      _G.x = nil
      f = coroutine.create(function (a, ...)
        local x, y = coroutine.running()
        assert(x == f and y == false)
        -- next call should fail but not corrupt coroutine
        local resume_ok = coroutine.resume(f)
        assert(resume_ok == false) -- can't resume running coroutine
        assert(coroutine.status(f) == "running")
        local arg = {...}
        for i=1,#arg do
          _G.x = {coroutine.yield(table.unpack(arg[i]))}
        end
        return table.unpack(a)
      end)

      -- Test yielding with multiple arguments
      s,a,b,c,d = coroutine.resume(f, {1,2,3}, {}, {1}, {'a', 'b', 'c'})
      first_yield_ok = s
      first_yield_a = a
      second_s, second_a, second_b, second_c, second_d = coroutine.resume(f)
      x_after_second = _G.x
      third_s, third_a, third_b, third_c, third_d = coroutine.resume(f, 1, 2, 3)
      x_after_third = _G.x
      fourth_s, fourth_a, fourth_b, fourth_c, fourth_d = coroutine.resume(f, "xuxu")
      x_after_fourth = _G.x
      fifth_s, fifth_a, fifth_b, fifth_c, fifth_d = coroutine.resume(f, "xuxu")
      final_status = coroutine.status(f)
      ''');

      print(
        'first_yield_ok: \\${fromLuaValue(bridge.getGlobal('first_yield_ok'))}',
      );
      print('first_yield_a: \\${bridge.getGlobal('first_yield_a')}');
      print('second_s: \\${fromLuaValue(bridge.getGlobal('second_s'))}');
      print('second_a: \\${bridge.getGlobal('second_a')}');
      print('second_b: \\${bridge.getGlobal('second_b')}');
      print('x_after_second: \\${bridge.getGlobal('x_after_second')}');
      print('third_s: \\${fromLuaValue(bridge.getGlobal('third_s'))}');
      print('third_a: \\${bridge.getGlobal('third_a')}');
      print('third_b: \\${bridge.getGlobal('third_b')}');
      print('third_c: \\${bridge.getGlobal('third_c')}');
      print('third_d: \\${bridge.getGlobal('third_d')}');
      print(
        'x_after_third: \\${fromLuaValue(bridge.getGlobal('x_after_third'))}',
      );
      print('fourth_s: \\${fromLuaValue(bridge.getGlobal('fourth_s'))}');
      print('fourth_a: \\${bridge.getGlobal('fourth_a')}');
      print('fourth_b: \\${bridge.getGlobal('fourth_b')}');
      print('fourth_c: \\${bridge.getGlobal('fourth_c')}');
      print('fourth_d: \\${bridge.getGlobal('fourth_d')}');
      print(
        'x_after_fourth: \\${fromLuaValue(bridge.getGlobal('x_after_fourth'))}',
      );
      print('fifth_s: \\${fromLuaValue(bridge.getGlobal('fifth_s'))}');
      print('final_status: \\${bridge.getGlobal('final_status')}');

      expect(fromLuaValue(bridge.getGlobal('first_yield_ok')), isTrue);
      expect(bridge.getGlobal('first_yield_a').raw, isNull);

      expect(fromLuaValue(bridge.getGlobal('second_s')), isTrue);
      expect(bridge.getGlobal('second_a').raw, equals(1));
      expect(bridge.getGlobal('second_b').raw, isNull);
      expect(
        bridge.getGlobal('x_after_second'),
        equals(Value({})),
      ); // Expect an empty Lua table (Value wrapping empty Map)

      expect(fromLuaValue(bridge.getGlobal('third_s')), isTrue);
      expect(bridge.getGlobal('third_a').raw, equals('a'));
      expect(bridge.getGlobal('third_b').raw, equals('b'));
      expect(bridge.getGlobal('third_c').raw, equals('c'));
      expect(bridge.getGlobal('third_d').raw, isNull);
      expect(
        fromLuaValue(bridge.getGlobal('x_after_third')),
        equals([1, 2, 3]),
      );

      expect(fromLuaValue(bridge.getGlobal('fourth_s')), isTrue);
      expect(bridge.getGlobal('fourth_a').raw, equals(1));
      expect(bridge.getGlobal('fourth_b').raw, equals(2));
      expect(bridge.getGlobal('fourth_c').raw, equals(3));
      expect(bridge.getGlobal('fourth_d').raw, isNull);
      expect(
        fromLuaValue(bridge.getGlobal('x_after_fourth')),
        equals(['xuxu']),
      );

      expect(
        fromLuaValue(bridge.getGlobal('fifth_s')),
        isFalse,
      ); // Can't resume dead coroutine
      expect(bridge.getGlobal('final_status').raw, equals('dead'));
    });

    test('Yields in tail calls', () async {
      await bridge.execute('''
      print('--- STARTING LUALIKE TEST ---')
      local function foo (i)
        print('foo called with:', i)
        print('_G.x before yield in foo:', _G.x)
        local result = coroutine.yield(i)
        print('foo resuming with:', result)
        print('_G.x after yield in foo:', _G.x)
        print('result == _G.x:', result == _G.x)
        return result
      end

      local f = coroutine.wrap(function ()
        print('coroutine function started')
        print('_G.x in coroutine start:', _G.x)
        for i=1,3 do
          print('loop iteration:', i)
          print('_G.x in loop before foo call:', _G.x)
          print('calling foo with:', i)
          local result = foo(i)
          print('foo returned:', result)
          print('_G.x after foo call:', _G.x)
          print('result == _G.x in coroutine:', result == _G.x)
        end
        print('coroutine returning a')
        return 'a'
      end)

      print('coroutine created')
      for i=1,3 do
        print('main loop iteration:', i)
        print('setting _G.x =', i)
        _G.x = i
        print('_G.x after setting in main:', _G.x)
        print('calling f with:', i)
        local result = f(i)
        print('f returned:', result)
        print('_G.x after f call in main:', _G.x)
        print('assert f returned equals i:', result == i)
      end

      print('setting _G.x = xuxu')
      _G.x = 'xuxu'
      print('calling f with: xuxu')
      local result = f('xuxu')
      print('f returned:', result)
      print('--- TEST COMPLETE ---')
      ''');

      expect(bridge.getGlobal('result').raw, equals('a'));
    });

    test('Recursive coroutine example', () async {
      await bridge.execute('''
      local function pf (n, i)
        coroutine.yield(n)
        pf(n*i, i+1)
      end

      f = coroutine.wrap(pf)
      local s=1
      results = {}
      for i=1,5 do -- Limit to first 5 values to avoid infinite loop
        table.insert(results, f(1, 1))
        s = s*i
      end
      ''');

      final results = fromLuaValue(bridge.getGlobal('results'));
      expect(
        results,
        equals([1, 1, 2, 6, 24]),
      ); // Each result is the previous multiplied by the index
    });

    test('Coroutine close', () async {
      await bridge.execute('''
      -- ok to close a dead coroutine
      co = coroutine.create(print)
      assert(coroutine.resume(co, "testing 'coroutine.close'"))
      assert(coroutine.status(co) == "dead")
      close_result, close_msg = coroutine.close(co)

      -- also ok to close it again
      second_close_ok, second_close_msg = coroutine.close(co)

      -- cannot close the running coroutine
      main_close_ok, main_close_error = pcall(coroutine.close, coroutine.running())

      -- cannot close a "normal" coroutine
      normal_close_error = nil
      ;(coroutine.wrap(function ()
        local ok, msg = pcall(coroutine.close, coroutine.running())
        normal_close_error = msg
      end))()
      ''');

      expect(fromLuaValue(bridge.getGlobal('close_result')), isTrue);
      expect(bridge.getGlobal('close_msg').raw, isNull);

      expect(fromLuaValue(bridge.getGlobal('second_close_ok')), isTrue);
      expect(bridge.getGlobal('second_close_msg').raw, isNull);

      expect(fromLuaValue(bridge.getGlobal('main_close_ok')), isFalse);
      expect(
        bridge.getGlobal('main_close_error').raw.toString(),
        contains('Cannot close running coroutine'),
      );

      expect(
        bridge.getGlobal('normal_close_error').raw.toString(),
        contains('Cannot close running coroutine'),
      );
    });

    test('Coroutine errors', () async {
      await bridge.execute('''
      function foo ()
        error("test error")
      end

      function goo() foo() end
      x = coroutine.wrap(goo)
      pcall_result, pcall_error = pcall(x)

      x = coroutine.create(goo)
      resume1_a, resume1_b = coroutine.resume(x)
      resume2_a, resume2_b = coroutine.resume(x)
      ''');

      expect(fromLuaValue(bridge.getGlobal('pcall_result')), isFalse);
      expect(
        bridge.getGlobal('pcall_error').raw.toString(),
        contains('test error'),
      );

      expect(fromLuaValue(bridge.getGlobal('resume1_a')), isFalse);
      expect(
        bridge.getGlobal('resume1_b').raw.toString(),
        contains('test error'),
      );

      expect(fromLuaValue(bridge.getGlobal('resume2_a')), isFalse);
      expect(bridge.getGlobal('resume2_b').raw.toString(), contains('dead'));
    });

    test('Attempt to resume itself', () async {
      await bridge.execute('''
      local function co_func (current_co)
        assert(coroutine.running() == current_co)
        assert(coroutine.resume(current_co) == false)
        coroutine.yield(10, 20)
        assert(coroutine.resume(current_co) == false)
        coroutine.yield(23)
        return 10
      end

      local co = coroutine.create(co_func)
      resume1_a, resume1_b, resume1_c = coroutine.resume(co, co)
      resume2_a, resume2_b = coroutine.resume(co, co)
      resume3_a, resume3_b = coroutine.resume(co, co)
      resume4_ok = coroutine.resume(co, co)
      resume5_ok = coroutine.resume(co, co)
      ''');

      expect(fromLuaValue(bridge.getGlobal('resume1_a')), isTrue);
      expect(bridge.getGlobal('resume1_b').raw, equals(10));
      expect(bridge.getGlobal('resume1_c').raw, equals(20));

      expect(fromLuaValue(bridge.getGlobal('resume2_a')), isTrue);
      expect(bridge.getGlobal('resume2_b').raw, equals(23));

      expect(fromLuaValue(bridge.getGlobal('resume3_a')), isTrue);
      expect(bridge.getGlobal('resume3_b').raw, equals(10));

      expect(fromLuaValue(bridge.getGlobal('resume4_ok')), isFalse);
      expect(fromLuaValue(bridge.getGlobal('resume5_ok')), isFalse);
    });

    test('isyieldable behaves correctly', () async {
      await bridge.execute('''
      main_co = coroutine.running()

      -- Create a coroutine to test isyieldable
      co = coroutine.create(function()
        local is_yieldable = coroutine.isyieldable()
        coroutine.yield(is_yieldable)
        return coroutine.isyieldable()
      end)

      main_yieldable = coroutine.isyieldable()
      resume1_a, resume1_b = coroutine.resume(co)
      resume2_a, resume2_b = coroutine.resume(co)

      -- Test isyieldable with arguments
      co_yieldable = coroutine.isyieldable(co)
      main_yieldable_arg = coroutine.isyieldable(main_co)
      ''');

      expect(
        fromLuaValue(bridge.getGlobal('main_yieldable')),
        isFalse,
      ); // Main can't yield
      expect(fromLuaValue(bridge.getGlobal('resume1_a')), isTrue);
      expect(
        fromLuaValue(bridge.getGlobal('resume1_b')),
        isTrue,
      ); // Coroutine can yield

      expect(fromLuaValue(bridge.getGlobal('resume2_a')), isTrue);
      expect(
        fromLuaValue(bridge.getGlobal('resume2_b')),
        isTrue,
      ); // Still yieldable after resumed

      expect(
        fromLuaValue(bridge.getGlobal('co_yieldable')),
        isTrue,
      ); // Created coroutine is yieldable
      expect(
        fromLuaValue(bridge.getGlobal('main_yieldable_arg')),
        isFalse,
      ); // Main thread is not yieldable
    });

    test('Yields inside metamethods', () async {
      await bridge.execute('''
      -- Create a metatable with metamethods that yield
      local mt = {
        __eq = function(a,b) local _, op = coroutine.yield(nil, "eq"); return a.x == b.x end,
        __lt = function(a,b) local _, op = coroutine.yield(nil, "lt"); return a.x < b.x end,
        __le = function(a,b) local _, op = coroutine.yield(nil, "le"); return a.x <= b.x end,
        __gt = function(a,b) local _, op = coroutine.yield(nil, "gt"); return a.x > b.x end,
        __add = function(a,b) local _, op = coroutine.yield(nil, "add"); return a.x + b.x end,
        __sub = function(a,b) local _, op = coroutine.yield(nil, "sub"); return a.x - b.x end,
        __mul = function(a,b) local _, op = coroutine.yield(nil, "mul"); return a.x * b.x end,
        __div = function(a,b) local _, op = coroutine.yield(nil, "div"); return a.x / b.x end,
        __idiv = function(a,b) local _, op = coroutine.yield(nil, "idiv"); return a.x // b.x end,
        __pow = function(a,b) local _, op = coroutine.yield(nil, "pow"); return a.x ^ b.x end,
        __mod = function(a,b) local _, op = coroutine.yield(nil, "mod"); return a.x % b.x end
      }

      local function new (x)
        return setmetatable({x = x, k = {}}, mt)
      end

      local a = new(10)
      local b = new(12)

      local function run (f, t)
        local i = 1
        local c = coroutine.wrap(f)
        while true do
          local res, stat = c()
          if res then return res, t end
          assert(stat == t[i])
          i = i + 1
        end
      end

      lt_result = run(function () if (a<b) then return "<" else return ">=" end end, {"lt"})
      gt_result = run(function () if (a>b) then return ">" else return "<=" end end, {"gt"})
      add_result = run(function () return a + b end, {"add"})
      mul_result = run(function () return a * b end, {"mul"})
      ''');

      expect(bridge.getGlobal('lt_result').raw, equals('<')); // a < b is true
      expect(bridge.getGlobal('gt_result').raw, equals('<=')); // a > b is false
      expect(bridge.getGlobal('add_result').raw, equals(22)); // 10 + 12
      expect(bridge.getGlobal('mul_result').raw, equals(120)); // 10 * 12
    });

    test('Yields inside for iterators', () async {
      await bridge.execute('''
      local f = function (s, i)
        if i%2 == 0 then coroutine.yield(nil, "for") end
        if i < s then return i + 1 end
      end

      -- Add the run function definition here
      local function run (f, t)
        local i = 1
        local c = coroutine.wrap(f)
        while true do
          local res, stat = c()
          if res then return res, t end
          assert(stat == t[i])
          i = i + 1
        end
      end

      local result = run(function ()
        local s = 0
        for i in f, 4, 0 do s = s + i end
        return s
      end, {"for", "for", "for"})
      ''');

      expect(bridge.getGlobal('result').raw, equals(10)); // 1+2+3+4 = 10
    });

    test('Yielding across C boundaries', () async {
      await bridge.execute('''
      local co = coroutine.wrap(function()
      local ok, err = pcall(table.sort, {1,2,3}, coroutine.yield)
      assert(not ok) -- Check that pcall failed
      assert(err:match("attempt to yield")) -- Check error message
      coroutine.yield(20) -- This yield should work
      return 30 -- Finally return 30
      end)

      first_result = co()
      second_result = co()
      ''');

      expect(bridge.getGlobal('first_result').raw, equals(20));
      expect(bridge.getGlobal('second_result').raw, equals(30));
    });

    test('Coroutine chain and table.sort interactions', () async {
      await bridge.execute('''
        local f = function (a, b)
          a = coroutine.yield(a)  -- First yield returns 10
          error({a + b})          -- Then errors with {100 + 20}
        end

        local function g(x)
          return x[1]*2  -- Should receive {120} and return 120*2=240
        end

        co = coroutine.wrap(function ()
          coroutine.yield(xpcall(f, g, 10, 20))
        end)

        first_result = co()      -- Gets 10
        pcall_result, error_msg = co(100)  -- Resumes with 100, gets error
      ''');

      // First yield returns 10
      expect(bridge.getGlobal('first_result').raw, equals(10));

      // pcall_result is false because error was raised
      expect(fromLuaValue(bridge.getGlobal('pcall_result')), isFalse);

      // error_msg should be 240 (error handler g received {120} and returned 120*2)
      expect(bridge.getGlobal('error_msg').raw, equals(240));
    });

    test('To-be-closed variables in coroutines', () async {
      await bridge.execute('''
      -- Simulate Lua's to-be-closed variables
      function func2close (f)
        return setmetatable({}, {__close = f})
      end

      local X = true
      co = coroutine.create(function ()
        local closed = false
        local closed_with_error = nil
        local x = func2close(function (self, err)
          closed = true
          closed_with_error = err
          X = false
        end)
        X = true
        coroutine.yield()
      end)
      coroutine.resume(co)

      initial_X = X
      close_result, close_msg = coroutine.close(co)
      final_X = X
      co_status = coroutine.status(co)
      ''');

      expect(fromLuaValue(bridge.getGlobal('initial_X')), isTrue);
      expect(fromLuaValue(bridge.getGlobal('close_result')), isTrue);
      expect(bridge.getGlobal('close_msg').raw, isNull);
      expect(fromLuaValue(bridge.getGlobal('final_X')), isFalse);
      expect(bridge.getGlobal('co_status').raw, equals('dead'));
    });

    test('Error closing a coroutine', () async {
      await bridge.execute('''
      x = 0
      co = coroutine.create(function()
        local y = func2close(function (self, err)
          assert(err == 111)
          x = 200
          error(200)
        end)
        local z = func2close(function (self, err)
          assert(err == nil)
          error(111)
        end)
        coroutine.yield()
      end)
      coroutine.resume(co)

      initial_x = x
      close_ok, close_msg = coroutine.close(co)
      final_x = x
      co_status = coroutine.status(co)

      -- After closing, no more errors
      second_close_ok, second_close_msg = coroutine.close(co)
      ''');

      expect(bridge.getGlobal('initial_x').raw, equals(0));
      expect(fromLuaValue(bridge.getGlobal('close_ok')), isFalse);
      expect(bridge.getGlobal('close_msg').raw.toString(), contains('200'));
      expect(bridge.getGlobal('final_x').raw, equals(200));
      expect(bridge.getGlobal('co_status').raw, equals('dead'));
      expect(fromLuaValue(bridge.getGlobal('second_close_ok')), isTrue);
      expect(bridge.getGlobal('second_close_msg').raw, isNull);
    });

    test('Cannot close running coroutine with close-variables', () async {
      await bridge.execute('''
      -- Tests the case where a coroutine tries to close itself during a close operation
      error_message = nil
      pcall(function()
        local co
        co = coroutine.create(
          function()
            local x = func2close(function()
              coroutine.close(co) -- try to close it again
            end)
            coroutine.yield(20)
          end)
        local st, msg = coroutine.resume(co)
        assert(st and msg == 20)
        local ok, err = pcall(coroutine.close, co)
        error_message = err
      end)
      ''');

      expect(
        bridge.getGlobal('error_message').raw.toString(),
        contains('running coroutine'),
      );
    });

    test('Yielding with pcalls inside coroutines', () async {
      await bridge.execute('''
      local co = coroutine.wrap(function ()
        return pcall(pcall, pcall, pcall, pcall, pcall, pcall, pcall, error, "hi")
      end)

      result = {co()}
      ''');

      final result = fromLuaValue(bridge.getGlobal('result'));
      expect(result.length, greaterThanOrEqualTo(10));
      expect(
        result[9],
        isTrue,
      ); // First element of nested pcall results is true
      expect(result[10], equals('hi')); // Last error message is the original
    });

    test('Cannot close the main thread', () async {
      await bridge.execute('''
      local main = coroutine.running()
      close_main_ok, close_main_err = pcall(coroutine.close, main)
      ''');

      expect(fromLuaValue(bridge.getGlobal('close_main_ok')), isFalse);
      expect(
        bridge.getGlobal('close_main_err').raw.toString(),
        contains('running'),
      );
    });

    test('Coroutine with non-function', () async {
      await bridge.execute('''
      create_ok, create_err = pcall(coroutine.create, 123)
      ''');

      expect(fromLuaValue(bridge.getGlobal('create_ok')), isFalse);
      expect(
        bridge.getGlobal('create_err').raw.toString(),
        contains('function'),
      );
    });

    test('Handling edge cases with coroutine status', () async {
      await bridge.execute('''
      -- Test invalid arguments
      status_nil_ok, status_nil_err = pcall(coroutine.status, nil)
      status_num_ok, status_num_err = pcall(coroutine.status, 123)
      status_str_ok, status_str_err = pcall(coroutine.status, "not a coroutine")

      -- Check if thread is correctly handled by status
      co = coroutine.create(function() end)
      valid_status = coroutine.status(co)
      ''');

      expect(fromLuaValue(bridge.getGlobal('status_nil_ok')), isFalse);
      expect(fromLuaValue(bridge.getGlobal('status_num_ok')), isFalse);
      expect(fromLuaValue(bridge.getGlobal('status_str_ok')), isFalse);
      expect(bridge.getGlobal('valid_status').raw, equals('suspended'));
    });

    test('Coroutine normal status and wrapping behavior', () async {
      await bridge.execute('''
      local co1, co2
      co1 = coroutine.create(function () return co2() end)
      co2 = coroutine.wrap(function ()
        assert(coroutine.status(co1) == 'normal')
        assert(not coroutine.resume(co1))
        coroutine.yield(3)
      end)

      a, b = coroutine.resume(co1)
      co1_status = coroutine.status(co1)
      ''');

      expect(fromLuaValue(bridge.getGlobal('a')), isTrue);
      expect(bridge.getGlobal('b').raw, equals(3));
      expect(bridge.getGlobal('co1_status').raw, equals('dead'));

      // Check co1 status again after it has finished
      final co1StatusAfterCo2Call = await bridge.execute('''
        return coroutine.status(co1)
      ''');
      print('[TEST DEBUG] Value returned by runCode: $co1StatusAfterCo2Call');
      print('[TEST DEBUG] Type: ${co1StatusAfterCo2Call?.runtimeType}');
      if (co1StatusAfterCo2Call is List) {
        print(
          '[TEST DEBUG] First element type: ${co1StatusAfterCo2Call.isNotEmpty ? co1StatusAfterCo2Call.first?.runtimeType : 'N/A'}',
        );
        print(
          '[TEST DEBUG] First element raw: ${co1StatusAfterCo2Call.isNotEmpty ? (co1StatusAfterCo2Call.first as Value?)?.raw : 'N/A'}',
        );
      }
      expect(
        ((co1StatusAfterCo2Call as List<Object?>?)?.first as Value?)?.raw,
        'dead', // co1 finished, so it should be dead
      );
    });

    test(
      'Infinite recursion of coroutines is prevented',
      () async {
        await bridge.execute('''
      recursion_error_detected = false
      pcall(function()
        local a = function(a) coroutine.wrap(a)(a) end
        a(a)
      end, function(err)
        recursion_error_detected = true
        return err
      end)
      ''');

        expect(
          fromLuaValue(bridge.getGlobal('recursion_error_detected')),
          isTrue,
        );
      },
      skip: 'TODO: Fix infinite recursion of coroutines',
    );

    test('Table unpacking and yield assignment consistency', () async {
      await bridge.execute('''
        _G.results = {}
        function test_unpack(arg)
          print('LUA ENTER test_unpack', arg)
          local yielded = {coroutine.yield(table.unpack(arg))}
          print('LUA BEFORE INSERT:', _G.results, _G.results[1], _G.results[2], _G.results[3])
          print('LUA YIELDED:', yielded[1], yielded[2], yielded[3])
          table.insert(_G.results, yielded)
          print('LUA AFTER INSERT:', _G.results, _G.results[1], _G.results[2], _G.results[3])
        end
        f = coroutine.create(function (...)
          print('LUA ENTER coroutine', ...)
          local arg = {...}
          print('LUA ARGS TABLE:', arg[1], arg[2], arg[3], arg[4])
          for i=1,#arg do
            print('LUA FORLOOP i=', i, 'arg[i]=', arg[i])
            test_unpack(arg[i])
          end
        end)
        -- Loop to resume until coroutine is dead
        local status, yielded
        repeat
          status, yielded = coroutine.resume(f)
        until coroutine.status(f) == 'dead'
        print('LUA FINAL:', _G.results, _G.results[1], _G.results[2], _G.results[3])
      ''');

      final rawResults = bridge.getGlobal('results');
      print(
        'DEBUG: rawResults = \\$rawResults, type = \\${rawResults.runtimeType}',
      );
      if (rawResults is Value && rawResults.raw is Map) {
        print(
          'DEBUG: rawResults.raw keys = \\${(rawResults.raw as Map).keys.toList()}',
        );
        print(
          'DEBUG: rawResults.raw values = \\${(rawResults.raw as Map).values.toList()}',
        );
      }
      final results = fromLuaValue(rawResults);
      print(
        'DEBUG: fromLuaValue(results) = \\$results, type = \\${results.runtimeType}',
      );
      // The coroutine receives no arguments, so the results table should be empty
      // This matches the reference Lua interpreter behavior
      expect(results, isA<Map>());
      expect(results.isEmpty, isTrue);
    });
  }, skip: 'temporarily disabled');
}
