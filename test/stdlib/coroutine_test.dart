import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('Coroutine Tests', () {
    late LuaLikeBridge bridge;

    setUp(() {
      bridge = LuaLikeBridge();
    });

    test('Basic coroutine creation and execution', () async {
      await bridge.runCode('''
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
      await bridge.runCode('''
      co = coroutine.create(function(x)
        -- Print the value of x to debug
        print("Inside coroutine, x =", x)
        local y = coroutine.yield(x + 1)
        print("After yield, y =", y)
        return x + y
      end)

      -- Store the results in global variables
      first = {coroutine.resume(co, 10)}
      print("First resume result:", first[1], first[2])
      second = {coroutine.resume(co, 20)}
      print("Second resume result:", second[1], second[2])
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
      await bridge.runCode('''
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

    test('Coroutine wrap', () async {
      await bridge.runCode('''
      f = coroutine.wrap(function(a, b)
        return a + b
      end)

      result = f(5, 7)
      ''');

      expect(bridge.getGlobal('result').raw, equals(12)); // 5+7
    });

    test('Complex coroutine example from Lua manual', () async {
      await bridge.runCode('''
      function foo(a)
        print("foo", a)
        return coroutine.yield(2*a)
      end

      co = coroutine.create(function(a, b)
        print("co-body", a, b)
        local r = foo(a+1)
        print("co-body", r)
        local r, s = coroutine.yield(a+b, a-b)
        print("co-body", r, s)
        return b, "end"
      end)

      print("main", coroutine.resume(co, 1, 10))
      print("main", coroutine.resume(co, "r"))
      print("main", coroutine.resume(co, "x", "y"))
      result = {coroutine.resume(co, "x", "y")}
      ''');

      final result = fromLuaValue(bridge.getGlobal('result'));
      expect(result[0], isFalse);
      expect(result[1], contains("cannot resume"));
    });

    test('Coroutine running', () async {
      await bridge.runCode('''
      co = coroutine.create(function()
        running, isMain = coroutine.running()
        return isMain
      end)

      mainRunning, mainIsMain = coroutine.running()
      result = {coroutine.resume(co)}
      ''');

      expect(fromLuaValue(bridge.getGlobal('mainIsMain')), isTrue);
      final result = fromLuaValue(bridge.getGlobal('result'));
      expect(result[0], isTrue);
      expect(result[1], isFalse);
    });

    test('Coroutine isyieldable', () async {
      await bridge.runCode('''
      co = coroutine.create(function()
        result = coroutine.isyieldable()
        return result
      end)

      mainYieldable = coroutine.isyieldable()
      resumed = {coroutine.resume(co)}
      ''');

      expect(bridge.getGlobal('mainYieldable').raw, isFalse);
      final result = fromLuaValue(bridge.getGlobal('resumed'));
      expect(result[0], isTrue);
      expect(result[1], isTrue);
    });

    test('Coroutine close', () async {
      await bridge.runCode('''
      co = coroutine.create(function()
        coroutine.yield()
      end)

      coroutine.resume(co)
      result = {coroutine.close(co)}
      statusAfterClose = coroutine.status(co)
      ''');

      final result = fromLuaValue(bridge.getGlobal('result'));
      expect(result[0], isTrue);
      expect(
        fromLuaValue(bridge.getGlobal('statusAfterClose')),
        equals('dead'),
      );
    });

    test('Multiple yields and resumes', () async {
      await bridge.runCode('''
      co = coroutine.create(function()
        local x = 0
        for i = 1, 3 do
          x = x + i
          x = coroutine.yield(x)
        end
        return x
      end)

      r1 = {coroutine.resume(co)}
      r2 = {coroutine.resume(co, 10)}
      r3 = {coroutine.resume(co, 20)}
      r4 = {coroutine.resume(co, 30)}
      ''');

      final r1 = fromLuaValue(bridge.getGlobal('r1'));
      final r2 = fromLuaValue(bridge.getGlobal('r2'));
      final r3 = fromLuaValue(bridge.getGlobal('r3'));
      final r4 = fromLuaValue(bridge.getGlobal('r4'));

      expect(r1[0], isTrue);
      expect(r1[1], equals(1));

      expect(r2[0], isTrue);
      expect(r2[1], equals(12));
      expect(r3[0], isTrue);
      expect(r3[1], equals(23));

      expect(r4[0], isTrue);
      expect(r4[1], equals(30)); // 6+3
    });

    test('Error handling in coroutines', () async {
      await bridge.runCode('''
      co = coroutine.create(function()
        error("test error")
      end)

      result = {coroutine.resume(co)}
      ''');

      final result = fromLuaValue(bridge.getGlobal('result'));
      expect(result[0], isFalse);
      expect(result[1], contains("test error"));
    });
  });
}
