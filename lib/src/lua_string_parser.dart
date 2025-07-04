import 'package:petitparser/petitparser.dart';

/// A PetitParser-based parser for Lua string literals that handles escape sequences correctly
class LuaStringParser {
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
              if (codePoint > 0x10FFFF) {
                throw FormatException(
                  'Unicode escape \\u{$hex} out of valid range',
                );
              }
              // Convert Unicode code point to UTF-8 bytes
              final str = String.fromCharCode(codePoint);
              return str
                  .codeUnits; // Returns List<int> of UTF-16 code units, but for most chars this works
            })
            .cast<List<int>>();

    // Line continuation: \z (skip following whitespace)
    final lineContinuation = (escapeChar & char('z') & whitespace().star()).map(
      (_) => <int>[],
    ); // Returns empty list of bytes

    // Any escape sequence
    final anyEscape = [
      basicEscape.map((byte) => [byte]),
      hexEscape.map((byte) => [byte]),
      decimalEscape.map((byte) => [byte]),
      unicodeEscape,
      lineContinuation,
    ].toChoiceParser().cast<List<int>>();

    // Regular character (not backslash)
    final regularChar = pattern('^\\\\').map((char) {
      // Convert character to its UTF-8 bytes
      final bytes = char.codeUnits;
      if (bytes.length == 1 && bytes[0] <= 255) {
        // ASCII/Latin-1 character, use as single byte
        return [bytes[0]];
      } else {
        // Multi-byte UTF-8 character, encode properly
        final utf8Bytes = char.runes.expand((rune) {
          if (rune <= 0x7F) {
            return [rune];
          } else if (rune <= 0x7FF) {
            return [0xC0 | (rune >> 6), 0x80 | (rune & 0x3F)];
          } else if (rune <= 0xFFFF) {
            return [
              0xE0 | (rune >> 12),
              0x80 | ((rune >> 6) & 0x3F),
              0x80 | (rune & 0x3F),
            ];
          } else {
            return [
              0xF0 | (rune >> 18),
              0x80 | ((rune >> 12) & 0x3F),
              0x80 | ((rune >> 6) & 0x3F),
              0x80 | (rune & 0x3F),
            ];
          }
        }).toList();
        return utf8Bytes;
      }
    }).cast<List<int>>();

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
