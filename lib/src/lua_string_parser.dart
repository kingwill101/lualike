import 'dart:convert';

import 'package:petitparser/petitparser.dart';

/// A PetitParser-based parser for Lua string literals that handles escape sequences correctly
class LuaStringParser {
  /// Encode an invalid Unicode code point as raw bytes that will be detected as invalid UTF-8
  static List<int> _encodeInvalidCodePoint(int codePoint) {
    // For invalid code points, we need to create the UTF-8 byte sequence
    // that would be generated if the codepoint were valid, but which will
    // be detected as invalid by UTF-8 validation functions

    if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
      // Surrogates: encode as 3-byte UTF-8 sequence (even though invalid)
      // This matches what some systems do and what the tests expect
      final byte1 = 0xE0 | ((codePoint >> 12) & 0x0F);
      final byte2 = 0x80 | ((codePoint >> 6) & 0x3F);
      final byte3 = 0x80 | (codePoint & 0x3F);
      return [byte1, byte2, byte3];
    } else if (codePoint > 0x10FFFF) {
      // Code points above valid Unicode range - use extended UTF-8 encoding
      if (codePoint <= 0x1FFFFF) {
        // 4-byte sequence
        final byte1 = 0xF0 | ((codePoint >> 18) & 0x07);
        final byte2 = 0x80 | ((codePoint >> 12) & 0x3F);
        final byte3 = 0x80 | ((codePoint >> 6) & 0x3F);
        final byte4 = 0x80 | (codePoint & 0x3F);
        return [byte1, byte2, byte3, byte4];
      } else if (codePoint <= 0x3FFFFFF) {
        // 5-byte sequence (original UTF-8 specification)
        final byte1 = 0xF8 | ((codePoint >> 24) & 0x03);
        final byte2 = 0x80 | ((codePoint >> 18) & 0x3F);
        final byte3 = 0x80 | ((codePoint >> 12) & 0x3F);
        final byte4 = 0x80 | ((codePoint >> 6) & 0x3F);
        final byte5 = 0x80 | (codePoint & 0x3F);
        return [byte1, byte2, byte3, byte4, byte5];
      } else if (codePoint <= 0x7FFFFFFF) {
        // 6-byte sequence (original UTF-8 specification)
        final byte1 = 0xFC | ((codePoint >> 30) & 0x01);
        final byte2 = 0x80 | ((codePoint >> 24) & 0x3F);
        final byte3 = 0x80 | ((codePoint >> 18) & 0x3F);
        final byte4 = 0x80 | ((codePoint >> 12) & 0x3F);
        final byte5 = 0x80 | ((codePoint >> 6) & 0x3F);
        final byte6 = 0x80 | (codePoint & 0x3F);
        return [byte1, byte2, byte3, byte4, byte5, byte6];
      } else {
        // Extremely large codepoints - use clearly invalid bytes
        return [0xFF, 0xFF, 0xFF, 0xFF];
      }
    } else {
      // Other invalid cases - use clearly invalid byte
      return [0xFF];
    }
  }

  static Parser<List<int>> build() {
    // Helper parsers for different escape sequences
    final escapeChar = char('\\');

    // Basic escape sequences that map to specific characters
    final basicEscapes = [
      (char('a'), 7), // Bell
      (char('b'), 8), // Backspace
      (char('f'), 12), // Form feed
      (char('n'), 10), // Newline
      (char('r'), 13), // Carriage return
      (char('t'), 9), // Tab
      (char('v'), 11), // Vertical tab
      (char('"'), 34), // Double quote
      (char("'"), 39), // Single quote
      (char('\\'), 92), // Backslash
    ];

    // Special case: backslash followed by literal newline should be treated as just newline
    final backslashNewline = (escapeChar & char('\n')).map((_) => 10);

    final basicEscape = basicEscapes
        .map((e) => (escapeChar & e.$1).map((_) => e.$2))
        .toChoiceParser();

    // Decimal escape sequence: \ddd (1-3 decimal digits only)
    final decimalEscape =
        (escapeChar &
                (digit() & digit().optional() & digit().optional()).flatten())
            .map((parts) {
              final digits = parts[1] as String;
              final value = int.parse(digits);
              if (value > 255) {
                throw FormatException(
                  'Decimal escape \\$digits out of range (0-255)',
                );
              }
              return value;
            });

    // Hexadecimal escape sequence: \xXX (exactly 2 hex digits)
    final hexEscape =
        (escapeChar & char('x') & pattern('0-9a-fA-F').times(2).flatten()).map((
          parts,
        ) {
          final hex = parts[2] as String;
          return int.parse(hex, radix: 16);
        });

    // Unicode escape sequence: \u{XXX} (1+ hex digits in braces)
    final unicodeEscape =
        (escapeChar &
                char('u') &
                char('{') &
                pattern('0-9a-fA-F').plus().flatten() &
                char('}'))
            .map((parts) {
              final hex = parts[3] as String;
              final codePoint = int.parse(hex, radix: 16);

              // Allow invalid Unicode code points in string literals
              // The UTF-8 library functions will handle validation
              if (codePoint <= 0x10FFFF &&
                  !(codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
                // Valid Unicode code point - encode as UTF-8
                final str = String.fromCharCode(codePoint);
                return utf8.encode(str);
              } else {
                // Invalid Unicode code point (including surrogates) - store as raw bytes
                // This will be detected by UTF-8 functions as invalid
                return _encodeInvalidCodePoint(codePoint);
              }
            })
            .cast<List<int>>();

    // Line continuation: \z (skip following whitespace)
    // This should consume ALL whitespace including spaces, tabs, newlines, etc.
    final lineContinuation =
        (escapeChar & char('z') & pattern(' \t\r\n').star()).map(
          (_) => <int>[],
        ); // Returns empty list of bytes

    // Fallback for unrecognized escape sequences: treat as literal backslash + character
    final fallbackEscape = (escapeChar & any()).map((parts) {
      final char = parts[1] as String;
      // Return literal backslash (92) followed by the character's bytes
      final result = <int>[92]; // backslash
      result.addAll(char.codeUnits);
      return result;
    }).cast<List<int>>();

    // Any escape sequence
    final anyEscape = [
      backslashNewline.map((byte) => [byte]), // Handle \<newline> first
      basicEscape.map((byte) => [byte]),
      hexEscape.map((byte) => [byte]),
      decimalEscape.map((byte) => [byte]),
      unicodeEscape,
      lineContinuation,
      fallbackEscape, // This should be last to catch unrecognized escapes
    ].toChoiceParser().cast<List<int>>();

    // Regular character (not backslash)
    final regularChar = pattern(
      '^\\\\',
    ).plus().flatten().map((chars) => chars.codeUnits).cast<List<int>>();

    // String content: sequence of escape sequences or regular characters
    final stringContent = (anyEscape | regularChar).star().map(
      (parts) => parts.expand<int>((part) => part as List<int>).toList(),
    );

    return stringContent;
  }

  /// Parse a Lua string literal content and return the resulting bytes
  static List<int> parseStringContent(String content) {
    final parser = build();
    final result = parser.parse(content);

    if (result is Success) {
      return result.value;
    } else {
      throw FormatException('Failed to parse Lua string: ${result.toString()}');
    }
  }
}
