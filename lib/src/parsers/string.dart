import 'dart:convert' as convert;

import 'package:petitparser/petitparser.dart';
import '../lua_error.dart';

/// Internal helper result for UTF-8 decode routines.
class Utf8DecodeResult {
  final int codePoint;
  final int sequenceLength;
  const Utf8DecodeResult(this.codePoint, this.sequenceLength);
}

/// Error context information for string parsing errors
class _ErrorContext {
  final String fullLexeme;
  final int errorPosition;
  final String errorSequence;

  const _ErrorContext(this.fullLexeme, this.errorPosition, this.errorSequence);

  /// Find the opening quote position in the full lexeme
  int? get openingQuotePosition {
    final doubleQuotePos = fullLexeme.indexOf('"');
    final singleQuotePos = fullLexeme.indexOf("'");

    if (doubleQuotePos == -1 && singleQuotePos == -1) return null;
    if (doubleQuotePos == -1) return singleQuotePos;
    if (singleQuotePos == -1) return doubleQuotePos;

    return doubleQuotePos < singleQuotePos ? doubleQuotePos : singleQuotePos;
  }

  /// Find the closing quote position in the full lexeme
  int? get closingQuotePosition {
    final openingPos = openingQuotePosition;
    if (openingPos == null) return null;

    final quote = fullLexeme[openingPos];
    final closingPos = fullLexeme.indexOf(quote, openingPos + 1);
    return closingPos == -1 ? null : closingPos;
  }

  /// Format error context for "near" portion of error message
  String formatNearContext({
    bool includeOpeningQuote = true,
    bool includeClosingQuote = false,
    bool onlyEscapeSequence = false,
  }) {
    final openingPos = openingQuotePosition;

    if (openingPos == null || onlyEscapeSequence) {
      // No quotes found or only want escape sequence, return the error sequence
      return errorSequence;
    }

    // Determine start position
    int startPos;
    if (includeOpeningQuote) {
      startPos = openingPos;
    } else {
      // Start after the opening quote
      startPos = openingPos + 1;
    }

    int endPos = errorPosition + errorSequence.length;

    // Include closing quote if requested and present
    if (includeClosingQuote) {
      final closingPos = closingQuotePosition;
      if (closingPos != null && closingPos >= endPos) {
        endPos = closingPos + 1;
      }
    }

    // Ensure we don't go beyond the lexeme bounds
    endPos = endPos.clamp(0, fullLexeme.length);
    startPos = startPos.clamp(0, fullLexeme.length);

    return fullLexeme.substring(startPos, endPos);
  }
}

/// Helper functions for error context extraction
class _StringErrorHelper {
  /// Find the position of an escape sequence in the full lexeme
  static int findEscapePosition(String fullLexeme, String escapeSequence) {
    return fullLexeme.indexOf(escapeSequence);
  }

  /// Create error context for escape sequence errors
  static _ErrorContext createEscapeContext(
    String? fullLexeme,
    String escapeSequence,
  ) {
    if (fullLexeme == null) {
      return _ErrorContext(escapeSequence, 0, escapeSequence);
    }

    final position = findEscapePosition(fullLexeme, escapeSequence);
    if (position == -1) {
      // Fallback if sequence not found
      return _ErrorContext(fullLexeme, fullLexeme.length, escapeSequence);
    }

    return _ErrorContext(fullLexeme, position, escapeSequence);
  }

  /// Format error message with proper context
  static String formatErrorMessage(
    String message,
    _ErrorContext context, {
    bool includeClosingQuote = false,
  }) {
    final nearContext = context.formatNearContext(
      includeClosingQuote: includeClosingQuote,
    );
    return "$message near '$nearContext'";
  }
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

