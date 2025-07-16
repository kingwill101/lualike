import 'package:petitparser/petitparser.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/stdlib/binary_type_size.dart';
import 'package:lualike/src/stdlib/pack_size_calculator.dart';
import 'package:lualike/src/stdlib/pack_error_handling.dart';

/// Represents a single directive inside a Lua 5.4 `string.pack` format.
///
/// Each binary format option corresponds to one element in a format string,
/// such as 'i4' (4-byte integer), 'c10' (10-byte char array), or '!' (alignment reset).
///
/// The class encapsulates all the information needed to process the option:
/// - [type]: The option character ('i', 'c', 'z', '<', '!', etc.)
/// - [size]: Optional size parameter for sized options (e.g., 4 in 'i4')
/// - [align]: Optional alignment parameter for alignment options (e.g., 8 in '!8')
/// - [raw]: The original text from the format string for error reporting
///
/// Examples:
/// - 'i4' → BinaryFormatOption('i', size: 4, raw: 'i4')
/// - 'c10' → BinaryFormatOption('c', size: 10, raw: 'c10')
/// - '!8' → BinaryFormatOption('!', align: 8, raw: '!8')
/// - '<' → BinaryFormatOption('<', raw: '<')
class BinaryFormatOption {
  /// The format option type character (e.g., 'i', 'c', 'z', '<', '!')
  final String type;

  /// Explicit size for options like i4, c10, etc. (null if not specified)
  final int? size;

  /// Alignment value for !n options (null if not applicable)
  final int? align;

  /// Original text from format string (useful for error reporting)
  final String raw;

  /// Creates a new binary format option.
  ///
  /// Parameters:
  /// - [type]: The option character
  /// - [size]: Optional size parameter
  /// - [align]: Optional alignment parameter
  /// - [raw]: Original text (required for error reporting)
  BinaryFormatOption(this.type, {this.size, this.align, required this.raw});

  @override
  String toString() =>
      'BinaryFormatOption(type: $type, size: $size, align: $align, raw: "$raw")';
}

/// Parser that turns a Lua 5.4 binary-format string into a list of
/// [BinaryFormatOption]s, performing the same validation that the Lua VM does.
///
/// This parser handles all Lua 5.4 binary format options including:
/// - Endianness markers: `<`, `>`, `=`
/// - Alignment options: `!`, `!n`
/// - Integer types: `b`, `B`, `h`, `H`, `l`, `L`, `j`, `J`, `T`, `i`, `I`
/// - Floating point types: `f`, `d`, `n`
/// - String types: `c`, `s`, `z`
/// - Padding and alignment: `x`, `X`
///
/// The parser performs comprehensive validation including:
/// - Numeric suffix length validation to prevent excessive digits
/// - Format option validation for proper syntax
/// - Size constraint validation for integer and alignment options
/// - Power-of-2 validation for alignment specifiers
/// - Overflow detection during parsing to fail early
///
/// Error handling matches Lua's exact behavior and error messages:
/// - "invalid format" for malformed format strings
/// - "missing size" for options requiring size parameters
/// - "out of limits" for size parameters outside valid ranges
/// - "format asks for alignment not power of 2" for invalid alignments
///
/// Example usage:
/// ```dart
/// try {
///   final options = BinaryFormatParser.parse("i4h2c10");
///   // Process the parsed options...
/// } catch (e) {
///   if (e is LuaError) {
///     print("Format error: ${e.message}");
///   }
/// }
/// ```
class BinaryFormatParser {
  // Validation constants
  static const int maxFormatSize = 0x7fffffff; // 2^31 - 1
  static const int maxNumericDigits =
      10; // Reasonable limit for numeric suffixes

  static final Parser<String> space = char(' ');
  // Match one or more digits without limiting the length. The actual
  // length validation is performed by `_validateNumericSuffix`, which
  // mirrors Lua's behavior of accepting long digit sequences and then
  // rejecting them with an "invalid format" error when they exceed
  // allowed limits.
  static final Parser<String> digits = digit().plus().flatten();
  static final Parser<String> signedDigits = (char('-').optional() & digits)
      .flatten();

  /// Endianness marks: `<  >  =`
  static final Parser<BinaryFormatOption> endiannessParser = pattern(
    '<>=',
  ).map((c) => BinaryFormatOption(c, raw: c));

