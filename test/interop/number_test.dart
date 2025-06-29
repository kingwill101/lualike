import 'package:lualike/lualike.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  final lualike = LuaLike();

  group('LuaLike Numeric Operator Interop', () {
    Future<void> check(
      String lua,
      dynamic expected, {
      bool isNaN = false,
    }) async {
      await lualike.runCode('result = $lua');
      final result = await lualike.getGlobal('result');
      var value = result is Value ? result.unwrap() : result;
      if (value is List && value.isNotEmpty) value = value.first;
      if (isNaN) {
        expect(value is double && value.isNaN, isTrue);
      } else {
        expect(value, equals(expected));
      }
    }

    test('Addition', () async => await check('2 + 3', 5));
    test('Subtraction', () async => await check('10 - 4', 6));
    test('Multiplication', () async => await check('6 * 7', 42));
    test('Division', () async => await check('8 / 2', 4));
    test('Floor Division', () async => await check('7 // 2', 3));
    test('Modulo', () async => await check('10 % 3', 1));
    test('Exponentiation', () async => await check('2 ^ 3', 8));
    test('Negation', () async => await check('-5', -5));
    test('Bitwise AND', () async => await check('0xF0 & 0x0F', 0));
    test('Bitwise OR', () async => await check('0xF0 | 0x0F', 0xFF));
    test('Bitwise XOR', () async => await check('0xF0 ~ 0xFF', 0x0F));
    test('Bitwise NOT', () async => await check('~0xF0', ~0xF0));
    test('Left Shift', () async => await check('0xF0 << 4', 0xF00));
    test('Right Shift', () async => await check('0xF0 >> 4', 0x0F));
    test('NaN', () async => await check('0/0', null, isNaN: true));
    test('Infinity', () async => await check('1/0', double.infinity));
    test(
      'Negative Infinity',
      () async => await check('-1/0', double.negativeInfinity),
    );
    test(
      'BigInt-like',
      () async => await check(
        '9223372036854775807 + 1',
        -9223372036854775808, // Integer overflow wraps around in Lua
      ),
    );
    test('Comparison ==', () async => await check('5 == 5', true));
    test('Comparison ~= (not equal)', () async => await check('5 ~= 6', true));
    test('Comparison <', () async => await check('3 < 4', true));
    test('Comparison >', () async => await check('4 > 3', true));
    test('Comparison <=', () async => await check('3 <= 3', true));
    test('Comparison >=', () async => await check('4 >= 3', true));
  });
}
