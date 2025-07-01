/// A helper that recognises every numeric literal Lua accepts:
///   * Decimal integers                7   -22
///   * Decimal floating-point          1.25
///   * Scientific notation             6.02e23  -1e-3
///   * Binary integers                 0b1011
///   * Hex integers                    0x3FC
///   * Hex floating-point              0x7.4   0x1p+4  -0x1.8p-2
///
/// The return type is:
///   • `int`    – if the value fits in a 64-bit signed range
///   • `BigInt` – for larger whole numbers
///   • `double` – for anything with a fractional part / exponent
///
/// Usage:
///   final value = LuaNumberParser.parse('0x7.4'); // 7.25 (double)
///
library;

import 'dart:math' as math;

/// Prevent instantiation – this is a pure utility class.
class LuaNumberParser {
  LuaNumberParser._();

  /// 64-bit signed limits (native Dart `int` range).
  static final BigInt _min64 =
      BigInt.from(-0x7FFFFFFFFFFFFFFF) - BigInt.one; // -2^63
  static final BigInt _max64 = BigInt.from(0x7FFFFFFFFFFFFFFF); //  2^63-1

  /// Parse [literal] and return `int`, `double`, or `BigInt`.
  static dynamic /* int | double | BigInt */ parse(String literal) {
    if (literal.isEmpty) {
      throw FormatException('Empty numeric literal');
    }

    // ----- strip optional sign -----
    final neg = literal.startsWith('-');
    final unsigned = (neg || literal.startsWith('+'))
        ? literal.substring(1)
        : literal;
    final s = unsigned.toLowerCase();

    // ============ HEXADECIMAL BRANCH ============
    if (s.startsWith('0x')) {
      final body = s.substring(2);

      final hasDot = body.contains('.');
      final pIndex = body.indexOf(RegExp(r'[pP]'));

      // ---------- hex integer ----------
      if (!hasDot && pIndex == -1) {
        final big = BigInt.parse(body, radix: 16);
        var signed = neg ? -big : big;
        // Lua wraps overflowing hexadecimal integers to 64 bits
        signed = signed.toUnsigned(64).toSigned(64);
        return signed.toInt();
      }

      // ---------- hex floating-point ----------
      final numPart = pIndex == -1 ? body : body.substring(0, pIndex);
      final expPart = pIndex == -1 ? '0' : body.substring(pIndex + 1);

      // split integer / fractional
      final dot = numPart.indexOf('.');
      final intStr = dot == -1 ? numPart : numPart.substring(0, dot);
      final fracStr = dot == -1 ? '' : numPart.substring(dot + 1);

      double value = 0;

      // integer portion
      if (intStr.isNotEmpty) {
        try {
          value += int.parse(intStr, radix: 16).toDouble();
        } on FormatException {
          // very large integers may overflow the native int parser
          value += BigInt.parse(intStr, radix: 16).toDouble();
        }
      }

      // fractional portion
      if (fracStr.isNotEmpty) {
        var denom = 16.0;
        for (final c in fracStr.split('')) {
          value += int.parse(c, radix: 16) / denom;
          denom *= 16;
        }
      }

      // exponent is power of TWO
      value *= math.pow(2, int.parse(expPart));

      return neg ? -value : value;
    }

    // ============ BINARY INTEGER BRANCH ============
    if (s.startsWith('0b')) {
      final big = BigInt.parse(s.substring(2), radix: 2);
      var signed = neg ? -big : big;
      // Binary literals behave like hexadecimal ones regarding overflow
      signed = signed.toUnsigned(64).toSigned(64);
      return signed.toInt();
    }

    // ============ DECIMAL / SCIENTIFIC BRANCH ============
    if (s == '.' || s.startsWith('.e') || s.endsWith('e')) {
      throw FormatException('Invalid decimal literal "$literal"');
    }
    final hasDot = s.contains('.');
    final hasE = s.contains(RegExp(r'[eE]'));

    // decimal integer
    if (!hasDot && !hasE) {
      final big = BigInt.parse(s);
      final signed = neg ? -big : big;
      if (signed < _min64 || signed > _max64) {
        return double.parse(signed.toString());
      }
      return signed.toInt();
    }

    // decimal float / scientific
    final parsed = num.parse(s); // num.parse already handles signless string
    return neg ? -parsed : parsed;
  }
}
