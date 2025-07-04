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
              specifier: values[4] as String,
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
}