  static Parser<List<int>> build({String? fullLexeme}) {
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
                final escapeSequence = '\\$digits';
                final context = _StringErrorHelper.createEscapeContext(
                  fullLexeme,
                  escapeSequence,
                );
                final nearContext = context.formatNearContext(
                  includeClosingQuote: true,
                );
                throw LuaError("decimal escape too large near '$nearContext'");
              }
              return value;
            });

    // Invalid hexadecimal escapes like \xG or incomplete like \x5 (but not \x at end)
    final invalidHexEscape = (escapeChar & char('x') & any() & any().optional()).map((
      parts,
    ) {
      final first = parts[2] as String;
      final second = parts[3] as String? ?? '';

      // Check if both characters are valid hex digits
      final firstIsHex = '0123456789abcdefABCDEF'.contains(first);
      final secondIsHex =
          second.isEmpty || '0123456789abcdefABCDEF'.contains(second);

      final escapeSequence = '\\x$first$second';
      final context = _StringErrorHelper.createEscapeContext(
        fullLexeme,
        escapeSequence,
      );

      // For hex escape errors, determine context based on the type of error
      String nearContext;
      if (firstIsHex && second.isEmpty) {
        // Incomplete hex sequence like \x5 at end of string - include closing quote
        if (fullLexeme != null && context.closingQuotePosition != null) {
          nearContext =
              '\\x$first' + fullLexeme![context.closingQuotePosition!];
        } else {
          nearContext = '\\x$first';
        }
      } else if (firstIsHex && !secondIsHex && second.isNotEmpty) {
        // First char is hex, second is not hex (like \x5g) - show only the sequence
        nearContext = '\\x$first$second';
      } else {
        // Invalid hex character (like \xr) - show only the escape sequence
        nearContext = escapeSequence;
      }

      throw LuaError("hexadecimal digit expected near '$nearContext'");
    });

    // Hex escape at end of string (no hex digits after \x)
    final hexEscapeAtEnd = (escapeChar & char('x')).map((_) {
      final escapeSequence = '\\x';
      final context = _StringErrorHelper.createEscapeContext(
        fullLexeme,
        escapeSequence,
      );

      // For hex escape at end, include closing quote if present
      String nearContext;
      if (fullLexeme != null && context.closingQuotePosition != null) {
        nearContext =
            escapeSequence + fullLexeme![context.closingQuotePosition!];
      } else {
        nearContext = escapeSequence;
      }
      throw LuaError("hexadecimal digit expected near '$nearContext'");
    }).cast<List<int>>();

    // Hexadecimal escape sequence: \xXX (exactly 2 hex digits)
    final hexEscape =
        (escapeChar & char('x') & pattern('0-9a-fA-F').times(2).flatten()).map((
          parts,
        ) {
          final hex = parts[2] as String;
          return int.parse(hex, radix: 16);
        });

    final unicodeStart = escapeChar & char('u');

    // Unicode escape sequence: \u{XXX} (1+ hex digits in braces)
    final unicodeEscape =
        (unicodeStart &
                char('{') &
                pattern('0-9a-fA-F').plus().flatten() &
                char('}'))
            .map((parts) {
              final hex = parts[3] as String;
              final codePoint = int.parse(hex, radix: 16);

              // Lua accepts historical UTF-8 encodings up to six bytes long,
              // which correspond to code points as large as 0x7FFFFFFF.
              // Values beyond that are treated as errors.
              if (codePoint > 0x7FFFFFFF) {
                final escapeSequence = '\\u{$hex';
                final context = _StringErrorHelper.createEscapeContext(
                  fullLexeme,
                  escapeSequence,
                );
                final nearContext = context.formatNearContext(
                  includeOpeningQuote: true,
                );
                throw LuaError("UTF-8 value too large near '$nearContext'");
              }

              // For surrogate code points and other invalid code points,
              // use the special encoding method that produces the expected
              // byte sequences that Lua generates
              if (codePoint >= 0xD800 && codePoint <= 0xDFFF ||
                  codePoint > 0x10FFFF) {
                return _encodeInvalidCodePoint(codePoint);
              }

              // Encode the code point directly. `String.fromCharCode` only
              // supports values up to 0x10FFFF.
              return encodeCodePoint(codePoint);
            })
            .cast<List<int>>();

    final unicodeMissingOpen =
        (unicodeStart & char('{').not() & any().optional()).map((parts) {
          final firstChar = parts[3] is String ? parts[3] as String : '';
          // For missing '{' errors, we need to show context up to the error point
          final actualSequence = '\\u$firstChar';

          // Use standard context formatting
          final context = _StringErrorHelper.createEscapeContext(
            fullLexeme,
            actualSequence,
          );
          final nearContext = context.formatNearContext(
            includeOpeningQuote: true,
            includeClosingQuote: firstChar.isEmpty,
          );
          throw LuaError("missing '{' near '$nearContext'");
        }).cast<List<int>>();

    // Unicode escape with { but no hex digits like \u{r
    final unicodeInvalidHex =
        (unicodeStart &
                char('{') &
                pattern('0-9a-fA-F').not() &
                any().optional())
            .map((parts) {
              final invalid = parts[2] is String ? parts[2] as String : '';
              final next = parts[3] is String ? parts[3] as String : '';
              final escapeSequence = '\\u{$invalid$next';
              final context = _StringErrorHelper.createEscapeContext(
                fullLexeme,
                escapeSequence,
              );
              final nearContext = context.formatNearContext(
                includeOpeningQuote: true,
              );
              throw LuaError("hexadecimal digit expected near '$nearContext'");
            })
            .cast<List<int>>();

    final unicodeMissingClose =
        (unicodeStart &
                char('{') &
                pattern('0-9a-fA-F').plus().flatten() &
                any().optional())
            .map((parts) {
              final hex = parts[2] as String;
              final next = parts[3] is String ? parts[3] as String : '';
              // For missing closing brace, include the next character in the sequence
              final escapeSequence = '\\u{$hex$next';
              final context = _StringErrorHelper.createEscapeContext(
                fullLexeme,
                escapeSequence,
              );
              // Manually construct the context to match Lua's format
              final openingPos = context.openingQuotePosition;
              if (openingPos != null) {
                final startPos =
                    openingPos + 1; // Skip the opening quote for the pattern
                final endPos = context.errorPosition + escapeSequence.length;
                // For missing closing brace, exclude the closing quote if it's not part of the pattern
                final closingPos = context.closingQuotePosition;
                final actualEndPos = closingPos != null && closingPos < endPos
                    ? closingPos // Stop before the closing quote
                    : endPos.clamp(0, fullLexeme!.length);
                final nearContext = fullLexeme!.substring(
                  startPos,
                  actualEndPos,
                );
                throw LuaError("missing '}' near '$nearContext'");
              } else {
                final nearContext = context.formatNearContext(
                  includeOpeningQuote: true,
                );
                throw LuaError("missing '}' near '$nearContext'");
              }
            })
            .cast<List<int>>();

    // Line continuation: \z (skip following whitespace)
    // This should consume ALL whitespace including spaces, tabs, newlines, etc.
    final lineContinuation =
        (escapeChar & char('z') & pattern(' \t\r\n\f\v').star()).map(
          (_) => <int>[],
        ); // Returns empty list of bytes

    // Any other escape sequence is invalid
    final fallbackEscape = (escapeChar & any()).map((parts) {
      final char = parts[1] as String;
      final escapeSequence = '\\$char';
      final context = _StringErrorHelper.createEscapeContext(
        fullLexeme,
        escapeSequence,
      );
      final nearContext = context.formatNearContext(onlyEscapeSequence: true);
      throw LuaError("invalid escape sequence near '$nearContext'");
    }).cast<List<int>>();

    // Any escape sequence
    final anyEscape = [
      backslashNewline.map((byte) => [byte]), // Handle \<newline> first
      basicEscape.map((byte) => [byte]),
      hexEscape.map((byte) => [byte]),
      invalidHexEscape, // must come after valid hex escape
      hexEscapeAtEnd, // must come after invalidHexEscape
      decimalEscape.map((byte) => [byte]),
      unicodeEscape,
      unicodeMissingOpen,
      unicodeInvalidHex, // must come before unicodeMissingClose
      unicodeMissingClose,
      lineContinuation,
      fallbackEscape, // This should be last to catch unrecognized escapes
    ].toChoiceParser().cast<List<int>>();

    // Regular character (not backslash). We need to handle UTF-8 characters properly
    // while preserving escape sequences. The key insight is that escape sequences
    // should always produce their exact byte values, while real UTF-8 characters
    // should be UTF-8 encoded.

    final regularChar = pattern('^\\\\').plus().flatten().map((chars) {
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
  static List<int> parseStringContent(String content, {String? fullLexeme}) {
    final parser = build(fullLexeme: fullLexeme);
    final result = parser.parse(content);

    if (result is Success) {
      return result.value;
    } else {
      throw LuaError('Failed to parse Lua string: ${result.toString()}');
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
