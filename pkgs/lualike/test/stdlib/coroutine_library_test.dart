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

    test('wrap handles tail-call chains via __call metamethods', () async {
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

        tailWrapResult = coroutine.wrap(function()
          return foo()
        end)()
      ''');

      expect(lua.getGlobal('tailWrapResult').unwrap(), equals(99));
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
