import 'dart:typed_data';

import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/parsers/binary_format.dart';
import 'package:lualike/src/stdlib/binary_type_size.dart';
import 'package:lualike/src/stdlib/pack_error_handling.dart';

/// Centralized size calculation with overflow detection for string pack operations.
///
/// This class provides consistent size calculation logic across all string binary
/// operations (pack, packsize, unpack) with proper overflow detection and alignment
/// handling. It ensures that format strings don't cause integer overflow and that
/// alignment requirements are properly validated.
///
/// The calculator maintains state for:
/// - Current offset/size accumulation
/// - Maximum alignment setting
/// - Endianness configuration
///
/// Key features:
/// - Overflow detection before operations that could exceed 2^31-1 bytes
/// - Power-of-2 alignment validation
/// - Consistent error messages matching Lua's format
/// - Support for all Lua 5.4 binary format options
///
/// Example usage:
/// ```dart
/// final calculator = PackSizeCalculator();
/// final options = BinaryFormatParser.parse("i4h2c10");
/// for (final option in options) {
///   calculator.processFormatOption(option);
/// }
/// final totalSize = calculator.totalSize;
/// ```
class PackSizeCalculator {
  static final BigInt maxAllowedSize = BigInt.from(0x7fffffff); // 2^31 - 1

  BigInt _currentOffset = BigInt.zero;
  int _maxAlign = 1;
  Endian _endianness = Endian.host;

  /// Current calculated offset/size
  BigInt get currentOffset => _currentOffset;

  /// Current maximum alignment
  int get maxAlign => _maxAlign;

  /// Current endianness setting
  Endian get endianness => _endianness;

  /// Total calculated size
  BigInt get totalSize => _currentOffset;

  /// Reset the calculator to initial state
  void reset() {
    _currentOffset = BigInt.zero;
    _maxAlign = 1;
    _endianness = Endian.host;
  }

  /// Set the maximum alignment value
  ///
  /// [alignment] must be a power of 2 between 1 and 16
  void setAlignment(int alignment) {
    final context = PackErrorHandling.packsizeContext();
    final issue = PackErrorHandling.validateAlignment(
      alignment: alignment,
      context: context,
      minAlignment: 1,
      maxAlignment: 16,
    );
    if (issue != null) {
      throw issue.toLuaError();
    }
    _maxAlign = alignment;
  }

  /// Reset alignment to default (native integer size)
  void resetAlignment() {
    _maxAlign = BinaryTypeSize.j;
  }

  /// Set endianness for subsequent operations
  void setEndianness(Endian endianness) {
    _endianness = endianness;
  }

  /// Calculate alignment padding needed for the given alignment
  ///
  /// Returns the number of bytes needed to align [offset] to [align] boundary
  BigInt _alignTo(BigInt offset, int align) {
    if (align <= 1) return BigInt.zero;

    // Validate alignment is power of 2
    if ((align & (align - 1)) != 0) {
      throw PackErrorHandling.alignmentNotPowerOf2Error(alignment: align);
    }

    final mod = offset % BigInt.from(align);
    return mod == BigInt.zero ? BigInt.zero : BigInt.from(align) - mod;
  }

  /// Add a sized element with proper alignment and overflow checking.
  ///
  /// This method handles the core logic for adding binary format elements that
  /// require alignment (like integers and floats). It calculates the necessary
  /// padding to align the element, checks for overflow conditions, and updates
  /// the current offset.
  ///
  /// The alignment logic follows Lua's rules:
  /// - Elements are aligned to their natural size or maxAlign, whichever is smaller
  /// - Alignment must be a power of 2
  /// - Padding bytes are added before the element if needed
  ///
  /// Overflow detection:
  /// - Checks for overflow before adding padding
  /// - Checks for overflow before adding the element size
  /// - Throws "too large" error if any operation would exceed 2^31-1 bytes
  ///
  /// Parameters:
  /// - [size] - the size of the element to add (must be positive)
  /// - [customAlign] - optional custom alignment (defaults to element size or maxAlign)
  ///
  /// Throws:
  /// - [LuaError] with "too large" message if overflow would occur
  /// - [LuaError] with alignment error if alignment is not power of 2
  void addSized(int size, {int? customAlign}) {
    final align = customAlign ?? (size > _maxAlign ? _maxAlign : size);

    // Calculate alignment padding
    final padding = _alignTo(_currentOffset, align);

    // Check for overflow before adding padding
    if (_currentOffset + padding > maxAllowedSize) {
      throw PackErrorHandling.formatResultTooLargeError(
        functionName: 'string.packsize',
      );
    }

    _currentOffset += padding;

    // Check for overflow before adding the actual size
    if (_currentOffset + BigInt.from(size) > maxAllowedSize) {
      throw PackErrorHandling.formatResultTooLargeError(
        functionName: 'string.packsize',
      );
    }

    _currentOffset += BigInt.from(size);
  }