  /// Alignment: `!n`  (n must be a power of two). A bare `!` resets to the
  /// default alignment.
  static final Parser<BinaryFormatOption>
  alignParser = (char('!') & digits.optional()).map((v) {
    final numStr = v[1] as String?;
    if (numStr == null) {
      return BinaryFormatOption('!', raw: '!');
    } else {
      // Validate numeric suffix length before parsing
      _validateNumericSuffix(numStr, '!', formatString: null);

      final n = int.parse(numStr);
      // Note: Alignment validation moved to individual functions (pack/packsize/unpack)
      // to provide proper context-aware error messages
      if (n < 1 || n > 16) {
        throw PackErrorHandling.outOfLimitsError(
          value: n,
          min: 1,
          max: 16,
          optionType: '!',
        );
      }
      if ((n & (n - 1)) != 0) {
        // This will be caught and re-thrown with proper context by calling functions
        throw LuaError('format asks for alignment not power of 2');
      }
      return BinaryFormatOption('!', align: n, raw: '!$numStr');
    }
  });

  /// `'cN'` – fixed-length char array, **size required**
  static final Parser<BinaryFormatOption> cParser = (char('c') & digits).map((
    v,
  ) {
    final numStr = v[1] as String;

    // Note: Numeric suffix validation removed to match Lua's behavior
    // Lua limits digit parsing naturally and treats excess as separate options

    int n;
    try {
      n = int.parse(numStr);
    } on FormatException {
      throw PackErrorHandling.invalidFormatError();
    }
    if (n < 0) {
      throw PackErrorHandling.invalidSizeForOptionError(
        optionType: 'c',
        size: n,
      );
    }
    return BinaryFormatOption('c', size: n, raw: 'c$numStr');
  });

  /// bare 'c' without a size -> missing size error
  static final Parser<BinaryFormatOption> cParserMissing = char(
    'c',
  ).map((_) => throw PackErrorHandling.missingSizeError(optionType: 'c'));

  /// `iN`, `IN`, `jN`, `JN`, `sN` – integer / size-prefixed string with explicit width
  static final Parser<BinaryFormatOption> iIParserWithNum =
      (pattern('iIjJs') & signedDigits).map((v) {
        final t = v[0] as String;
        final numStr = v[1] as String;

        // Validate numeric suffix length before parsing
        _validateNumericSuffix(numStr, t, formatString: null);

        int n;
        try {
          n = int.parse(numStr);
        } on FormatException {
          throw PackErrorHandling.invalidFormatError();
        }

        if ((t == 'i' || t == 'I' || t == 'j' || t == 'J') &&
            (n < 1 || n > 16)) {
          final context = PackErrorHandling.packsizeContext(optionType: t);
          final issue = PackErrorHandling.validateIntegerSize(
            size: n,
            optionType: t,
            context: context,
            minSize: 1,
            maxSize: 16,
          );
          if (issue != null) {
            throw issue.toLuaError();
          }
        }
        if (t == 's' && n < 0) {
          throw PackErrorHandling.invalidSizeForOptionError(
            optionType: 's',
            size: n,
          );
        }
        return BinaryFormatOption(t, size: n, raw: '$t$numStr');
      });

  /// a bare `'s'` (size-prefixed string with native integer size)
  static final Parser<BinaryFormatOption> sParserAlone = char(
    's',
  ).map((_) => BinaryFormatOption('s', raw: 's'));

  /// `X` alignment option with optional size: `X` or `Xn`
  static final Parser<BinaryFormatOption> xParser =
      (char('X') & digits.optional()).map((v) {
        final numStr = v[1] as String?;
        if (numStr == null) {
          return BinaryFormatOption('X', raw: 'X');
        } else {
          // Validate numeric suffix length before parsing
          _validateNumericSuffix(numStr, 'X', formatString: null);

          int n;
          try {
            n = int.parse(numStr);
          } on FormatException {
            throw PackErrorHandling.invalidFormatError();
          }
          final context = PackErrorHandling.packsizeContext(optionType: 'X');
          final issue = PackErrorHandling.validateIntegerSize(
            size: n,
            optionType: 'X',
            context: context,
            minSize: 1,
            maxSize: 16,
          );
          if (issue != null) {
            throw issue.toLuaError();
          }
          return BinaryFormatOption('X', size: n, raw: 'X$numStr');
        }
      });

  /// all simple one-byte options that never take a number
  /// (`i`, `s`, and `X` are *omitted* here because they appear in other rules)
  static final Parser<BinaryFormatOption> simpleParser = pattern(
    'bBhHlLjJTdnisxzfI',
  ).map((c) => BinaryFormatOption(c, raw: c));

  static final Parser<BinaryFormatOption> unknownParser = any().map(
    (c) => throw PackErrorHandling.invalidFormatOptionError(option: c),
  );

