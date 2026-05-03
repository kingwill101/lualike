import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/binary_type_size.dart';
import 'package:petitparser/petitparser.dart';

import '../number_limits.dart';

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
    final numStr = v[1] as String;
    final bigN = BigInt.parse(numStr);
    if (bigN < BigInt.zero) {
      throw LuaError("invalid size for format option 'c'");
    }
    if (bigN > BigInt.from(NumberLimits.maxInteger)) {
      throw LuaError('invalid format');
    }
    return BinaryFormatOption('c', size: bigN.toInt(), raw: 'c$numStr');
  });

  /// bare 'c' without a size -> missing size error
  static final Parser<BinaryFormatOption> cParserMissing = char(
    'c',
  ).map((_) => throw LuaError('missing size'));

  /// `iN`, `IN`, `jN`, `JN`, `sN` – integer / size-prefixed string with explicit width
  static final Parser<BinaryFormatOption> iIParserWithNum =
      (pattern('iIjJs') & signedDigits).map((v) {
        final t = v[0] as String;
        final numStr = v[1] as String;
        final bigN = BigInt.parse(numStr);
        if (bigN > BigInt.from(NumberLimits.maxInteger) ||
            bigN < BigInt.from(NumberLimits.minInteger)) {
          throw LuaError('invalid format');
        }
        final n = bigN.toInt();

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
    final raw = <BinaryFormatOption>[];
    var current = 0;
    while (current < input.length) {
      final codeUnit = input.codeUnitAt(current);
      if (codeUnit == 0x20) {
        current++;
        continue;
      }

      if (codeUnit == 0x58) {
        if (current + 1 >= input.length || input[current + 1].trim().isEmpty) {
          throw LuaError("invalid next option for option 'X'");
        }
      }

      switch (codeUnit) {
        case 0x3C: // <
        case 0x3D: // =
        case 0x3E: // >
          final rawOption = input[current];
          raw.add(BinaryFormatOption(rawOption, raw: rawOption));
          current++;
          break;
        case 0x21: // !
          current = _parseAlignment(input, current, raw);
          break;
        case 0x63: // c
          current = _parseCharArray(input, current, raw);
          break;
        case 0x69: // i
        case 0x49: // I
        case 0x6A: // j
        case 0x4A: // J
        case 0x73: // s
          current = _parseIntegerOrStringSize(input, current, raw);
          break;
        default:
          final option = input[current];
          if (_isSimpleOption(codeUnit)) {
            raw.add(BinaryFormatOption(option, raw: option));
            current++;
          } else {
            throw LuaError.typeError("invalid format option '$option'");
          }
      }
    }

    final processed = <BinaryFormatOption>[];
    for (var i = 0; i < raw.length; i++) {
      final opt = raw[i];
      if (opt.type == 'X') {
        if (i + 1 >= raw.length) {
          throw LuaError("invalid next option for option 'X'");
        }
        final next = raw[i + 1];
        final size = _paddingSizeFor(next);
        processed.add(
          BinaryFormatOption('X', size: size, raw: opt.raw + next.raw),
        );
        i++;
      } else {
        processed.add(opt);
      }
    }
    return processed;
  }

  static int _parseAlignment(
    String input,
    int position,
    List<BinaryFormatOption> raw,
  ) {
    final digitStart = position + 1;
    final digitEnd = _scanDigits(input, digitStart);
    if (digitEnd == digitStart) {
      raw.add(BinaryFormatOption('!', raw: '!'));
      return digitStart;
    }

    final digits = input.substring(digitStart, digitEnd);
    final n = int.parse(digits);
    if (n < 1 || n > 16) {
      throw LuaError("integral size ($n) out of limits [1,16]");
    }
    if ((n & (n - 1)) != 0) {
      throw LuaError("format asks for alignment not power of 2");
    }
    raw.add(BinaryFormatOption('!', align: n, raw: '!$digits'));
    return digitEnd;
  }

  static int _parseCharArray(
    String input,
    int position,
    List<BinaryFormatOption> raw,
  ) {
    final digitStart = position + 1;
    final digitEnd = _scanDigits(input, digitStart);
    if (digitEnd == digitStart) {
      throw LuaError('missing size');
    }

    final digits = input.substring(digitStart, digitEnd);
    final bigN = BigInt.parse(digits);
    if (bigN > BigInt.from(NumberLimits.maxInteger)) {
      throw LuaError('invalid format');
    }
    raw.add(BinaryFormatOption('c', size: bigN.toInt(), raw: 'c$digits'));
    return digitEnd;
  }

  static int _parseIntegerOrStringSize(
    String input,
    int position,
    List<BinaryFormatOption> raw,
  ) {
    final type = input[position];
    final digitStart = _signedDigitsStart(input, position + 1);
    if (digitStart == null) {
      raw.add(BinaryFormatOption(type, raw: type));
      return position + 1;
    }

    final digitEnd = _scanDigits(input, digitStart);
    final numberStart = position + 1;
    final numberText = input.substring(numberStart, digitEnd);
    final bigN = BigInt.parse(numberText);
    if (bigN > BigInt.from(NumberLimits.maxInteger) ||
        bigN < BigInt.from(NumberLimits.minInteger)) {
      throw LuaError('invalid format');
    }

    final n = bigN.toInt();
    if ((type == 'i' || type == 'I' || type == 'j' || type == 'J') &&
        (n < 1 || n > 16)) {
      throw LuaError("integral size ($n) out of limits [1,16]");
    }
    if (type == 's' && n < 0) {
      throw LuaError("invalid size for format option 's'");
    }

    raw.add(BinaryFormatOption(type, size: n, raw: '$type$numberText'));
    return digitEnd;
  }

  static int? _signedDigitsStart(String input, int position) {
    if (position >= input.length) {
      return null;
    }
    final codeUnit = input.codeUnitAt(position);
    if (_isDigit(codeUnit)) {
      return position;
    }
    if (codeUnit == 0x2D &&
        position + 1 < input.length &&
        _isDigit(input.codeUnitAt(position + 1))) {
      return position + 1;
    }
    return null;
  }

  static int _scanDigits(String input, int position) {
    var current = position;
    while (current < input.length && _isDigit(input.codeUnitAt(current))) {
      current++;
    }
    return current;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  static bool _isSimpleOption(int codeUnit) {
    switch (codeUnit) {
      case 0x62: // b
      case 0x42: // B
      case 0x68: // h
      case 0x48: // H
      case 0x6C: // l
      case 0x4C: // L
      case 0x54: // T
      case 0x64: // d
      case 0x6E: // n
      case 0x78: // x
      case 0x7A: // z
      case 0x58: // X
      case 0x66: // f
        return true;
    }
    return false;
  }

  static int _paddingSizeFor(BinaryFormatOption option) {
    switch (option.type) {
      case 'b':
        return BinaryTypeSize.b;
      case 'B':
        return BinaryTypeSize.B;
      case 'h':
        return BinaryTypeSize.h;
      case 'H':
        return BinaryTypeSize.H;
      case 'l':
        return BinaryTypeSize.l;
      case 'L':
        return BinaryTypeSize.L;
      case 'j':
        return BinaryTypeSize.j;
      case 'J':
        return BinaryTypeSize.J;
      case 'T':
        return BinaryTypeSize.T;
      case 'f':
        return BinaryTypeSize.f;
      case 'd':
        return BinaryTypeSize.d;
      case 'n':
        return BinaryTypeSize.n;
      case 'i':
        return option.size ?? BinaryTypeSize.i;
      case 'I':
        return option.size ?? BinaryTypeSize.I;
    }
    throw LuaError("invalid next option for option 'X'");
  }
}
