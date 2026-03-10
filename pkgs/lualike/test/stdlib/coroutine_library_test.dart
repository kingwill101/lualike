import 'package:lualike_test/test.dart';

void main() {
  group('Coroutine library', () {
    late LuaLike lua;

    setUp(() {
      lua = LuaLike();
    });

    test('create/resume drives coroutine lifecycle', () async {
      await lua.execute(r'''
        insideIsMain = nil
        insideEquals = false
        isyieldableInside = nil
        isyieldableMain = coroutine.isyieldable()

        local function worker(a, b)
          local current, isMain = coroutine.running()
          insideIsMain = isMain
          insideEquals = current == co
          isyieldableInside = coroutine.isyieldable()
          local resumeArg = coroutine.yield(a + b)
          return a * resumeArg
        end

        co = coroutine.create(worker)
        coYieldableBefore = coroutine.isyieldable(co)
        mainThread, isMainThread = coroutine.running()
        firstOk, firstValue = coroutine.resume(co, 3, 4)
        midStatus = coroutine.status(co)
        secondOk, secondValue = coroutine.resume(co, 5)
        finalStatus = coroutine.status(co)
        coYieldableAfter = coroutine.isyieldable(co)
      ''');

      expect(lua.getGlobal('firstOk').unwrap(), isTrue);
      expect(lua.getGlobal('firstValue').unwrap(), equals(7));

      expect(lua.getGlobal('secondOk').unwrap(), isTrue);
      expect(lua.getGlobal('secondValue').unwrap(), equals(15));

      expect(lua.getGlobal('midStatus').unwrap(), equals('suspended'));
      expect(lua.getGlobal('finalStatus').unwrap(), equals('dead'));

      expect(lua.getGlobal('isMainThread').unwrap(), isTrue);
      expect(lua.getGlobal('insideIsMain').unwrap(), isFalse);
      expect(lua.getGlobal('insideEquals').unwrap(), isTrue);
      expect(lua.getGlobal('isyieldableMain').unwrap(), isFalse);
      expect(lua.getGlobal('isyieldableInside').unwrap(), isTrue);
      expect(lua.getGlobal('coYieldableBefore').unwrap(), isTrue);
      expect(lua.getGlobal('coYieldableAfter').unwrap(), isFalse);
    });

    test('wrap forwards yields and raises errors', () async {
      await lua.execute(r'''
        wrapped = coroutine.wrap(function()
          local input = coroutine.yield(5)
          if input == "boom" then error("boom") end
          return input * 2
        end)

        wrapFirst = wrapped()
        wrapSecond = wrapped(11)
        wrapPcallOk, wrapPcallErr = pcall(wrapped)

        errorWrap = coroutine.wrap(function()
          error("kaboom")
        end)
        errorPcallOk, errorPcallErr = pcall(errorWrap)
      ''');

      expect(lua.getGlobal('wrapFirst').unwrap(), equals(5));
      expect(lua.getGlobal('wrapSecond').unwrap(), equals(22));
      expect(lua.getGlobal('wrapPcallOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('wrapPcallErr').unwrap().toString(),
        contains('cannot resume dead coroutine'),
      );
      expect(lua.getGlobal('errorPcallOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('errorPcallErr').unwrap().toString(),
        contains('kaboom'),
      );
    });

    test('wrap preserves primitive error objects through pcall', () async {
      await lua.execute(r'''
        numericWrap = coroutine.wrap(function()
          error(23)
        end)
        numericOk, numericErr = pcall(numericWrap)
        numericEq = numericErr == 23
      ''');

      expect(lua.getGlobal('numericOk').unwrap(), isFalse);
      expect(lua.getGlobal('numericErr').unwrap(), equals(23));
      expect(lua.getGlobal('numericEq').unwrap(), isTrue);
    });

    test('wrap reports __call chain limits via metamethods', () async {
      await lua.execute(r'''
        local depth = 256
        local function foo()
          if depth == 0 then return 99
          else depth = depth - 1; return foo()
          end
        end

        for i = 1, 32 do
          foo = setmetatable({}, { __call = foo })
        end

        tailWrapOk, tailWrapError = pcall(function()
          return coroutine.wrap(function()
            return foo()
          end)()
        end)
      ''');

      expect(lua.getGlobal('tailWrapOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('tailWrapError').unwrap().toString(),
        contains('__call\' chain too long'),
      );
    });

    test('wrap accepts iterators returned by string.gmatch', () async {
      await lua.execute(r'''
        local iter = string.gmatch("1 2 3", "%d+")
        directFirst = iter()
        wrappedIterResult = coroutine.wrap(iter)()
      ''');

      expect(lua.getGlobal('directFirst').unwrap(), equals('1'));
      expect(lua.getGlobal('wrappedIterResult').unwrap(), equals('2'));
    });

    test('wrap preserves zero return values after yielding closes', () async {
      await lua.execute(r'''
        function func2close(f)
          local t = {}
          return setmetatable(t, { __close = f })
        end

        local wrapped = coroutine.wrap(function()
          local x <close> = func2close(coroutine.yield)
          return
        end)

        wrapYielded = wrapped()
        wrapResults = table.pack(wrapped())
        wrapResultCount = wrapResults.n
        wrapResultFirst = wrapResults[1]
      ''');

      expect(lua.getGlobal('wrapYielded').unwrap(), isNotNull);
      expect(lua.getGlobal('wrapResultCount').unwrap(), equals(0));
      expect(lua.getGlobal('wrapResultFirst').unwrap(), isNull);
    });

    test('resume preserves yielded table.unpack arity', () async {
      await lua.execute(r'''
        yielded = nil
        local function worker(a, ...)
          local arg = {...}
          for i = 1, #arg do
            yielded = {coroutine.yield(table.unpack(arg[i]))}
          end
          return table.unpack(a)
        end

        co = coroutine.create(worker)
        ok1, a1 = coroutine.resume(co, {1, 2, 3}, {}, {1}, {'a', 'b', 'c'})
        ok2, a2, b2 = coroutine.resume(co)
        yieldedIsNil2 = yielded == nil
        yieldedLen2 = yielded and #yielded or -1
        yieldedFirst2 = yielded and yielded[1] or nil
        ok3, a3, b3, c3, d3 = coroutine.resume(co, 1, 2, 3)
        yieldedIsNil3 = yielded == nil
        yieldedLen3 = yielded and #yielded or -1
        yieldedFirst3 = yielded and yielded[1] or nil
        yieldedSecond3 = yielded and yielded[2] or nil
        yieldedThird3 = yielded and yielded[3] or nil
      ''');

      expect(lua.getGlobal('ok1').unwrap(), isTrue);
      expect(lua.getGlobal('a1').unwrap(), isNull);
      expect(lua.getGlobal('ok2').unwrap(), isTrue);
      expect(lua.getGlobal('a2').unwrap(), equals(1));
      expect(lua.getGlobal('b2').unwrap(), isNull);
      expect(lua.getGlobal('yieldedIsNil2').unwrap(), isFalse);
      expect(lua.getGlobal('yieldedLen2').unwrap(), equals(0));
      expect(lua.getGlobal('yieldedFirst2').unwrap(), isNull);
      expect(lua.getGlobal('ok3').unwrap(), isTrue);
      expect(lua.getGlobal('a3').unwrap(), equals('a'));
      expect(lua.getGlobal('b3').unwrap(), equals('b'));
      expect(lua.getGlobal('c3').unwrap(), equals('c'));
      expect(lua.getGlobal('d3').unwrap(), isNull);
      expect(lua.getGlobal('yieldedIsNil3').unwrap(), isFalse);
      expect(lua.getGlobal('yieldedLen3').unwrap(), equals(3));
      expect(lua.getGlobal('yieldedFirst3').unwrap(), equals(1));
      expect(lua.getGlobal('yieldedSecond3').unwrap(), equals(2));
      expect(lua.getGlobal('yieldedThird3').unwrap(), equals(3));
    });

    test('wrap surfaces __call chain limits through deep tail calls', () async {
      await lua.execute(r'''
        local n = 10000

        local function foo()
          if n == 0 then return 1023
          else n = n - 1; return foo()
          end
        end

        for i = 1, 100 do
          foo = setmetatable({}, {__call = foo})
        end

        tailCallChainOk, tailCallChainError = pcall(function()
          return coroutine.wrap(function()
            return foo()
          end)()
        end)
      ''');

      expect(lua.getGlobal('tailCallChainOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('tailCallChainError').unwrap().toString(),
        contains('__call\' chain too long'),
      );
    });

    test('wrap supports recursive generators using yield', () async {
      await lua.execute(r'''
        local x = {"=", "[", "]", "\n"}
        local len = 2
        local function gen(c, n)
          if n == 0 then
            coroutine.yield(c)
          else
            for _, a in ipairs(x) do
              gen(c .. a, n - 1)
            end
          end
        end

        local iter = coroutine.wrap(function() gen("", len) end)
        wrapGenA = iter()
        wrapGenB = iter()
      ''');

      expect(lua.getGlobal('wrapGenA').unwrap(), equals('=='));
      expect(lua.getGlobal('wrapGenB').unwrap(), equals('=['));
    });

    test('close transitions coroutine to dead state', () async {
      await lua.execute(r'''
        closable = coroutine.create(function()
          coroutine.yield('pause')
          return 99
        end)

        resumeOk, resumeVal = coroutine.resume(closable)
        closeOk = select(1, coroutine.close(closable))
        statusAfterClose = coroutine.status(closable)

        errorCo = coroutine.create(function()
          coroutine.yield()
        end)
        coroutine.resume(errorCo)
        errorCloseOk, errorCloseMsg = coroutine.close(errorCo, 'fatal')
      ''');

      expect(lua.getGlobal('resumeOk').unwrap(), isTrue);
      expect(lua.getGlobal('resumeVal').unwrap(), equals('pause'));
      expect(lua.getGlobal('closeOk').unwrap(), isTrue);
      expect(lua.getGlobal('statusAfterClose').unwrap(), equals('dead'));
      expect(lua.getGlobal('errorCloseOk').unwrap(), isFalse);
      expect(lua.getGlobal('errorCloseMsg').unwrap(), equals('fatal'));
    });

    test('close rejects main and normal coroutines', () async {
      await lua.execute(r'''
        mainThread = select(1, coroutine.running())
        mainCloseOk, mainCloseErr = pcall(coroutine.close, mainThread)

        coroutine.wrap(function ()
          mainStatusInsideCoroutine = coroutine.status(mainThread)
          local ok, err = pcall(coroutine.close, mainThread)
          normalCloseOk = ok
          normalCloseErr = err
        end)()
      ''');

      expect(lua.getGlobal('mainCloseOk').unwrap(), isFalse);
      expect(
        (lua.getGlobal('mainCloseErr') as Value).raw.toString(),
        contains('main'),
      );
      expect(lua.getGlobal('normalCloseOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('mainStatusInsideCoroutine').unwrap(),
        equals('normal'),
      );
      expect(
        (lua.getGlobal('normalCloseErr') as Value).raw.toString(),
        contains('normal'),
      );
    });

    test(
      'coroutines created from builtins report errors via resume and close',
      () async {
        await lua.execute(r'''
        errorCo = coroutine.create(error)
        resumeOk, resumeErr = coroutine.resume(errorCo, 100)
        closeOk1, closeErr1 = coroutine.close(errorCo)
        closeOk2 = select(1, coroutine.close(errorCo))
      ''');

        expect(lua.getGlobal('resumeOk').unwrap(), isFalse);
        expect(lua.getGlobal('resumeErr').unwrap(), equals(100));
        expect(lua.getGlobal('closeOk1').unwrap(), isFalse);
        expect(lua.getGlobal('closeErr1').unwrap(), equals(100));
        expect(lua.getGlobal('closeOk2').unwrap(), isTrue);
      },
    );

    test(
      'yielded iterator calls continue yielding resumed control values',
      () async {
        await lua.execute(r'''
        local f = function (s, i) return coroutine.yield(i) end

        wrapped = coroutine.wrap(function ()
          return pcall(function ()
            local s = 0
            local q = 42
            for i in f, nil, 1 do
              s = s + i
            end
            return s, q
          end)
        end)

        firstYield = wrapped()
        ok2, sum2, q2 = wrapped(0)
      ''');

        expect(lua.getGlobal('firstYield').unwrap(), equals(1));
        expect(lua.getGlobal('ok2').unwrap(), equals(0));
        expect(lua.getGlobal('sum2').unwrap(), isNull);
        expect(lua.getGlobal('q2').unwrap(), isNull);
      },
    );

    test('pcall preserves locals after yielded iterator resumes', () async {
      await lua.execute(r'''
        local f = function (s, i) return coroutine.yield(i) end

        wrapped = coroutine.wrap(function ()
          return pcall(function ()
            local s = 0
            for i in f, nil, 1 do
              pcall(function () s = s + i end)
            end
            return s
          end)
        end)

        firstYield = wrapped()
        for n = 1, 10 do
          lastYield = wrapped(n)
        end
        ok3, sum3 = wrapped(nil)
      ''');

      expect(lua.getGlobal('firstYield').unwrap(), equals(1));
      expect(lua.getGlobal('lastYield').unwrap(), equals(10));
      expect(lua.getGlobal('ok3').unwrap(), isTrue);
      expect(lua.getGlobal('sum3').unwrap(), equals(55));
    });

    test(
      'coroutine debug hooks include the final return after a yield',
      () async {
        await lua.execute(r'''
        local co = coroutine.create(function ()
          coroutine.yield(10)
          return 20
        end)

        local trace = {}
        local function dotrace (event)
          trace[#trace + 1] = event
        end

        debug.sethook(co, dotrace, 'clr')
        repeat until not coroutine.resume(co)

        traceCount = #trace
        traceJoined = table.concat(trace, ',')
      ''');

        expect(lua.getGlobal('traceCount').unwrap(), equals(6));
        expect(
          lua.getGlobal('traceJoined').unwrap(),
          equals('call,line,call,return,line,return'),
        );
      },
    );

    test(
      'yielded closures keep captured locals after wrapper collection',
      () async {
        await lua.execute(r'''
        local weak = {}
        setmetatable(weak, {__mode = 'kv'})

        local wrapped = coroutine.wrap(function ()
          local a = 10
          local function f ()
            a = a + 10
            return a
          end
          while true do
            a = a + 1
            coroutine.yield(f)
          end
        end)

        weak[1] = wrapped
        local retained = wrapped()
        first = retained()
        second = wrapped()()
        sameClosure = wrapped() == retained

        wrapped = nil
        collectgarbage()
        collectgarbage()

        weakCleared = weak[1] == nil
        afterGc1 = retained()
        afterGc2 = retained()
      ''');

        expect(lua.getGlobal('first').unwrap(), equals(21));
        expect(lua.getGlobal('second').unwrap(), equals(32));
        expect(lua.getGlobal('sameClosure').unwrap(), isTrue);
        expect(lua.getGlobal('weakCleared').unwrap(), isTrue);
        expect(lua.getGlobal('afterGc1').unwrap(), equals(43));
        expect(lua.getGlobal('afterGc2').unwrap(), equals(53));
      },
    );

    test(
      'self resume reports non-suspended coroutine and runs close handlers',
      () async {
        await lua.execute(r'''
        closed = false
        wrapped = coroutine.wrap(function()
          local _ <close> = setmetatable({}, {
            __close = function () closed = true end
          })
          return pcall(wrapped, 1)
        end)

        okSelf, errSelf = wrapped()
      ''');

        expect(lua.getGlobal('okSelf').unwrap(), isFalse);
        expect(
          lua.getGlobal('errSelf').unwrap().toString(),
          contains('non-suspended'),
        );
        expect(lua.getGlobal('closed').unwrap(), isTrue);
      },
    );

    test(
      'recursive wrap chains fail with stack overflow instead of hanging',
      timeout: const Timeout(Duration(seconds: 5)),
      () async {
        await lua.execute(r'''
          a = function(a) coroutine.wrap(a)(a) end
          wrapOverflowOk, wrapOverflowErr = pcall(a, a)
        ''');

        expect(lua.getGlobal('wrapOverflowOk').unwrap(), isFalse);
        expect(
          lua.getGlobal('wrapOverflowErr').unwrap().toString(),
          contains('stack overflow'),
        );
      },
    );

    test('resume reports main-thread and dead-thread errors', () async {
      await lua.execute(r'''
        mainThread = select(1, coroutine.running())
        mainResumeOk, mainResumeErr = coroutine.resume(mainThread)

        finished = coroutine.create(function()
          return 1
        end)
        firstOk, firstValue = coroutine.resume(finished)
        secondOk, secondErr = coroutine.resume(finished)
      ''');

      expect(lua.getGlobal('mainResumeOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('mainResumeErr').unwrap(),
        equals('cannot resume main thread'),
      );
      expect(lua.getGlobal('firstOk').unwrap(), isTrue);
      expect(lua.getGlobal('firstValue').unwrap(), equals(1));
      expect(lua.getGlobal('secondOk').unwrap(), isFalse);
      expect(
        lua.getGlobal('secondErr').unwrap(),
        equals('cannot resume dead coroutine'),
      );
    });

    test(
      'weak-value tables release unreachable coroutines after collection',
      () async {
        await lua.execute(r'''
        weakFresh = setmetatable({}, { __mode = 'v' })
        do
          local transient = coroutine.create(function()
            return 1
          end)
          weakFresh.thread = transient
          transient = nil
        end

        collectgarbage('collect')
        collectgarbage('collect')
        freshCollected = weakFresh.thread == nil

        weakClosed = setmetatable({}, { __mode = 'v' })
        do
          local transient = coroutine.create(function()
            coroutine.yield('pause')
          end)
          weakClosed.thread = transient
          coroutine.resume(transient)
          coroutine.close(transient)
          transient = nil
        end

        collectgarbage('collect')
        collectgarbage('collect')
        closedCollected = weakClosed.thread == nil
      ''');

        expect(lua.getGlobal('freshCollected').unwrap(), isTrue);
        expect(lua.getGlobal('closedCollected').unwrap(), isTrue);
      },
    );

    test(
      'reachable suspended coroutines survive explicit collection',
      () async {
        await lua.execute(r'''
        local co = coroutine.create(function (x)
          local a = 1
          coroutine.yield(x)
          return a
        end)

        local ok, value = coroutine.resume(co, 10)
        assert(ok and value == 10)
        beforeStatus = coroutine.status(co)
        collectgarbage('collect')
        collectgarbage('collect')
        afterStatus = coroutine.status(co)
        resumedOk, resumedValue = coroutine.resume(co)
      ''');

        expect(lua.getGlobal('beforeStatus').unwrap(), equals('suspended'));
        expect(lua.getGlobal('afterStatus').unwrap(), equals('suspended'));
        expect(lua.getGlobal('resumedOk').unwrap(), isTrue);
        expect(lua.getGlobal('resumedValue').unwrap(), equals(1));
      },
    );

    test('self-referenced threads do not overflow at modest counts', () async {
      await lua.execute(r'''
        local thread_id = 0
        local threads = {}
        local function fn(thread)
          local x = {}
          threads[thread_id] = function()
            thread = x
          end
          coroutine.yield()
        end

        while thread_id < 50 do
          local thread = coroutine.create(fn)
          assert(coroutine.resume(thread, thread))
          thread_id = thread_id + 1
        end
      ''');
    });
  });
}
