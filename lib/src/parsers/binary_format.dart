import 'package:petitparser/petitparser.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/stdlib/binary_type_size.dart';

/// Represents a single directive inside a Lua 5.4 `string.pack` format.
class BinaryFormatOption {
  final String type; // e.g. 'i', 'c', 'z', '<', '!', …
  final int? size; // explicit size for options like i4, c10, etc.
  final int? align; // alignment for !n
  final String raw; // original text (useful for error reporting)

  BinaryFormatOption(this.type, {this.size, this.align, required this.raw});

  @override
  String toString() =>
      'BinaryFormatOption(type: $type, size: $size, align: $align, raw: "$raw")';
}

/// Parser that turns a Lua 5.4 binary-format string into a list of
/// [BinaryFormatOption]s, performing the same validation that the Lua VM does.
class BinaryFormatParser {
  static final Parser<String> space = char(' ');
  static final Parser<String> digits = digit().plus().flatten();
  static final Parser<String> signedDigits = (char('-').optional() & digits)
      .flatten();

  /// Endianness marks: `<  >  =`
  static final Parser<BinaryFormatOption> endiannessParser = pattern(
    '<>=',
  ).map((c) => BinaryFormatOption(c, raw: c));

  /// Alignment: `!n`  (n must be a power of two). A bare `!` resets to the
  /// default alignment.
  static final Parser<BinaryFormatOption> alignParser =
      (char('!') & digits.optional()).map((v) {
        final numStr = v[1] as String?;
        if (numStr == null) {
          return BinaryFormatOption('!', raw: '!');
        } else {
          final n = int.parse(numStr);
          if (n < 1 || n > 16) {
            throw LuaError("integral size ($n) out of limits [1,16]");
          }
          if ((n & (n - 1)) != 0) {
            throw LuaError("format asks for alignment not power of 2");
          }
          return BinaryFormatOption('!', align: n, raw: '!$numStr');
        }
      });

  /// `'cN'` – fixed-length char array, **size required**
  static final Parser<BinaryFormatOption> cParser = (char('c') & digits).map((
    v,
  ) {
    final n = int.parse(v[1]);
    if (n <= 0) {
      throw LuaError("invalid size for format option 'c'");
    }
    return BinaryFormatOption('c', size: n, raw: 'c${v[1]}');
  });

  /// bare 'c' without a size -> missing size error
  static final Parser<BinaryFormatOption> cParserMissing = char(
    'c',
  ).map((_) => throw LuaError('missing size'));

  /// `iN`, `IN`, `jN`, `JN`, `sN` – integer / size-prefixed string with explicit width
  static final Parser<BinaryFormatOption> iIParserWithNum =
      (pattern('iIjJs') & signedDigits).map((v) {
        final t = v[0] as String;
        final n = int.parse(v[1]);

        if ((t == 'i' || t == 'I' || t == 'j' || t == 'J') &&
            (n < 1 || n > 16)) {
          throw LuaError("integral size ($n) out of limits [1,16]");
        }
        if (t == 's' && n < 0) {
          throw LuaError("invalid size for format option 's'");
        }
        return BinaryFormatOption(t, size: n, raw: '$t${v[1]}');
      });

  /// a bare `'s'` (size-prefixed string with native integer size)
  static final Parser<BinaryFormatOption> sParserAlone = char(
    's',
  ).map((_) => BinaryFormatOption('s', raw: 's'));

  /// all simple one-byte options that never take a number
  /// (`i` and `s` are *omitted* here because they appear in other rules)
  static final Parser<BinaryFormatOption> simpleParser = pattern(
    'bBhHlLjJTdnisxzXfI',
  ).map((c) => BinaryFormatOption(c, raw: c));

  static final Parser<BinaryFormatOption> unknownParser = any().map(
    (c) => throw LuaError.typeError("invalid format option '$c'"),
  );

  static final Parser<BinaryFormatOption> optionParser =
      (iIParserWithNum |
              sParserAlone |
              cParser |
              cParserMissing |
              alignParser |
              endiannessParser |
              simpleParser |
              unknownParser // always keep last
              )
          .cast<BinaryFormatOption>();

  static final Parser<List<BinaryFormatOption>> formatParser =
      (space.star() &
              // 0-or-more pairs: <option> <trailing-spaces>
              (optionParser & space.star()).map((v) => v[0]).star() &
              space.star())
          .map((v) => List<BinaryFormatOption>.from(v[1]))
          .end();

  /// Parse [input] into a list of [BinaryFormatOption]s or throw [LuaError].
  static List<BinaryFormatOption> parse(String input) {
    final result = formatParser.parse(input);
    if (result is Success) {
      final raw = List<BinaryFormatOption>.from(result.value);
      final processed = <BinaryFormatOption>[];
      for (var i = 0; i < raw.length; i++) {
        final opt = raw[i];
        if (opt.type == 'X') {
          if (i + 1 >= raw.length) {
            throw LuaError("invalid next option for option 'X'");
          }
          final next = raw[i + 1];
          int size;
          switch (next.type) {
            case 'b':
              size = BinaryTypeSize.b;
              break;
            case 'B':
              size = BinaryTypeSize.B;
              break;
            case 'h':
              size = BinaryTypeSize.h;
              break;
            case 'H':
              size = BinaryTypeSize.H;
              break;
            case 'l':
              size = BinaryTypeSize.l;
              break;
            case 'L':
              size = BinaryTypeSize.L;
              break;
            case 'j':
              size = BinaryTypeSize.j;
              break;
            case 'J':
              size = BinaryTypeSize.J;
              break;
            case 'T':
              size = BinaryTypeSize.T;
              break;
            case 'f':
              size = BinaryTypeSize.f;
              break;
            case 'd':
              size = BinaryTypeSize.d;
              break;
            case 'n':
              size = BinaryTypeSize.n;
              break;
            case 'i':
              size = next.size ?? BinaryTypeSize.i;
              break;
            case 'I':
              size = next.size ?? BinaryTypeSize.I;
              break;
            default:
              throw LuaError(
                "'X' cannot align to non-alignable type '${next.type}'",
              );
          }
          processed.add(
            BinaryFormatOption('X', size: size, raw: opt.raw + next.raw),
          );
          i++; // skip next
        } else {
          processed.add(opt);
        }
      }
      return processed;
    }
    // Failure – PetitParser tells us where it got stuck.
    throw LuaError.typeError(
      "invalid format option at position ${result.position}",
    );
  }
}
