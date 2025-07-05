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
  static Parser<String> get precision => (char('.') & digit().plus()).flatten();
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
    for (final code in bytes) {
      if (code == 34) {
        // "
        buffer.write(r'\"');
      } else if (code == 92) {
        // \
        buffer.write(r'\\');
      } else if (code == 10) {
        // \n - escape as backslash followed by actual newline (Lua format)
        buffer.write('\\\n');
      } else if (code == 13) {
        // \r
        buffer.write(r'\r');
      } else if (code == 9) {
        // \t
        buffer.write(r'\t');
      } else if (code == 7) {
        // \a (bell)
        buffer.write(r'\a');
      } else if (code == 8) {
        // \b (backspace)
        buffer.write(r'\b');
      } else if (code == 11) {
        // \v (vertical tab)
        buffer.write(r'\v');
      } else if (code == 12) {
        // \f (form feed)
        buffer.write(r'\f');
      } else if (code == 0) {
        // null byte - special case
        buffer.write(r'\0');
      } else if (code >= 32 && code <= 126) {
        // Printable ASCII characters
        buffer.writeCharCode(code);
      } else if (code >= 128 && code <= 255) {
        // Extended ASCII - don't escape, keep as raw bytes (Lua behavior)
        buffer.writeCharCode(code);
      } else {
        // Other control characters (1-31, 127) - pad to 3 digits
        buffer.write('\\${code.toString().padLeft(3, '0')}');
      }
    }
    return buffer.toString();
  }
}
