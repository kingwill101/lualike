import 'dart:convert' as convert;

import 'package:petitparser/petitparser.dart';

/// Internal helper result for UTF-8 decode routines.
class Utf8DecodeResult {
  final int codePoint;
  final int sequenceLength;

  const Utf8DecodeResult(this.codePoint, this.sequenceLength);
}

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

    // Special case: backslash followed by a line break continues the string.
    // Accept any platform newline and normalize to '\n' (LF).
    // Match multi-char sequences before single-char ones.
    final backslashCRLF = (escapeChar & char('\r') & char('\n')).map((_) => 10);
    final backslashLFCR = (escapeChar & char('\n') & char('\r')).map((_) => 10);
    final backslashCR = (escapeChar & char('\r')).map((_) => 10);
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
                throw FormatException('decimal escape too large');
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

    // Incomplete hexadecimal escape: \x with exactly 0 or 1 hex digits followed by non-hex or end
    final incompleteHexEscape =
        (escapeChar &
                char('x') &
                (pattern('0-9a-fA-F').times(1).flatten() & endOfInput()))
            .map<List<int>>((parts) {
              throw FormatException('hexadecimal digit expected|incomplete');
            });

    // Invalid hex escape with 0 digits: \x followed immediately by non-hex character
    final invalidHexEscape0 = (escapeChar & char('x') & pattern('^0-9a-fA-F'))
        .map<List<int>>((parts) {
          throw FormatException('hexadecimal digit expected|invalid');
        });

    // Invalid hex escape with 1 digit: \x followed by 1 hex digit and 1 non-hex character
    final invalidHexEscape1 =
        (escapeChar &
                char('x') &
                pattern('0-9a-fA-F').times(1).flatten() &
                pattern('^0-9a-fA-F'))
            .map<List<int>>((parts) {
              throw FormatException('hexadecimal digit expected|invalid');
            });

    // Incomplete hex escape at end: \x with exactly 1 hex digit at end of input
    final incompleteHexEscapeEnd =
        (escapeChar &
                char('x') &
                pattern('0-9a-fA-F').times(1).flatten() &
                endOfInput())
            .map<List<int>>((parts) {
              throw FormatException('hexadecimal digit expected|incomplete');
            });

    // Incomplete hex escape with no digits at end: \x at end of input
    final incompleteHexEscapeNoDigits = (escapeChar & char('x') & endOfInput())
        .map<List<int>>((parts) {
          throw FormatException('hexadecimal digit expected|incomplete');
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

              // Check if the code point is too large even for Lua's extended UTF-8
              if (codePoint > 0x7FFFFFFF) {
                // Include the hex digits for error context
                final context = 'u{$hex';
                throw FormatException('UTF-8 value too large|context:$context');
              }

              // Use the extended UTF-8 encoding that supports Lua's historical sequences
              // This includes 5-byte and 6-byte sequences for code points up to 0x7FFFFFFF
              return encodeCodePoint(codePoint);
            })
            .cast<List<int>>();

    // Line continuation: \z (skip following whitespace)
    // This should consume ALL whitespace including spaces, tabs, newlines, form feed, vertical tab, etc.
    final lineContinuation =
        (escapeChar & char('z') & pattern(' \t\r\n\f\v').star()).map(
          (_) => <int>[],
        ); // Returns empty list of bytes

    // Invalid escape sequences for letters that are not valid escape characters
    // Remove 'u' from this pattern since we handle \u separately
    final invalidEscape =
        (escapeChar & pattern('cdeghijklmopqswyCDEFGHIJKLMOPQSWY'))
            .map<List<int>>((parts) {
              final char = parts[1] as String;
              throw FormatException('invalid escape sequence near "\\$char"');
            });

    // Invalid \u escape sequences - these need to come before invalidEscape
    // \u followed by hex digits but no opening brace: \u11r -> missing '{'
    final invalidUnicodeNoOpenBrace =
        (escapeChar & char('u') & pattern('0-9a-fA-F').plus().flatten())
            .map<List<int>>((parts) {
              final hex = parts[2] as String;
              // Truncate to just the first digit to match Lua's behavior
              final firstDigit = hex.isNotEmpty ? hex[0] : '';
              final context = 'u$firstDigit';
              throw FormatException('missing \'{\' near|context:$context');
            });

    // Invalid \u escape sequence - just \u followed by non-hex/non-brace
    final invalidUnicodeNoBrace =
        (escapeChar & char('u') & pattern('^{0-9a-fA-F').plus().flatten())
            .map<List<int>>((parts) {
              final following = parts[2] as String;
              final context = 'u$following';
              throw FormatException('missing \'{\' near|context:$context');
            });

    // Invalid \u escape sequence - just \u at end
    final invalidUnicodeAtEnd = (escapeChar & char('u') & endOfInput())
        .map<List<int>>((parts) {
          final context = 'u"';
          throw FormatException('missing \'{\' near|context:$context');
        });

    // Invalid \u{ escape sequences - missing closing brace with non-hex content
    final invalidUnicodeNoCloseBraceNonHex =
        (escapeChar &
                char('u') &
                char('{') &
                (pattern('0-9a-fA-F').star() & pattern('^}0-9a-fA-F').plus())
                    .flatten())
            .map<List<int>>((parts) {
              final content = parts[3] as String;
              final context = 'u{$content';
              throw FormatException('missing \'}\' near|context:$context');
            });

    // Invalid \u{ escape sequences - missing closing brace at end of input
    final invalidUnicodeNoCloseBraceEnd =
        (escapeChar &
                char('u') &
                char('{') &
                pattern('0-9a-fA-F').star().flatten() &
                endOfInput())
            .map<List<int>>((parts) {
              final content = parts[3] as String;
              final context =
                  'u{$content"'; // Include the full context with quote
              throw FormatException('missing \'}\' near|context:$context');
            });

    // Invalid \u{ escape sequences - no hex digits, just non-hex
    final invalidUnicodeNoDigits =
        (escapeChar &
                char('u') &
                char('{') &
                pattern('^}0-9a-fA-F').plus().flatten())
            .map<List<int>>((parts) {
              final content = parts[3] as String;
              final context = 'u{$content';
              throw FormatException(
                'hexadecimal digit expected near|context:$context',
              );
            });

    // Fallback for unrecognized escape sequences - also invalid
    final fallbackEscape = (escapeChar & any()).map<List<int>>((parts) {
      final char = parts[1] as String;
      throw FormatException('invalid escape sequence near "\\$char"');
    });

    final anyEscape =
        [
              // Handle backslash + newline first (normalized to LF)
              backslashCRLF.map((byte) => [byte]),
              backslashLFCR.map((byte) => [byte]),
              backslashCR.map((byte) => [byte]),
              backslashNewline.map((byte) => [byte]),
              basicEscape.map((byte) => [byte]),
              hexEscape.map((byte) => [byte]), // Try valid hex escape first
              invalidHexEscape1.map(
                (byte) => [byte],
              ), // Invalid hex with 1 digit + non-hex
              invalidHexEscape0.map(
                (byte) => [byte],
              ), // Invalid hex with 0 digits + non-hex
              incompleteHexEscapeEnd.map(
                (byte) => [byte],
              ), // Incomplete hex with 1 digit at end
              incompleteHexEscapeNoDigits.map(
                (byte) => [byte],
              ), // Incomplete hex with 0 digits at end
              incompleteHexEscape.map(
                (byte) => [byte],
              ), // General incomplete case
              decimalEscape.map((byte) => [byte]),
              unicodeEscape, // Valid \u{...} sequences
              lineContinuation,
              // Invalid \u sequences - these must come before invalidEscape
              invalidUnicodeNoOpenBrace, // \u followed by hex digits but no {
              invalidUnicodeNoBrace, // \u followed by non-hex/non-brace
              invalidUnicodeAtEnd, // \u at end of input
              invalidUnicodeNoCloseBraceNonHex, // \u{ with content but missing }
              invalidUnicodeNoCloseBraceEnd, // \u{ at end of input
              invalidUnicodeNoDigits, // \u{ with no hex digits
              invalidEscape, // Handle other invalid escapes
              fallbackEscape, // This should be last to catch unrecognized escapes
            ]
            .toChoiceParser()
            .cast<
              List<int>
            >(); // Regular character (not backslash). We need to handle UTF-8 characters properly
    // while preserving escape sequences. The key insight is that escape sequences
    // should always produce their exact byte values, while real UTF-8 characters
    // should be UTF-8 encoded.

    // Regular character that is not a backslash and not a raw newline.
    // Raw newlines inside short strings are not allowed in Lua; they must be
    // consumed by an escape (e.g., \\\n or via \\z continuation).
    final regularChar = pattern('^\\\\\r\n').plus().flatten().map((chars) {
      final result = <int>[];

      // Process each character individually to handle mixed content correctly
      for (final char in chars.runes) {
        if (char <= 0x7F) {
          // ASCII character - always single byte
          result.add(char);
        } else {
          // All non-ASCII characters should be properly UTF-8 encoded
          // This includes characters in the 128-255 range that represent
          // actual Unicode characters from the source file
          final utf8Bytes = convert.utf8.encode(String.fromCharCode(char));
          result.addAll(utf8Bytes);
        }
      }

      return result;
    }).cast<List<int>>();

    // String content: sequence of escape sequences or regular characters
    final stringContent = (anyEscape | regularChar).star().map(
      (parts) => parts.expand<int>((part) => part as List<int>).toList(),
    );

    return stringContent;
  }

  /// Parse a Lua string literal content and return the resulting bytes
  static List<int> parseStringContent(String content) {
    // Normalize \xHH (hex escapes) to decimal escapes (\ddd) so that
    // downstream parsing always sees a single uniform form for byte escapes.
    final hexRe = RegExp(r'\\x([0-9A-Fa-f]{2})');
    final normalized = content.replaceAllMapped(hexRe, (m) {
      final v = int.parse(m.group(1)!, radix: 16);
      return '\\$v';
    });

    final result = build().end().parse(normalized);

    if (result is Success) {
      return result.value;
    } else {
      // If the raw content contains a newline and we failed to parse,
      // this is most likely an unfinished short string. Report it in
      // Lua style so higher layers can surface the right message.
      if (content.contains('\n') || content.contains('\r')) {
        throw const FormatException(
          "[string \"\"]:1: unfinished string near '<eof>'",
        );
      }
      throw FormatException('Failed to parse Lua string: ${result.toString()}');
    }
  }

  // ************************************************************
  // Added UTF-8 helpers for stdlib/utf8.dart so everything lives
  // in one place (requested by user)
  // ************************************************************

  /// Encodes a single Unicode [codePoint] to UTF-8 bytes.
  /// Supports the historical 5- and 6-byte forms that Lua still
  /// recognises for code points up to 0x7FFFFFFF.
  static List<int> encodeCodePoint(int codePoint) {
    if (codePoint < 0) {
      throw RangeError('Negative code points are not allowed');
    }

    if (codePoint <= 0x7F) {
      return [codePoint];
    } else if (codePoint <= 0x7FF) {
      return [0xC0 | (codePoint >> 6), 0x80 | (codePoint & 0x3F)];
    } else if (codePoint <= 0xFFFF) {
      return [
        0xE0 | (codePoint >> 12),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    } else if (codePoint <= 0x1FFFFF) {
      return [
        0xF0 | (codePoint >> 18),
        0x80 | ((codePoint >> 12) & 0x3F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    } else if (codePoint <= 0x3FFFFFF) {
      return [
        0xF8 | (codePoint >> 24),
        0x80 | ((codePoint >> 18) & 0x3F),
        0x80 | ((codePoint >> 12) & 0x3F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    } else if (codePoint <= 0x7FFFFFFF) {
      return [
        0xFC | (codePoint >> 30),
        0x80 | ((codePoint >> 24) & 0x3F),
        0x80 | ((codePoint >> 18) & 0x3F),
        0x80 | ((codePoint >> 12) & 0x3F),
        0x80 | ((codePoint >> 6) & 0x3F),
        0x80 | (codePoint & 0x3F),
      ];
    }

    // Anything above 0x7FFFFFFF – fallback to clearly invalid bytes so
    // the UTF-8 library can flag an error later.
    return _encodeInvalidCodePoint(codePoint);
  }

  /// Decodes one UTF-8 character starting at byte position [start].
  /// Returns `null` if the sequence is invalid (unless [lax] is true).
  static Utf8DecodeResult? decodeUtf8Character(
    List<int> bytes,
    int start, {
    bool lax = false,
  }) {
    if (start >= bytes.length) return null;

    int first = bytes[start];

    // Single-byte (ASCII)
    if (first <= 0x7F) {
      return Utf8DecodeResult(first, 1);
    }

    // Helper to validate continuation bytes
    bool isContinuation(int byte) => (byte & 0xC0) == 0x80;

    int needed = 0;
    int codePoint = 0;

    if (first >= 0xC2 && first <= 0xDF) {
      needed = 1;
      codePoint = first & 0x1F;
    } else if (first >= 0xE0 && first <= 0xEF) {
      needed = 2;
      codePoint = first & 0x0F;
    } else if (first >= 0xF0 && first <= (lax ? 0xF7 : 0xF4)) {
      // Standard UTF-8 allows first byte up to 0xF4. In lax mode, Lua still
      // accepts the historical values 0xF5–0xF7 for 4-byte sequences that
      // encode code points larger than 0x10FFFF (up to 0x1FFFFF).
      needed = 3;
      codePoint = first & 0x07;
    } else if (first >= 0xF8 && first <= 0xFB) {
      needed = 4;
      codePoint = first & 0x03;
    } else if (first >= 0xFC && first <= 0xFD) {
      needed = 5;
      codePoint = first & 0x01;
    } else {
      // Illegal first byte
      return null;
    }

    if (start + needed >= bytes.length) return null; // not enough bytes

    for (int i = 1; i <= needed; i++) {
      int byte = bytes[start + i];
      if (!isContinuation(byte)) return null;
      codePoint = (codePoint << 6) | (byte & 0x3F);
    }

    int sequenceLength = needed + 1;

    // Reject over-long encodings and surrogate range if not in lax mode
    if (!lax) {
      if (sequenceLength == 2 && codePoint <= 0x7F) return null;
      if (sequenceLength == 3 && codePoint <= 0x7FF) return null;
      if (sequenceLength == 4 && codePoint <= 0xFFFF) return null;
      if (sequenceLength == 5 && codePoint <= 0x1FFFFF) return null;
      if (sequenceLength == 6 && codePoint <= 0x3FFFFFF) return null;
      if (codePoint >= 0xD800 && codePoint <= 0xDFFF) return null; // surrogates
      if (sequenceLength > 4) {
        return null; // standard UTF-8 max 4 bytes in strict mode
      }
      if (codePoint > 0x10FFFF) return null; // outside Unicode range
      if (codePoint > 0x7FFFFFFF) return null;
    }

    return Utf8DecodeResult(codePoint, sequenceLength);
  }
}
