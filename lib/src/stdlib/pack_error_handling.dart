import 'package:lualike/src/lua_error.dart';

/// Validation severity levels for different types of format issues
enum ValidationSeverity {
  /// Critical errors that must stop processing immediately
  critical,

  /// Errors that should be reported but may allow continued processing
  error,

  /// Warnings that indicate potential issues but don't stop processing
  warning,

  /// Informational messages for debugging
  info,
}

/// Error context for tracking debugging information
class ErrorContext {
  final String operation; // 'pack', 'packsize', 'unpack'
  final String? formatString;
  final int? position;
  final String? optionType;
  final int? argumentIndex;
  final Map<String, dynamic> additionalInfo;

  ErrorContext({
    required this.operation,
    this.formatString,
    this.position,
    this.optionType,
    this.argumentIndex,
    this.additionalInfo = const {},
  });

  /// Create a copy of this context with updated information
  ErrorContext copyWith({
    String? operation,
    String? formatString,
    int? position,
    String? optionType,
    int? argumentIndex,
    Map<String, dynamic>? additionalInfo,
  }) {
    return ErrorContext(
      operation: operation ?? this.operation,
      formatString: formatString ?? this.formatString,
      position: position ?? this.position,
      optionType: optionType ?? this.optionType,
      argumentIndex: argumentIndex ?? this.argumentIndex,
      additionalInfo: additionalInfo ?? this.additionalInfo,
    );
  }

  @override
  String toString() {
    final parts = <String>[];
    parts.add('operation: $operation');
    if (formatString != null) parts.add('format: "$formatString"');
    if (position != null) parts.add('position: $position');
    if (optionType != null) parts.add('option: $optionType');
    if (argumentIndex != null) parts.add('arg: $argumentIndex');
    if (additionalInfo.isNotEmpty) {
      parts.add('info: $additionalInfo');
    }
    return 'ErrorContext(${parts.join(', ')})';
  }
}

/// Validation issue with severity and context
class ValidationIssue {
  final ValidationSeverity severity;
  final String message;
  final ErrorContext context;
  final Exception? cause;

  ValidationIssue({
    required this.severity,
    required this.message,
    required this.context,
    this.cause,
  });

  /// Convert this validation issue to a LuaError if it's critical or error level
  LuaError toLuaError() {
    return LuaError(message, cause: cause);
  }

  @override
  String toString() {
    return 'ValidationIssue(${severity.name}: $message, $context)';
  }
}

/// Comprehensive error handling system for string pack/unpack operations.
///
/// This class provides consistent error message constants, validation severity
/// levels, and helper methods for error message formatting to match Lua's
/// exact error format and behavior.
///
/// The error handling system supports:
/// - Consistent error messages matching Lua 5.4's exact wording
/// - Context-aware error reporting with operation details
/// - Validation severity levels for different types of issues
/// - Helper methods for common error patterns
/// - Error context tracking for better debugging
///
/// Error categories handled:
/// - Format validation errors (invalid format strings)
/// - Size overflow errors (results too large for system limits)
/// - Data validation errors (values don't fit constraints)
/// - Alignment errors (non-power-of-2 alignments)
/// - Missing parameter errors (required sizes not provided)
///
/// Example usage:
/// ```dart
/// final context = PackErrorHandling.packsizeContext(formatString: "c1000000000");
/// final issue = PackErrorHandling.validateNumericSuffix(
///   suffix: "1000000000",
///   optionType: "c",
///   context: context,
/// );
/// if (issue != null) {
///   throw issue.toLuaError();
/// }
/// ```
class PackErrorHandling {
  // Error message constants matching Lua's format
  static const String invalidFormat = 'invalid format';
  static const String tooLarge = 'too large';
  static const String missingSize = 'missing size';
  static const String outOfLimits = 'out of limits';
  static const String doesNotFit = 'does not fit';
  static const String containsZeros = 'contains zeros';
  static const String unfinishedString = 'unfinished string';
  static const String formatResultTooLarge = 'format result too large';
  static const String invalidNextOption = 'invalid next option';
  static const String formatAsksForAlignment =
      'format asks for alignment not power of 2';
  static const String variableLengthFormat = 'variable-length format';
  static const String invalidFormatOption = 'invalid format option';
  static const String integralSizeOutOfLimits = 'integral size';
  static const String invalidSizeForFormatOption =
      'invalid size for format option';
  static const String badArgument = 'bad argument';
  static const String noValue = 'no value';