  /// Add a fixed-size element without alignment (like 'c' or 'x' options)
  ///
  /// [size] - the size to add
  void addUnaligned(int size) {
    // Check for overflow before adding
    if (_currentOffset + BigInt.from(size) > maxAllowedSize) {
      throw PackErrorHandling.formatResultTooLargeError(
        functionName: 'string.packsize',
      );
    }

    _currentOffset += BigInt.from(size);
  }

  /// Calculate alignment padding for a given size without adding it
  ///
  /// Used for 'X' alignment options that only add padding
  BigInt calculateAlignmentPadding(int size) {
    final align = size > _maxAlign ? _maxAlign : size;
    return _alignTo(_currentOffset, align);
  }

  /// Add alignment padding for the given size
  ///
  /// Used for 'X' alignment options
  void addAlignmentPadding(int size) {
    final align = size > _maxAlign ? _maxAlign : size;
    final padding = _alignTo(_currentOffset, align);

    // Check for overflow before adding padding
    if (_currentOffset + padding > maxAllowedSize) {
      throw PackErrorHandling.tooLargeError();
    }

    _currentOffset += padding;
  }

  /// Process a binary format option and update the size calculation.
  ///
  /// This method handles all Lua 5.4 binary format options and updates the
  /// calculator state accordingly. It performs the appropriate size and alignment
  /// calculations for each option type while checking for overflow conditions.
  ///
  /// Format option types handled:
  /// - Endianness: `<` (little), `>` (big), `=` (native)
  /// - Alignment: `!` (reset), `!n` (set to n)
  /// - Integers: `b`, `B`, `h`, `H`, `l`, `L`, `j`, `J`, `T`, `i`, `I`
  /// - Floats: `f`, `d`, `n`
  /// - Strings: `c` (fixed-size), `s`, `z` (variable-length)
  /// - Padding: `x` (single byte), `X` (alignment padding)
  ///
  /// Special handling:
  /// - Variable-length formats (`s`, `z`) are allowed but don't contribute to size
  /// - `X` option requires next option or explicit size for alignment calculation
  /// - All sized operations check for overflow before updating offset
  ///
  /// Parameters:
  /// - [option] - the format option to process
  /// - [nextOption] - the next option (required for `X` without explicit size)
  ///
  /// Throws:
  /// - [LuaError] for invalid format options
  /// - [LuaError] for missing required parameters
  /// - [LuaError] for overflow conditions
  void processFormatOption(
    BinaryFormatOption option, {
    BinaryFormatOption? nextOption,
  }) {
    switch (option.type) {
      case '<':
        setEndianness(Endian.little);
        break;
      case '>':
        setEndianness(Endian.big);
        break;
      case '=':
        setEndianness(Endian.host);
        break;
      case '!':
        if (option.align == null) {
          resetAlignment();
        } else {
          setAlignment(option.align!);
        }
        break;
      case 'c':
        if (option.size == null) {
          throw PackErrorHandling.missingSizeError(optionType: 'c');
        }
        addUnaligned(option.size!);
        break;
      case 'b':
      case 'B':
        addSized(BinaryTypeSize.b);
        break;
      case 'h':
      case 'H':
        addSized(BinaryTypeSize.h);
        break;
      case 'l':
      case 'L':
        addSized(BinaryTypeSize.l);
        break;
      case 'j':
      case 'J':
        addSized(BinaryTypeSize.j);
        break;
      case 'T':
        addSized(BinaryTypeSize.T);
        break;
      case 'f':
        addSized(BinaryTypeSize.f);
        break;
      case 'd':
      case 'n':
        addSized(BinaryTypeSize.d);
        break;
      case 'i':
        addSized(option.size ?? BinaryTypeSize.i);
        break;
      case 'I':
        addSized(option.size ?? BinaryTypeSize.I);
        break;
      case 's':
      case 'z':
        // Variable-length formats are allowed during parsing but not during size calculation
        // They will be handled separately in the actual pack/unpack operations
        break;
      case 'x':
        addUnaligned(1);
        break;
      case 'X':
        // X option requires the next option to determine alignment size
        int alignmentSize;
        if (option.size != null) {
          // Explicit size was provided (e.g., X4)
          alignmentSize = option.size!;
        } else if (nextOption != null) {
          // Use the size of the next option for alignment
          alignmentSize = _getSizeForOption(nextOption);
        } else {
          throw PackErrorHandling.invalidNextOptionError();
        }
        addAlignmentPadding(alignmentSize);
        break;
      default:
        throw PackErrorHandling.invalidFormatOptionError(option: option.type);
    }
  }

