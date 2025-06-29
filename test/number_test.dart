import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('LuaNumberParser.parse', () {
    test('decimal integers', () {
      expect(LuaNumberParser.parse('7'), equals(7));
      expect(LuaNumberParser.parse('-22'), equals(-22));
    });

    test('decimal floats & scientific', () {
      expect(LuaNumberParser.parse('1.25'), equals(1.25));
      expect(LuaNumberParser.parse('12e3'), equals(12000.0));
      expect(LuaNumberParser.parse('-6.02e-23'), equals(-6.02e-23));
    });

    test('binary integers', () {
      expect(LuaNumberParser.parse('0b1011'), equals(11));
      expect(LuaNumberParser.parse('-0b1100'), equals(-12));
    });

    test('hex integers', () {
      expect(LuaNumberParser.parse('0x3FC'), equals(1020));
      expect(LuaNumberParser.parse('0XFB'), equals(251));
      expect(
        LuaNumberParser.parse('0x8000000000000000'),
        allOf(isA<BigInt>(), equals(BigInt.parse('9223372036854775808'))),
      );
    });

    test('hex floating-point', () {
      expect(LuaNumberParser.parse('0x7.4'), closeTo(7.25, 1e-12));
      expect(LuaNumberParser.parse('0x1p+4'), equals(16.0));
      expect(LuaNumberParser.parse('-0x1.8p-2'), closeTo(-0.375, 1e-12));
    });

    test('big decimal promotion', () {
      final value = LuaNumberParser.parse('12345678901234567890');
      expect(value, isA<BigInt>());
      expect(value, equals(BigInt.parse('12345678901234567890')));
    });

    test('math.lua special formats', () {
      expect(LuaNumberParser.parse('0e12'), equals(0));
      expect(LuaNumberParser.parse('.0'), equals(0.0));
      expect(LuaNumberParser.parse('0.'), equals(0.0));
      expect(LuaNumberParser.parse('.2e2'), equals(20.0));
      expect(LuaNumberParser.parse('2.E-1'), equals(0.2));
    });

    test('more number formats from math.lua', () {
      // Decimal formats from tonumber tests
      expect(LuaNumberParser.parse('+0.01'), equals(0.01));
      expect(LuaNumberParser.parse('+.01'), equals(0.01));
      expect(LuaNumberParser.parse('.01'), equals(0.01));
      expect(LuaNumberParser.parse('-1.'), equals(-1.0));
      expect(LuaNumberParser.parse('+1.'), equals(1.0));
      expect(LuaNumberParser.parse('-012'), equals(-12));
      expect(LuaNumberParser.parse('1.3e-2'), equals(1.3e-2));

      // Hex formats from tonumber tests
      expect(LuaNumberParser.parse('0x10'), equals(16));
      expect(LuaNumberParser.parse('0xfff'), equals(4095));
      expect(LuaNumberParser.parse('0x0p12'), equals(0));
      expect(LuaNumberParser.parse('0x.0p-3'), equals(0));
      expect(LuaNumberParser.parse('+0x2'), equals(2));
      expect(LuaNumberParser.parse('-0xaA'), equals(-170));

      // Hex float formats
      expect(LuaNumberParser.parse('0x2.5'), closeTo(2.3125, 1e-12));
      expect(LuaNumberParser.parse('-0x2.5'), closeTo(-2.3125, 1e-12));
      expect(LuaNumberParser.parse('+0x0.51p+8'), closeTo(81.0, 1e-12));
      expect(LuaNumberParser.parse('0x4P-2'), closeTo(1.0, 1e-12));
    });

    test('invalid number formats from math.lua', () {
      expect(() => LuaNumberParser.parse(''), throwsFormatException);
      expect(() => LuaNumberParser.parse('-'), throwsFormatException);
      expect(() => LuaNumberParser.parse('.'), throwsFormatException);
      expect(() => LuaNumberParser.parse('0x'), throwsFormatException);
      expect(() => LuaNumberParser.parse('0x3.3.3'), throwsFormatException);
      expect(() => LuaNumberParser.parse('e1'), throwsFormatException);
      expect(() => LuaNumberParser.parse('1.0e+'), throwsFormatException);
    });
  });
}
