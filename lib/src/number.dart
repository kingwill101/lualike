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

import 'stdlib/number_utils.dart';

/// Prevent instantiation – this is a pure utility class.
class LuaNumberParser {
  LuaNumberParser._();

  /// 64-bit signed limits (native Dart `int` range).
  static final BigInt _min64 = BigInt.from(NumberUtils.minInteger);
  static final BigInt _max64 = BigInt.from(NumberUtils.maxInteger);

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

    // Check for multiple signs (invalid in Lua)
    if (unsigned.startsWith('+') || unsigned.startsWith('-')) {
      throw FormatException('Multiple signs in numeric literal: $literal');
    }

    final s = unsigned.toLowerCase();

    // ============ HEXADECIMAL BRANCH ============
    if (s.startsWith('0x')) {
      final body = s.substring(2);

      // Reject hex numbers with leading/trailing spaces or internal spaces
      if (body.trim() != body || body.contains(' ') || body.contains('\t')) {
        throw FormatException(
          'Invalid hexadecimal number with whitespace: $literal',
        );
      }

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

      // remove decimal point for easier handling
      final dot = numPart.indexOf('.');
      if (dot != -1 && numPart.indexOf('.', dot + 1) != -1) {
        throw FormatException('Invalid hexadecimal float');
      }

      final digits = numPart.replaceAll('.', '');
      final fracDigits = dot == -1 ? 0 : numPart.length - dot - 1;

      BigInt mantissa = BigInt.parse(digits, radix: 16);
      var exponent = int.parse(expPart) - 4 * fracDigits;

      // Adjust magnitude using shifts before converting to double
      double value;
      if (exponent >= 0) {
        mantissa = mantissa << exponent;
        value = mantissa.toDouble();
      } else {
        final shift = -exponent;
        final intPart = mantissa >> shift;
        final fracMask = (BigInt.one << shift) - BigInt.one;
        final fracPart = mantissa & fracMask;
        value = intPart.toDouble();
        if (fracPart != BigInt.zero) {
          value += fracPart.toDouble() / math.pow(2.0, shift);
        }
      }

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
