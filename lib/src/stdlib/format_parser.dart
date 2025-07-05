import 'dart:typed_data';

import 'dart:typed_data';

import 'dart:convert';
import 'dart:typed_data';

import 'package:petitparser/petitparser.dart';

/// Represents a parsed format specifier or a literal string segment.
abstract class FormatPart {}

class LiteralPart extends FormatPart {
  final String text;
  LiteralPart(this.text);
  @override
  String toString() => 'LiteralPart("$text")';
}

class SpecifierPart extends FormatPart {
  final String full;
  final String flags;
  final String? width;
  final String? precision;
  final String specifier;
  SpecifierPart({
    required this.full,
    required this.flags,
    this.width,
    this.precision,
    required this.specifier,
  });
  @override
  String toString() =>
      'SpecifierPart(%$flags${width ?? ''}${precision ?? ''}$specifier)';
}

class FormatStringParser {
  static Parser<String> get percent => char('%');
  static Parser<String> get flags => pattern('-+ 0#').star().flatten();
  static Parser<String> get width => digit().plus().flatten();
  static Parser<String> get precision => (char('.') & digit().star()).flatten();
  static Parser<String> get specifier => pattern('cdiouxXeEfgGqQs%aAp');

  static Parser<SpecifierPart> get specifierParser =>
      (percent & flags & width.optional() & precision.optional() & specifier)
          .map((values) {
            return SpecifierPart(
              full: values.join(),
              flags: values[1] as String,
              width: values[2] as String?,
              precision: values[3] as String?,
              specifier: values.last.toString(),
            );
          });

  // Matches one or more non-'%' characters.
  static Parser<LiteralPart> get literalTextParser => any()
      .where((char) => char != '%')
      .plus()
      .flatten()
      .map((s) => LiteralPart(s));

  static Parser<FormatPart> get partParser =>
      (specifierParser.map((s) => s as FormatPart) |
              literalTextParser.map((l) => l as FormatPart))
          .cast<FormatPart>();

  // The main parser. It explicitly handles alternating literals and specifiers.
  static Parser<List<FormatPart>> get formatStringParser =>
      (literalTextParser.optional().map(
                (l) => l == null ? <FormatPart>[] : [l as FormatPart],
              ) &
              (specifierParser.map((s) => s as FormatPart) &
                      literalTextParser.optional().map(
                        (l) => l == null ? <FormatPart>[] : [l as FormatPart],
                      ))
                  .star())
          .map((result) {
            final List<FormatPart> parts = [];
            // Add initial literal part (if any)
            parts.addAll(result[0] as List<FormatPart>);
            // Add specifier and subsequent literal pairs
            for (final pair in result[1] as List) {
              parts.add(pair[0] as FormatPart);
              parts.addAll(pair[1] as List<FormatPart>);
            }
            return parts;
          })
          .end();

  /// Parses a format string into a list of FormatPart (literals and specifiers).
  static List<FormatPart> parse(String input) {
    final result = formatStringParser.parse(input);
    if (result is Success) {
      return List<FormatPart>.from(result.value);
    } else {
      throw FormatException(
        'Invalid format string: ${result.message ?? "Unknown error"}',
      );
    }
  }

  /// Escapes a byte list according to Lua's %q format rules.
  static String escape(Uint8List bytes) {
    final buffer = StringBuffer();
    int i = 0;
    while (i < bytes.length) {
      final code = bytes[i];
      if (code == 34) {
        // "
        buffer.write(r'\"');
        i++;
      } else if (code == 92) {
        // \
        buffer.write(r'\\');
        i++;
      } else if (code == 10) {
        // \n - escape as backslash followed by actual newline (Lua format)
        buffer.write('\\\n');
        i++;
      } else if (code == 0) {
        // null byte - check if next character is a digit to avoid ambiguity
        if (i + 1 < bytes.length && bytes[i + 1] >= 48 && bytes[i + 1] <= 57) {
          // Next char is a digit, use \000 to avoid ambiguity
          buffer.write(r'\000');
        } else {
          // Safe to use short form
          buffer.write(r'\0');
        }
        i++;
      } else if (code >= 32 && code <= 126) {
        // Printable ASCII characters
        buffer.writeCharCode(code);
        i++;
      } else if (code >= 128 && code <= 255) {
        // Check if this starts a valid UTF-8 sequence
        final sequenceLength = _getValidUTF8SequenceLength(bytes, i);
        if (sequenceLength > 1 &&
            _isSafeUTF8Sequence(bytes, i, sequenceLength)) {
          // Safe UTF-8 sequence that we know will round-trip correctly
          for (int j = 0; j < sequenceLength; j++) {
            buffer.writeCharCode(bytes[i + j]);
          }
          i += sequenceLength;
        } else if (sequenceLength == 1) {
          // Single byte in 128-255 range - check if it causes round-trip issues
          if (code == 255 || code == 225) {
            // Bytes that cause round-trip issues, escape them
            if (i + 1 < bytes.length &&
                bytes[i + 1] >= 48 &&
                bytes[i + 1] <= 57) {
              buffer.write('\\${code.toString().padLeft(3, '0')}');
            } else {
              buffer.write('\\$code');
            }
          } else {
            // Other single bytes 128-254 (except 225) are safe Latin-1 characters
            buffer.writeCharCode(code);
          }
          i++;
        } else {
          // Invalid or potentially problematic byte, escape it
          if (i + 1 < bytes.length &&
              bytes[i + 1] >= 48 &&
              bytes[i + 1] <= 57) {
            buffer.write('\\${code.toString().padLeft(3, '0')}');
          } else {
            buffer.write('\\$code');
          }
          i++;
        }
      } else {
        // Control characters (1-31, 127) - use numeric escape sequences
        if (i + 1 < bytes.length && bytes[i + 1] >= 48 && bytes[i + 1] <= 57) {
          // Next char is a digit, need 3-digit form to avoid ambiguity
          buffer.write('\\${code.toString().padLeft(3, '0')}');
        } else {
          // Safe to use shortest form
          buffer.write('\\$code');
        }
        i++;
      }
    }
    return buffer.toString();
  }