  static final Parser<BinaryFormatOption> optionParser =
      (iIParserWithNum |
              sParserAlone |
              cParser |
              cParserMissing |
              alignParser |
              endiannessParser |
              xParser |
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

  /// Validate numeric suffix to detect excessive digits in format options
  static void _validateNumericSuffix(
    String suffix,
    String optionType, {
    String? formatString,
  }) {
    final context = PackErrorHandling.packsizeContext(
      formatString: formatString,
      optionType: optionType,
    );

    final issue = PackErrorHandling.validateNumericSuffix(
      suffix: suffix,
      optionType: optionType,
      context: context,
      maxDigits: maxNumericDigits,
    );

    if (issue != null) {
      throw issue.toLuaError();
    }
  }

  /// Validation helper for different format option types
  static void _validateFormatOption(
    BinaryFormatOption option, {
    String? formatString,
  }) {
    final context = PackErrorHandling.packsizeContext(
      formatString: formatString,
      optionType: option.type,
    );

    switch (option.type) {
      case 'c':
        if (option.size != null && option.size! < 0) {
          throw PackErrorHandling.invalidSizeForOptionError(
            optionType: 'c',
            size: option.size,
            errorContext: context,
          );
        }
        break;
      case 'i':
      case 'I':
      case 'j':
      case 'J':
        if (option.size != null) {
          final issue = PackErrorHandling.validateIntegerSize(
            size: option.size!,
            optionType: option.type,
            context: context,
            minSize: 1,
            maxSize: 16,
          );
          if (issue != null) {
            throw issue.toLuaError();
          }
        }
        break;
      case 's':
        if (option.size != null && option.size! < 0) {
          throw PackErrorHandling.invalidSizeForOptionError(
            optionType: 's',
            size: option.size,
            errorContext: context,
          );
        }
        break;
      case '!':
        if (option.align != null) {
          final issue = PackErrorHandling.validateAlignment(
            alignment: option.align!,
            context: context,
            minAlignment: 1,
            maxAlignment: 16,
          );
          if (issue != null) {
            throw issue.toLuaError();
          }
        }
        break;
    }
  }

  /// Parse [input] into a list of [BinaryFormatOption]s or throw [LuaError].
  static List<BinaryFormatOption> parse(String input) {
    // Step 1: Format complexity validation removed to match Lua's behavior
    // _validateFormatComplexity(input);

    // Step 2: Pre-validate X options
    for (var i = 0; i < input.length; i++) {
      if (input[i] == 'X') {
        if (i + 1 >= input.length || input[i + 1].trim().isEmpty) {
          throw PackErrorHandling.invalidNextOptionError();
        }
      }
    }

    // Step 3: Parse the format string
    final result = formatParser.parse(input);
    if (result is Success) {
      final raw = List<BinaryFormatOption>.from(result.value);
      final processed = <BinaryFormatOption>[];

      // Step 4: Use PackSizeCalculator for integrated size validation
      final calculator = PackSizeCalculator();

      for (var i = 0; i < raw.length; i++) {
        final opt = raw[i];

        // Step 5: Validate each format option
        _validateFormatOption(opt);

        // Step 6: Validate numeric suffixes in the raw format
        // Note: Numeric suffix validation removed to match Lua's behavior
        // Lua limits digit parsing naturally and treats excess as separate options
        // if (opt.size != null) {
        //   final sizeStr = opt.size.toString();
        //   _validateNumericSuffix(sizeStr, opt.type);
        // }
        // if (opt.align != null) {
        //   final alignStr = opt.align.toString();
        //   _validateNumericSuffix(alignStr, opt.type);
        // }

        if (opt.type == 'X') {
          int size;
          if (opt.size != null) {
            // Explicit size provided (e.g., X4)
            size = opt.size!;
          } else {
            // Use next option to determine size
            if (i + 1 >= raw.length) {
              throw PackErrorHandling.invalidNextOptionError();
            }
            final next = raw[i + 1];
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
                throw PackErrorHandling.invalidNextOptionError(
                  nextOption: next.type,
                );
            }
          }

          // Step 7: Process X option with calculator for overflow detection
          final xOption = BinaryFormatOption(
            'X',
            size: size,
            raw: opt.size != null
                ? opt.raw
                : opt.raw + (i + 1 < raw.length ? raw[i + 1].raw : ''),
          );
          calculator.processFormatOption(xOption);

          processed.add(xOption);

          // If we used the next option for size calculation, we need to process it but not add it to the result
          if (opt.size == null && i + 1 < raw.length) {
            final next = raw[i + 1];
            // Validate and process the next option for size calculation
            _validateFormatOption(next);
            if (next.size != null) {
              final sizeStr = next.size.toString();
              _validateNumericSuffix(sizeStr, next.type);
            }
            calculator.processFormatOption(next);
            // Note: We don't add 'next' to processed because X consumes it for alignment
            i++; // skip next in the main loop since we processed it here
          }
        } else {
          // Step 8: Process regular options with calculator for overflow detection
          calculator.processFormatOption(opt);
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
