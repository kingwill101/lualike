import 'dart:math' as math;

import 'package:lualike/testing.dart';

void main() {
  group('Math Library', () {
    late LuaLike bridge;

    setUp(() {
      bridge = LuaLike();
    });

    test('basic arithmetic functions', () async {
      await bridge.runCode('''
        local abs = math.abs(-5)
        local ceil = math.ceil(3.4)
        local floor = math.floor(3.7)
        local max = math.max(1, 5, 3, 2, 4)
        local min = math.min(1, 5, 3, 2, 4)
        local mod = math.fmod(10, 3)
      ''');

      var abs = bridge.getGlobal('abs');
      var ceil = bridge.getGlobal('ceil');
      var floor = bridge.getGlobal('floor');
      var max = bridge.getGlobal('max');
      var min = bridge.getGlobal('min');
      var mod = bridge.getGlobal('mod');

      expect((abs as Value).raw, equals(5));
      expect((ceil as Value).raw, equals(4));
      expect((floor as Value).raw, equals(3));
      expect((max as Value).raw, equals(5));
      expect((min as Value).raw, equals(1));
      expect((mod as Value).raw, equals(1));
    });

    test('trigonometric functions', () async {
      await bridge.runCode('''
        local pi = math.pi
        local sin = math.sin(pi/2)
        local cos = math.cos(pi)
        local tan = math.tan(pi/4)
        local asin = math.asin(1)
        local acos = math.acos(0)
        local atan = math.atan(1)
      ''');

      var sin = bridge.getGlobal('sin');
      var cos = bridge.getGlobal('cos');
      var tan = bridge.getGlobal('tan');
      var asin = bridge.getGlobal('asin');
      var acos = bridge.getGlobal('acos');
      var atan = bridge.getGlobal('atan');

      expect((sin as Value).raw, closeTo(1, 1e-10));
      expect((cos as Value).raw, closeTo(-1, 1e-10));
      expect((tan as Value).raw, closeTo(1, 1e-10));
      expect((asin as Value).raw, closeTo(math.pi / 2, 1e-10));
      expect((acos as Value).raw, closeTo(math.pi / 2, 1e-10));
      expect((atan as Value).raw, closeTo(math.pi / 4, 1e-10));
    });

    test('exponential and logarithmic functions', () async {
      await bridge.runCode('''
        local exp = math.exp(1)
        local log = math.log(math.exp(1))
        local log10 = math.log(100, 10)
        local sqrt = math.sqrt(16)
      ''');

      var exp = bridge.getGlobal('exp');
      var log = bridge.getGlobal('log');
      var log10 = bridge.getGlobal('log10');
      var sqrt = bridge.getGlobal('sqrt');

      expect((exp as Value).raw, closeTo(math.e, 1e-10));
      expect((log as Value).raw, closeTo(1, 1e-10));
      expect((log10 as Value).raw, closeTo(2, 1e-10));
      expect((sqrt as Value).raw, equals(4));
    });

    test('random number generation', () async {
      await bridge.runCode('''
        math.randomseed(12345)
        local r1 = math.random()
        local r2 = math.random(10)
        local r3 = math.random(20, 30)
      ''');

      var r1 = bridge.getGlobal('r1');
      var r2 = bridge.getGlobal('r2');
      var r3 = bridge.getGlobal('r3');

      expect((r1 as Value).raw, isA<double>());
      expect((r1).raw, greaterThanOrEqualTo(0));
      expect((r1).raw, lessThan(1));

      expect((r2 as Value).raw, isA<int>());
      expect((r2).raw, greaterThanOrEqualTo(1));
      expect((r2).raw, lessThanOrEqualTo(10));

      expect((r3 as Value).raw, isA<int>());
      expect((r3).raw, greaterThanOrEqualTo(20));
      expect((r3).raw, lessThanOrEqualTo(30));
    });

    test('xoshiro deterministic integer', () async {
      await bridge.runCode('''
        math.randomseed(1007)
        result = math.random(0)
      ''');

      final result = bridge.getGlobal('result') as Value;
      expect(result.raw, equals(8822622750169614806));
    });

    test('angle conversion', () async {
      await bridge.runCode('''
        local deg = math.deg(math.pi)
        local rad = math.rad(180)
      ''');

      var deg = bridge.getGlobal('deg');
      var rad = bridge.getGlobal('rad');

      expect((deg as Value).raw, closeTo(180, 1e-10));
      expect((rad as Value).raw, closeTo(math.pi, 1e-10));
    });

    test('math type checking', () async {
      await bridge.runCode('''
        local t1 = math.type(3)
        local t2 = math.type(3.14)
        local t3 = math.type("not a number")
      ''');

      var t1 = bridge.getGlobal('t1');
      var t2 = bridge.getGlobal('t2');
      var t3 = bridge.getGlobal('t3');

      expect((t1 as Value).raw, equals("integer"));
      expect((t2 as Value).raw, equals("float"));
      expect((t3 as Value).raw, equals(null));
    });

    test('modf function', () async {
      await bridge.runCode('''
        local i, f = math.modf(3.14)
      ''');

      var i = bridge.getGlobal('i');
      var f = bridge.getGlobal('f');

      expect((i as Value).raw, equals(3));
      expect((f as Value).raw, closeTo(0.14, 1e-10));
    });

    test('constants', () async {
      await bridge.runCode('''
        local pi = math.pi
        local huge = math.huge
      ''');

      var pi = bridge.getGlobal('pi');
      var huge = bridge.getGlobal('huge');

      expect((pi as Value).raw, equals(math.pi));
      expect((huge as Value).raw, equals(double.infinity));
    });

    test('indirect usage through metatables', () async {
      await bridge.runCode('''
        local x = -5
        local y = math.abs(x)
        local sum = 2 + 3
        local neg = -x
        local prod = 2 * 3
      ''');

      var y = bridge.getGlobal('y');
      var sum = bridge.getGlobal('sum');
      var neg = bridge.getGlobal('neg');
      var prod = bridge.getGlobal('prod');

      expect((y as Value).raw, equals(5));
      expect((sum as Value).raw, equals(5));
      expect((neg as Value).raw, equals(5));
      expect((prod as Value).raw, equals(6));
    });
  });
}