  /// Get the size for a format option (used for X alignment calculations)
  int _getSizeForOption(BinaryFormatOption option) {
    switch (option.type) {
      case 'b':
      case 'B':
        return BinaryTypeSize.b;
      case 'h':
      case 'H':
        return BinaryTypeSize.h;
      case 'l':
      case 'L':
        return BinaryTypeSize.l;
      case 'j':
      case 'J':
        return BinaryTypeSize.j;
      case 'T':
        return BinaryTypeSize.T;
      case 'f':
        return BinaryTypeSize.f;
      case 'd':
      case 'n':
        return BinaryTypeSize.d;
      case 'i':
        return option.size ?? BinaryTypeSize.i;
      case 'I':
        return option.size ?? BinaryTypeSize.I;
      case 'c':
        return option.size ?? 0;
      default:
        throw PackErrorHandling.invalidNextOptionError(nextOption: option.type);
    }
  }

  /// Calculate the total size for a list of format options.
  ///
  /// This is the main entry point for size calculation used by string.packsize
  /// and other functions that need to determine the total size of a binary format.
  /// It creates a new calculator instance and processes all format options in order,
  /// handling dependencies between options (like X alignment requiring next option).
  ///
  /// The calculation process:
  /// 1. Creates a fresh calculator instance
  /// 2. Iterates through all format options
  /// 3. Processes each option with awareness of the next option (for X handling)
  /// 4. Returns the final calculated size
  ///
  /// Parameters:
  /// - [options] - list of parsed binary format options
  ///
  /// Returns:
  /// - [BigInt] representing the total size in bytes
  ///
  /// Throws:
  /// - [LuaError] for invalid format options
  /// - [LuaError] for overflow conditions
  /// - [LuaError] for missing required parameters
  static BigInt calculateSize(List<BinaryFormatOption> options) {
    final calculator = PackSizeCalculator();

    for (int i = 0; i < options.length; i++) {
      final option = options[i];
      final nextOption = (i + 1 < options.length) ? options[i + 1] : null;

      calculator.processFormatOption(option, nextOption: nextOption);
    }

    return calculator.totalSize;
  }

  /// Validate that a format string won't cause size overflow.
  ///
  /// This performs early validation during format parsing to ensure that
  /// the format string can be processed without causing integer overflow.
  /// It's used by the string pack/unpack functions to fail fast on invalid
  /// formats before attempting to process data.
  ///
  /// The validation process:
  /// 1. Parses the format string into binary format options
  /// 2. Calculates the total size using the size calculator
  /// 3. Throws appropriate errors if parsing or calculation fails
  ///
  /// This method is particularly important for detecting format strings that
  /// would cause overflow conditions, such as very large repeat counts or
  /// excessive alignment requirements.
  ///
  /// Parameters:
  /// - [format] - the format string to validate
  ///
  /// Throws:
  /// - [LuaError] with "invalid format" for malformed format strings
  /// - [LuaError] with "too large" for formats that would cause overflow
  /// - [LuaError] for other validation failures
  static void validateFormatSize(String format) {
    try {
      final options = BinaryFormatParser.parse(format);
      calculateSize(options);
    } catch (e) {
      if (e is LuaError) rethrow;
      throw PackErrorHandling.invalidFormatError();
    }
  }
}