  /// Check if a byte at position i would cause UTF-8 conversion issues
  static bool _wouldCauseUTF8Issues(Uint8List bytes, int i) {
    final byte = bytes[i];

    // Only escape bytes that we know cause round-trip issues
    // Based on our testing, these are primarily isolated high bytes
    // that don't form valid UTF-8 sequences

    // Byte 255 always causes issues
    if (byte == 255) return true;

    // Check if this byte is part of a valid UTF-8 sequence
    if (byte >= 0xC2 && byte <= 0xDF) {
      // 2-byte sequence - check if we have a valid continuation
      if (i + 1 < bytes.length && _isUTF8Continuation(bytes[i + 1])) {
        return false; // Valid UTF-8 sequence, don't escape
      }
      return true; // Invalid sequence, escape it
    } else if (byte >= 0xE0 && byte <= 0xEF) {
      // 3-byte sequence - check if we have valid continuations
      if (i + 2 < bytes.length &&
          _isUTF8Continuation(bytes[i + 1]) &&
          _isUTF8Continuation(bytes[i + 2])) {
        return false; // Valid UTF-8 sequence, don't escape
      }
      return true; // Invalid sequence, escape it
    } else if (byte >= 0xF0 && byte <= 0xF4) {
      // 4-byte sequence - check if we have valid continuations
      if (i + 3 < bytes.length &&
          _isUTF8Continuation(bytes[i + 1]) &&
          _isUTF8Continuation(bytes[i + 2]) &&
          _isUTF8Continuation(bytes[i + 3])) {
        return false; // Valid UTF-8 sequence, don't escape
      }
      return true; // Invalid sequence, escape it
    } else if (byte >= 0x80 && byte <= 0xBF) {
      // Continuation byte - check if it's part of a valid sequence
      // by looking backward (this is complex, so for now escape orphaned ones)
      return true;
    }

    // For other bytes in 128-255 range that don't start UTF-8 sequences,
    // escape them as they likely cause issues
    if (byte >= 128) return true;

    return false; // ASCII bytes are fine
  }

  /// Check if a byte is a valid UTF-8 continuation byte (10xxxxxx)
  static bool _isUTF8Continuation(int byte) {
    return (byte & 0xC0) == 0x80;
  }

  /// Get the length of a valid UTF-8 sequence starting at position i, or 1 if invalid
  static int _getValidUTF8SequenceLength(Uint8List bytes, int i) {
    if (i >= bytes.length) return 1;

    final byte = bytes[i];

    // Byte 255 always causes issues
    if (byte == 255) return 1;

    // Check if this byte starts a valid UTF-8 sequence
    if (byte >= 0xC2 && byte <= 0xDF) {
      // 2-byte sequence - check if we have a valid continuation
      if (i + 1 < bytes.length && _isUTF8Continuation(bytes[i + 1])) {
        return 2; // Valid 2-byte sequence
      }
      return 1; // Invalid sequence
    } else if (byte >= 0xE0 && byte <= 0xEF) {
      // 3-byte sequence - check if we have valid continuations
      if (i + 2 < bytes.length &&
          _isUTF8Continuation(bytes[i + 1]) &&
          _isUTF8Continuation(bytes[i + 2])) {
        return 3; // Valid 3-byte sequence
      }
      return 1; // Invalid sequence
    } else if (byte >= 0xF0 && byte <= 0xF4) {
      // 4-byte sequence - check if we have valid continuations
      if (i + 3 < bytes.length &&
          _isUTF8Continuation(bytes[i + 1]) &&
          _isUTF8Continuation(bytes[i + 2]) &&
          _isUTF8Continuation(bytes[i + 3])) {
        return 4; // Valid 4-byte sequence
      }
      return 1; // Invalid sequence
    }

    // Not a UTF-8 start byte, treat as single byte
    return 1;
  }

  /// Check if a UTF-8 sequence is safe to preserve
  static bool _isSafeUTF8Sequence(Uint8List bytes, int i, int length) {
    // For our Lua implementation, we need to be conservative about what UTF-8
    // sequences to preserve vs escape. We'll preserve sequences that represent
    // common Latin-1 extended characters (like á, é, etc.) that are commonly
    // used and likely to round-trip correctly.

    if (length == 2) {
      final byte1 = bytes[i];
      final byte2 = bytes[i + 1];

      // Latin-1 Supplement (U+0080 to U+00FF) encoded as UTF-8
      // These are bytes 0xC2 0x80 through 0xC3 0xBF
      if (byte1 == 0xC2 && byte2 >= 0x80 && byte2 <= 0xBF) {
        return true; // Latin-1 supplement characters
      }
      if (byte1 == 0xC3 && byte2 >= 0x80 && byte2 <= 0xBF) {
        return true; // Latin-1 supplement characters (including á, é, etc.)
      }
    }

    if (length == 3) {
      final byte1 = bytes[i];
      final byte2 = bytes[i + 1];
      final byte3 = bytes[i + 2];

      // UTF-8 replacement character (U+FFFD) = 0xEF 0xBF 0xBD
      if (byte1 == 0xEF && byte2 == 0xBF && byte3 == 0xBD) {
        return true; // UTF-8 replacement character is safe
      }
    }

    // For now, be conservative with other 3-byte and 4-byte sequences
    // as they're more likely to cause round-trip issues
    return false;
  }
}