  /// Helper methods for consistent error message formatting

  /// Format an "invalid format" error with optional context
  static LuaError invalidFormatError({
    String? context,
    ErrorContext? errorContext,
  }) {
    String message = invalidFormat;
    if (context != null) {
      message = '$invalidFormat: $context';
    }
    return LuaError(message);
  }

  /// Format a "too large" error for size overflow conditions
  static LuaError tooLargeError({String? context, ErrorContext? errorContext}) {
    String message = tooLarge;
    if (context != null) {
      message = '$tooLarge: $context';
    }
    return LuaError(message);
  }

  /// Format a "format result too large" error (alternative to "too large")
  static LuaError formatResultTooLargeError({
    String? context,
    ErrorContext? errorContext,
    String? functionName,
  }) {
    String message =
        '$badArgument #1 to \'${functionName ?? 'string.packsize'}\' ($formatResultTooLarge)';
    return LuaError(message);
  }

  /// Format a "missing size" error for format options that require size
  static LuaError missingSizeError({
    String? optionType,
    ErrorContext? errorContext,
  }) {
    String message = missingSize;
    if (optionType != null) {
      message = '$missingSize for format option \'$optionType\'';
    }
    return LuaError(message);
  }

  /// Format an "out of limits" error for size parameters
  static LuaError outOfLimitsError({
    required int value,
    required int min,
    required int max,
    String? optionType,
    ErrorContext? errorContext,
  }) {
    String message;
    if (optionType != null) {
      message = '$integralSizeOutOfLimits ($value) $outOfLimits [$min,$max]';
    } else {
      message = '$outOfLimits: $value not in [$min,$max]';
    }
    return LuaError(message);
  }

  /// Format an "invalid size for format option" error
  static LuaError invalidSizeForOptionError({
    required String optionType,
    int? size,
    ErrorContext? errorContext,
  }) {
    String message = '$invalidSizeForFormatOption \'$optionType\'';
    if (size != null) {
      message = '$invalidSizeForFormatOption \'$optionType\' (size: $size)';
    }
    return LuaError(message);
  }

  /// Format an "invalid format option" error
  static LuaError invalidFormatOptionError({
    required String option,
    int? position,
    ErrorContext? errorContext,
  }) {
    String message = '$invalidFormatOption \'$option\'';
    if (position != null) {
      message = '$invalidFormatOption \'$option\' at position $position';
    }
    return LuaError(message);
  }

  /// Format a "format asks for alignment not power of 2" error
  static LuaError alignmentNotPowerOf2Error({
    int? alignment,
    ErrorContext? errorContext,
  }) {
    String message = formatAsksForAlignment;
    if (alignment != null) {
      message = '$formatAsksForAlignment (alignment: $alignment)';
    }
    return LuaError(message);
  }

  /// Format an "invalid next option for option 'X'" error
  static LuaError invalidNextOptionError({
    String? nextOption,
    ErrorContext? errorContext,
  }) {
    String message = '$invalidNextOption for option \'X\'';
    if (nextOption != null) {
      message = '$invalidNextOption for option \'X\' (found: \'$nextOption\')';
    }
    return LuaError(message);
  }

  /// Format a "variable-length format" error for packsize operations
  static LuaError variableLengthFormatError({
    required String optionType,
    ErrorContext? errorContext,
  }) {
    String message =
        '$variableLengthFormat \'$optionType\' not allowed in packsize';
    return LuaError(message);
  }

  /// Format a "bad argument" error for function calls
  static LuaError badArgumentError({
    required int argumentIndex,
    required String functionName,
    required String expectedType,
    String? actualType,
    String? reason,
    ErrorContext? errorContext,
  }) {
    String message = '$badArgument #$argumentIndex to \'$functionName\'';

    if (reason != null) {
      message = '$message ($reason)';
    } else {
      message = '$message ($expectedType expected';
      if (actualType != null) {
        message = '$message, got $actualType';
      }
      message = '$message)';
    }

    return LuaError(message);
  }

  /// Format a "no value" error for missing arguments
  static LuaError noValueError({
    required int argumentIndex,
    required String functionName,
    ErrorContext? errorContext,
  }) {
    String message =
        '$badArgument #$argumentIndex to \'$functionName\' ($noValue)';
    return LuaError(message);
  }

  /// Format a "contains zeros" error for string formatting
  static LuaError containsZerosError({
    required int argumentIndex,
    required String functionName,
    ErrorContext? errorContext,
  }) {
    String message =
        '$badArgument #$argumentIndex to \'$functionName\' (string $containsZeros)';
    return LuaError(message);
  }

  /// Format a "does not fit" error for value constraints
  static LuaError doesNotFitError({
    required String value,
    required String constraint,
    ErrorContext? errorContext,
  }) {
    String message = '$value $doesNotFit in $constraint';
    return LuaError(message);
  }

  /// Format an "unfinished string" error for incomplete data
  static LuaError unfinishedStringError({
    String? context,
    ErrorContext? errorContext,
  }) {
    String message = unfinishedString;
    if (context != null) {
      message = '$unfinishedString: $context';
    }
    return LuaError(message);
  }

  /// Validate numeric suffix to detect excessive digits in format options.
  ///
  /// This method validates that numeric suffixes in format options (like the "10"
  /// in "c10" or "i4") don't exceed reasonable limits. It's designed to catch
  /// malformed format strings that could cause parsing issues or overflow conditions.
  ///
  /// Validation rules:
  /// - Numeric suffixes cannot exceed maxDigits characters (default: 10)
  /// - Special detection for patterns like "c1" + "0".repeat(40) which should
  ///   be rejected as "invalid format"
  /// - Prevents excessive trailing zeros that could indicate malformed input
  ///
  /// This validation helps match Lua's behavior where certain patterns of
  /// excessive digits in format strings are rejected early in parsing.
  ///
  /// Parameters:
  /// - [suffix] - the numeric suffix string to validate
  /// - [optionType] - the format option type (e.g., 'c', 'i', '!')
  /// - [context] - error context for detailed error reporting
  /// - [maxDigits] - maximum allowed digits (default: 10)
  ///
  /// Returns:
  /// - [ValidationIssue] if validation fails, null if valid
  static ValidationIssue? validateNumericSuffix({
    required String suffix,
    required String optionType,
    required ErrorContext context,
    int maxDigits = 10,
  }) {
    if (suffix.length > maxDigits) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message: invalidFormat,
        context: context.copyWith(
          optionType: optionType,
          additionalInfo: {
            'suffix': suffix,
            'maxDigits': maxDigits,
            'reason': 'numeric suffix too long',
          },
        ),
      );
    }

    // Special case for patterns like "c1" + "0".repeat(40)
    if (suffix.startsWith('1') && suffix.length > 20) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message: invalidFormat,
        context: context.copyWith(
          optionType: optionType,
          additionalInfo: {
            'suffix': suffix,
            'reason': 'excessive trailing zeros',
          },
        ),
      );
    }

    return null;
  }

  /// Validate format complexity to prevent malformed format strings.
  ///
  /// This method validates that format strings don't exceed reasonable complexity
  /// limits that could cause parsing issues or performance problems. It checks
  /// both overall string length and sequences of numeric digits.
  ///
  /// Validation rules:
  /// - Format string length cannot exceed maxLength (default: 1000)
  /// - Numeric sequences cannot exceed maxNumericSequenceLength (default: 10)
  /// - Detects patterns that could indicate malformed or malicious input
  ///
  /// This validation helps prevent denial-of-service attacks through extremely
  /// long or complex format strings while maintaining compatibility with
  /// reasonable use cases.
  ///
  /// Parameters:
  /// - [formatString] - the complete format string to validate
  /// - [context] - error context for detailed error reporting
  /// - [maxLength] - maximum allowed format string length (default: 1000)
  /// - [maxNumericSequenceLength] - maximum consecutive digits (default: 10)
  ///
  /// Returns:
  /// - [ValidationIssue] if validation fails, null if valid
  static ValidationIssue? validateFormatComplexity({
    required String formatString,
    required ErrorContext context,
    int maxLength = 1000,
    int maxNumericSequenceLength = 10,
  }) {
    if (formatString.length > maxLength) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message: invalidFormat,
        context: context.copyWith(
          formatString: formatString,
          additionalInfo: {
            'length': formatString.length,
            'maxLength': maxLength,
            'reason': 'format string too long',
          },
        ),
      );
    }

    // Check for excessive numeric sequences
    var inNumericSequence = false;
    var currentSequenceLength = 0;

    for (var i = 0; i < formatString.length; i++) {
      final char = formatString[i];
      if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        // '0' to '9'
        if (!inNumericSequence) {
          inNumericSequence = true;
          currentSequenceLength = 1;
        } else {
          currentSequenceLength++;
        }

        if (currentSequenceLength > maxNumericSequenceLength) {
          return ValidationIssue(
            severity: ValidationSeverity.critical,
            message: invalidFormat,
            context: context.copyWith(
              formatString: formatString,
              position: i,
              additionalInfo: {
                'sequenceLength': currentSequenceLength,
                'maxSequenceLength': maxNumericSequenceLength,
                'reason': 'numeric sequence too long',
              },
            ),
          );
        }
      } else {
        inNumericSequence = false;
        currentSequenceLength = 0;
      }
    }

    return null;
  }

  /// Validate size overflow conditions.
  ///
  /// This method checks whether adding a new element to the current size
  /// would cause an integer overflow condition. It's used throughout the
  /// pack size calculation process to ensure that operations don't exceed
  /// the maximum allowed size (2^31-1 bytes).
  ///
  /// The validation is performed before any size addition to ensure that
  /// overflow conditions are detected early and appropriate error messages
  /// are generated.
  ///
  /// Parameters:
  /// - [currentSize] - the current accumulated size
  /// - [additionalSize] - the size to be added
  /// - [context] - error context for detailed error reporting
  /// - [maxSize] - maximum allowed size (default: 2^31-1)
  ///
  /// Returns:
  /// - [ValidationIssue] if overflow would occur, null if safe
  static ValidationIssue? validateSizeOverflow({
    required BigInt currentSize,
    required int additionalSize,
    required ErrorContext context,
    BigInt? maxSize,
  }) {
    final maxAllowedSize = maxSize ?? BigInt.from(0x7fffffff);

    if (currentSize + BigInt.from(additionalSize) > maxAllowedSize) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message: tooLarge,
        context: context.copyWith(
          additionalInfo: {
            'currentSize': currentSize.toString(),
            'additionalSize': additionalSize,
            'maxSize': maxAllowedSize.toString(),
            'reason': 'size overflow detected',
          },
        ),
      );
    }

    return null;
  }

  /// Validate alignment requirements.
  ///
  /// This method validates that alignment values specified in format strings
  /// (like the "4" in "!4") meet Lua's requirements for binary format alignment.
  /// Alignment values must be powers of 2 and within reasonable limits.
  ///
  /// Validation rules:
  /// - Alignment must be within [minAlignment, maxAlignment] range (default: [1, 16])
  /// - Alignment must be a power of 2 (1, 2, 4, 8, 16)
  /// - Zero or negative alignments are not allowed
  ///
  /// This validation ensures that binary data can be properly aligned in memory
  /// and that the alignment requirements don't exceed system capabilities.
  ///
  /// Parameters:
  /// - [alignment] - the alignment value to validate
  /// - [context] - error context for detailed error reporting
  /// - [minAlignment] - minimum allowed alignment (default: 1)
  /// - [maxAlignment] - maximum allowed alignment (default: 16)
  ///
  /// Returns:
  /// - [ValidationIssue] if validation fails, null if valid
  static ValidationIssue? validateAlignment({
    required int alignment,
    required ErrorContext context,
    int minAlignment = 1,
    int maxAlignment = 16,
  }) {
    if (alignment < minAlignment || alignment > maxAlignment) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message:
            '$integralSizeOutOfLimits ($alignment) $outOfLimits [$minAlignment,$maxAlignment]',
        context: context.copyWith(
          additionalInfo: {
            'alignment': alignment,
            'minAlignment': minAlignment,
            'maxAlignment': maxAlignment,
            'reason': 'alignment out of range',
          },
        ),
      );
    }

    if ((alignment & (alignment - 1)) != 0) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message: formatAsksForAlignment,
        context: context.copyWith(
          additionalInfo: {
            'alignment': alignment,
            'reason': 'alignment not power of 2',
          },
        ),
      );
    }

    return null;
  }

  /// Validate integer size constraints.
  ///
  /// This method validates that size parameters for integer format options
  /// (like the "4" in "i4" or "8" in "I8") are within the valid range
  /// supported by Lua's binary format system.
  ///
  /// Validation rules:
  /// - Size must be within [minSize, maxSize] range (default: [1, 16])
  /// - Size must be positive (greater than 0)
  /// - Size represents the number of bytes for the integer representation
  ///
  /// This validation ensures that integer sizes are reasonable and can be
  /// properly handled by the binary packing/unpacking system without
  /// causing memory issues or invalid operations.
  ///
  /// Parameters:
  /// - [size] - the integer size to validate
  /// - [optionType] - the format option type (e.g., 'i', 'I', 'j', 'J')
  /// - [context] - error context for detailed error reporting
  /// - [minSize] - minimum allowed size (default: 1)
  /// - [maxSize] - maximum allowed size (default: 16)
  ///
  /// Returns:
  /// - [ValidationIssue] if validation fails, null if valid
  static ValidationIssue? validateIntegerSize({
    required int size,
    required String optionType,
    required ErrorContext context,
    int minSize = 1,
    int maxSize = 16,
  }) {
    if (size < minSize || size > maxSize) {
      return ValidationIssue(
        severity: ValidationSeverity.critical,
        message:
            '$integralSizeOutOfLimits ($size) $outOfLimits [$minSize,$maxSize]',
        context: context.copyWith(
          optionType: optionType,
          additionalInfo: {
            'size': size,
            'minSize': minSize,
            'maxSize': maxSize,
            'reason': 'integer size out of range',
          },
        ),
      );
    }

    return null;
  }

  /// Create error context for pack operations
  static ErrorContext packContext({
    String? formatString,
    int? position,
    String? optionType,
    int? argumentIndex,
    Map<String, dynamic>? additionalInfo,
  }) {
    return ErrorContext(
      operation: 'pack',
      formatString: formatString,
      position: position,
      optionType: optionType,
      argumentIndex: argumentIndex,
      additionalInfo: additionalInfo ?? {},
    );
  }

  /// Create error context for packsize operations
  static ErrorContext packsizeContext({
    String? formatString,
    int? position,
    String? optionType,
    int? argumentIndex,
    Map<String, dynamic>? additionalInfo,
  }) {
    return ErrorContext(
      operation: 'packsize',
      formatString: formatString,
      position: position,
      optionType: optionType,
      argumentIndex: argumentIndex,
      additionalInfo: additionalInfo ?? {},
    );
  }

  /// Create error context for unpack operations
  static ErrorContext unpackContext({
    String? formatString,
    int? position,
    String? optionType,
    int? argumentIndex,
    Map<String, dynamic>? additionalInfo,
  }) {
    return ErrorContext(
      operation: 'unpack',
      formatString: formatString,
      position: position,
      optionType: optionType,
      argumentIndex: argumentIndex,
      additionalInfo: additionalInfo ?? {},
    );
  }

  /// Collect and validate multiple issues, throwing the first critical/error
  static void validateIssues(List<ValidationIssue> issues) {
    final criticalIssues = issues
        .where((i) => i.severity == ValidationSeverity.critical)
        .toList();
    final errorIssues = issues
        .where((i) => i.severity == ValidationSeverity.error)
        .toList();

    if (criticalIssues.isNotEmpty) {
      throw criticalIssues.first.toLuaError();
    }

    if (errorIssues.isNotEmpty) {
      throw errorIssues.first.toLuaError();
    }
  }

  /// Log validation warnings and info messages (for debugging)
  static void logIssues(List<ValidationIssue> issues) {
    final warnings = issues
        .where((i) => i.severity == ValidationSeverity.warning)
        .toList();
    final infos = issues
        .where((i) => i.severity == ValidationSeverity.info)
        .toList();

    // In a real implementation, these would go to a proper logging system
    // For now, we silently ignore warnings and info messages to avoid console spam
    // but preserve the structure for future logging integration
    if (warnings.isNotEmpty || infos.isNotEmpty) {
      // Logging would be implemented here in a production system
      // Example: logger.warning('Pack validation warnings: ${warnings.length}');
      // Example: logger.info('Pack validation info messages: ${infos.length}');
    }
  }
}
