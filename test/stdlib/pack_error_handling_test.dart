import 'package:lualike/src/stdlib/pack_error_handling.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:test/test.dart';

/// Unit tests for PackErrorHandling class.
///
/// These tests focus on the error handling system including validation
/// severity levels, error context tracking, and consistent error message
/// formatting to match Lua's exact behavior.
void main() {
  group('PackErrorHandling', () {
    group('Error Context', () {
      test('should create error context with required fields', () {
        final context = ErrorContext(operation: 'packsize');

        expect(context.operation, equals('packsize'));
        expect(context.formatString, isNull);
        expect(context.position, isNull);
        expect(context.optionType, isNull);
        expect(context.argumentIndex, isNull);
        expect(context.additionalInfo, isEmpty);
      });

      test('should create error context with all fields', () {
        final context = ErrorContext(
          operation: 'pack',
          formatString: 'i4h2',
          position: 2,
          optionType: 'h',
          argumentIndex: 1,
          additionalInfo: {'test': 'value'},
        );

        expect(context.operation, equals('pack'));
        expect(context.formatString, equals('i4h2'));
        expect(context.position, equals(2));
        expect(context.optionType, equals('h'));
        expect(context.argumentIndex, equals(1));
        expect(context.additionalInfo['test'], equals('value'));
      });

      test('should copy context with updates', () {
        final original = ErrorContext(operation: 'packsize');
        final updated = original.copyWith(formatString: 'i4', position: 1);

        expect(updated.operation, equals('packsize'));
        expect(updated.formatString, equals('i4'));
        expect(updated.position, equals(1));
        expect(original.formatString, isNull); // Original unchanged
      });

      test('should provide meaningful toString', () {
        final context = ErrorContext(
          operation: 'pack',
          formatString: 'i4',
          position: 1,
          optionType: 'i',
        );

        final str = context.toString();
        expect(str, contains('operation: pack'));
        expect(str, contains('format: "i4"'));
        expect(str, contains('position: 1'));
        expect(str, contains('option: i'));
      });
    });

    group('Validation Issue', () {
      test('should create validation issue', () {
        final context = ErrorContext(operation: 'packsize');
        final issue = ValidationIssue(
          severity: ValidationSeverity.critical,
          message: 'invalid format',
          context: context,
        );

        expect(issue.severity, equals(ValidationSeverity.critical));
        expect(issue.message, equals('invalid format'));
        expect(issue.context, equals(context));
        expect(issue.cause, isNull);
      });

      test('should convert to LuaError', () {
        final context = ErrorContext(operation: 'packsize');
        final issue = ValidationIssue(
          severity: ValidationSeverity.critical,
          message: 'invalid format',
          context: context,
        );

        final error = issue.toLuaError();
        expect(error, isA<LuaError>());
        expect(error.toString(), contains('invalid format'));
      });

      test('should provide meaningful toString', () {
        final context = ErrorContext(operation: 'packsize');
        final issue = ValidationIssue(
          severity: ValidationSeverity.error,
          message: 'test message',
          context: context,
        );

        final str = issue.toString();
        expect(str, contains('error: test message'));
        expect(str, contains('operation: packsize'));
      });
    });

    group('Error Message Helpers', () {
      test('should create invalid format error', () {
        final error = PackErrorHandling.invalidFormatError();
        expect(error.toString(), contains('invalid format'));
      });

      test('should create invalid format error with context', () {
        final error = PackErrorHandling.invalidFormatError(
          context: 'test context',
        );
        expect(error.toString(), contains('invalid format: test context'));
      });

      test('should create too large error', () {
        final error = PackErrorHandling.tooLargeError();
        expect(error.toString(), contains('too large'));
      });

      test('should create format result too large error', () {
        final error = PackErrorHandling.formatResultTooLargeError();
        expect(error.toString(), contains('bad argument'));
        expect(error.toString(), contains('string.packsize'));
        expect(error.toString(), contains('format result too large'));
      });

      test(
        'should create format result too large error with function name',
        () {
          final error = PackErrorHandling.formatResultTooLargeError(
            functionName: 'string.pack',
          );
          expect(error.toString(), contains('string.pack'));
        },
      );

      test('should create missing size error', () {
        final error = PackErrorHandling.missingSizeError();
        expect(error.toString(), contains('missing size'));
      });

      test('should create missing size error with option type', () {
        final error = PackErrorHandling.missingSizeError(optionType: 'c');
        expect(
          error.toString(),
          contains('missing size for format option \'c\''),
        );
      });

      test('should create out of limits error', () {
        final error = PackErrorHandling.outOfLimitsError(
          value: 17,
          min: 1,
          max: 16,
        );
        expect(error.toString(), contains('out of limits: 17 not in [1,16]'));
      });

      test('should create out of limits error with option type', () {
        final error = PackErrorHandling.outOfLimitsError(
          value: 17,
          min: 1,
          max: 16,
          optionType: 'i',
        );
        expect(
          error.toString(),
          contains('integral size (17) out of limits [1,16]'),
        );
      });

      test('should create invalid size for option error', () {
        final error = PackErrorHandling.invalidSizeForOptionError(
          optionType: 'c',
          size: -1,
        );
        expect(
          error.toString(),
          contains('invalid size for format option \'c\' (size: -1)'),
        );
      });

      test('should create invalid format option error', () {
        final error = PackErrorHandling.invalidFormatOptionError(option: 'q');
        expect(error.toString(), contains('invalid format option \'q\''));
      });

      test('should create invalid format option error with position', () {
        final error = PackErrorHandling.invalidFormatOptionError(
          option: 'q',
          position: 5,
        );
        expect(
          error.toString(),
          contains('invalid format option \'q\' at position 5'),
        );
      });

      test('should create alignment not power of 2 error', () {
        final error = PackErrorHandling.alignmentNotPowerOf2Error(alignment: 3);
        expect(
          error.toString(),
          contains('format asks for alignment not power of 2'),
        );
        expect(error.toString(), contains('(alignment: 3)'));
      });

      test('should create invalid next option error', () {
        final error = PackErrorHandling.invalidNextOptionError();
        expect(
          error.toString(),
          contains('invalid next option for option \'X\''),
        );
      });

      test('should create invalid next option error with next option', () {
        final error = PackErrorHandling.invalidNextOptionError(nextOption: 'q');
        expect(
          error.toString(),
          contains('invalid next option for option \'X\' (found: \'q\')'),
        );
      });

      test('should create variable length format error', () {
        final error = PackErrorHandling.variableLengthFormatError(
          optionType: 's',
        );
        expect(
          error.toString(),
          contains('variable-length format \'s\' not allowed in packsize'),
        );
      });

      test('should create bad argument error', () {
        final error = PackErrorHandling.badArgumentError(
          argumentIndex: 1,
          functionName: 'string.pack',
          expectedType: 'number',
          actualType: 'string',
        );
        expect(
          error.toString(),
          contains('bad argument #1 to \'string.pack\''),
        );
        expect(error.toString(), contains('(number expected, got string)'));
      });

      test('should create bad argument error with reason', () {
        final error = PackErrorHandling.badArgumentError(
          argumentIndex: 1,
          functionName: 'string.pack',
          expectedType: 'number',
          reason: 'custom reason',
        );
        expect(
          error.toString(),
          contains('bad argument #1 to \'string.pack\''),
        );
        expect(error.toString(), contains('(custom reason)'));
      });

      test('should create no value error', () {
        final error = PackErrorHandling.noValueError(
          argumentIndex: 2,
          functionName: 'string.pack',
        );
        expect(
          error.toString(),
          contains('bad argument #2 to \'string.pack\' (no value)'),
        );
      });

      test('should create contains zeros error', () {
        final error = PackErrorHandling.containsZerosError(
          argumentIndex: 2,
          functionName: 'string.pack',
        );
        expect(
          error.toString(),
          contains(
            'bad argument #2 to \'string.pack\' (string contains zeros)',
          ),
        );
      });

      test('should create does not fit error', () {
        final error = PackErrorHandling.doesNotFitError(
          value: '256',
          constraint: 'byte',
        );
        expect(error.toString(), contains('256 does not fit in byte'));
      });

      test('should create unfinished string error', () {
        final error = PackErrorHandling.unfinishedStringError();
        expect(error.toString(), contains('unfinished string'));
      });

      test('should create unfinished string error with context', () {
        final error = PackErrorHandling.unfinishedStringError(
          context: 'at position 5',
        );
        expect(error.toString(), contains('unfinished string: at position 5'));
      });
    });

    group('Validation Methods', () {
      group('Numeric Suffix Validation', () {
        test('should accept valid numeric suffixes', () {
          final context = PackErrorHandling.packsizeContext();

          final validSuffixes = ['1', '10', '100', '1000', '12345'];
          for (final suffix in validSuffixes) {
            final issue = PackErrorHandling.validateNumericSuffix(
              suffix: suffix,
              optionType: 'c',
              context: context,
            );
            expect(issue, isNull, reason: 'Suffix "$suffix" should be valid');
          }
        });

        test('should reject excessive digit suffixes', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateNumericSuffix(
            suffix: '12345678901', // 11 digits (over default limit of 10)
            optionType: 'c',
            context: context,
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
          expect(issue.message, equals('invalid format'));
        });

        test('should reject patterns like c1 + excessive zeros', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateNumericSuffix(
            suffix: '1${"0" * 30}', // 1 followed by 30 zeros
            optionType: 'c',
            context: context,
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
          expect(issue.message, equals('invalid format'));
        });

        test('should respect custom max digits limit', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateNumericSuffix(
            suffix: '12345',
            optionType: 'c',
            context: context,
            maxDigits: 3, // Custom limit
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
        });
      });

      group('Format Complexity Validation', () {
        test('should accept reasonable format strings', () {
          final context = PackErrorHandling.packsizeContext();

          final validFormats = [
            'i4h2c10',
            'bBhHlLjJTfdn',
            '!4i4!8dc5',
            '<i4>i4=i4',
          ];

          for (final format in validFormats) {
            final issue = PackErrorHandling.validateFormatComplexity(
              formatString: format,
              context: context,
            );
            expect(issue, isNull, reason: 'Format "$format" should be valid');
          }
        });

        test('should reject excessively long format strings', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateFormatComplexity(
            formatString: 'i' * 1001, // Over default limit of 1000
            context: context,
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
          expect(issue.message, equals('invalid format'));
        });

        test('should reject excessive numeric sequences', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateFormatComplexity(
            formatString: 'c${"1" * 15}', // 15 consecutive digits
            context: context,
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
          expect(issue.message, equals('invalid format'));
        });

        test('should respect custom limits', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateFormatComplexity(
            formatString: 'i4h2c10',
            context: context,
            maxLength: 5, // Custom limit
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
        });
      });

      group('Size Overflow Validation', () {
        test('should accept safe size additions', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateSizeOverflow(
            currentSize: BigInt.from(1000),
            additionalSize: 2000,
            context: context,
          );

          expect(issue, isNull);
        });

        test('should detect size overflow', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateSizeOverflow(
            currentSize: BigInt.from(0x7ffffff0),
            additionalSize: 0x20,
            context: context,
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
          expect(issue.message, equals('too large'));
        });

        test('should respect custom max size', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateSizeOverflow(
            currentSize: BigInt.from(900),
            additionalSize: 200,
            context: context,
            maxSize: BigInt.from(1000),
          );

          expect(issue, isNotNull);
          expect(issue!.severity, equals(ValidationSeverity.critical));
        });
      });

      group('Alignment Validation', () {
        test('should accept valid power-of-2 alignments', () {
          final context = PackErrorHandling.packsizeContext();

          final validAlignments = [1, 2, 4, 8, 16];
          for (final alignment in validAlignments) {
            final issue = PackErrorHandling.validateAlignment(
              alignment: alignment,
              context: context,
            );
            expect(
              issue,
              isNull,
              reason: 'Alignment $alignment should be valid',
            );
          }
        });

        test('should reject non-power-of-2 alignments', () {
          final context = PackErrorHandling.packsizeContext();

          final invalidAlignments = [3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15];
          for (final alignment in invalidAlignments) {
            final issue = PackErrorHandling.validateAlignment(
              alignment: alignment,
              context: context,
            );
            expect(
              issue,
              isNotNull,
              reason: 'Alignment $alignment should be invalid',
            );
            expect(issue!.message, contains('power of 2'));
          }
        });

        test('should reject out-of-range alignments', () {
          final context = PackErrorHandling.packsizeContext();

          final outOfRangeAlignments = [0, 17, 32, 64];
          for (final alignment in outOfRangeAlignments) {
            final issue = PackErrorHandling.validateAlignment(
              alignment: alignment,
              context: context,
            );
            expect(
              issue,
              isNotNull,
              reason: 'Alignment $alignment should be out of range',
            );
            expect(issue!.message, contains('out of limits'));
          }
        });

        test('should respect custom alignment limits', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateAlignment(
            alignment: 8,
            context: context,
            minAlignment: 1,
            maxAlignment: 4,
          );

          expect(issue, isNotNull);
          expect(issue!.message, contains('out of limits'));
        });
      });

      group('Integer Size Validation', () {
        test('should accept valid integer sizes', () {
          final context = PackErrorHandling.packsizeContext();

          final validSizes = [1, 2, 4, 8, 16];
          for (final size in validSizes) {
            final issue = PackErrorHandling.validateIntegerSize(
              size: size,
              optionType: 'i',
              context: context,
            );
            expect(issue, isNull, reason: 'Size $size should be valid');
          }
        });

        test('should reject out-of-range integer sizes', () {
          final context = PackErrorHandling.packsizeContext();

          final invalidSizes = [0, 17, 32];
          for (final size in invalidSizes) {
            final issue = PackErrorHandling.validateIntegerSize(
              size: size,
              optionType: 'i',
              context: context,
            );
            expect(issue, isNotNull, reason: 'Size $size should be invalid');
            expect(issue!.message, contains('out of limits'));
          }
        });

        test('should respect custom size limits', () {
          final context = PackErrorHandling.packsizeContext();

          final issue = PackErrorHandling.validateIntegerSize(
            size: 8,
            optionType: 'i',
            context: context,
            minSize: 1,
            maxSize: 4,
          );

          expect(issue, isNotNull);
          expect(issue!.message, contains('out of limits'));
        });
      });
    });

    group('Context Helpers', () {
      test('should create pack context', () {
        final context = PackErrorHandling.packContext(
          formatString: 'i4',
          position: 1,
          optionType: 'i',
        );

        expect(context.operation, equals('pack'));
        expect(context.formatString, equals('i4'));
        expect(context.position, equals(1));
        expect(context.optionType, equals('i'));
      });

      test('should create packsize context', () {
        final context = PackErrorHandling.packsizeContext(formatString: 'i4');

        expect(context.operation, equals('packsize'));
        expect(context.formatString, equals('i4'));
      });

      test('should create unpack context', () {
        final context = PackErrorHandling.unpackContext(
          formatString: 'i4',
          argumentIndex: 2,
        );

        expect(context.operation, equals('unpack'));
        expect(context.formatString, equals('i4'));
        expect(context.argumentIndex, equals(2));
      });
    });

    group('Issue Collection and Validation', () {
      test('should validate issues and throw first critical', () {
        final context = PackErrorHandling.packsizeContext();
        final issues = [
          ValidationIssue(
            severity: ValidationSeverity.warning,
            message: 'warning message',
            context: context,
          ),
          ValidationIssue(
            severity: ValidationSeverity.critical,
            message: 'critical message',
            context: context,
          ),
          ValidationIssue(
            severity: ValidationSeverity.error,
            message: 'error message',
            context: context,
          ),
        ];

        expect(
          () => PackErrorHandling.validateIssues(issues),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('critical message'),
            ),
          ),
        );
      });

      test('should validate issues and throw first error if no critical', () {
        final context = PackErrorHandling.packsizeContext();
        final issues = [
          ValidationIssue(
            severity: ValidationSeverity.warning,
            message: 'warning message',
            context: context,
          ),
          ValidationIssue(
            severity: ValidationSeverity.error,
            message: 'error message',
            context: context,
          ),
        ];

        expect(
          () => PackErrorHandling.validateIssues(issues),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('error message'),
            ),
          ),
        );
      });

      test('should not throw for warnings and info only', () {
        final context = PackErrorHandling.packsizeContext();
        final issues = [
          ValidationIssue(
            severity: ValidationSeverity.warning,
            message: 'warning message',
            context: context,
          ),
          ValidationIssue(
            severity: ValidationSeverity.info,
            message: 'info message',
            context: context,
          ),
        ];

        // Should not throw
        PackErrorHandling.validateIssues(issues);
      });

      test('should log issues without throwing', () {
        final context = PackErrorHandling.packsizeContext();
        final issues = [
          ValidationIssue(
            severity: ValidationSeverity.warning,
            message: 'warning message',
            context: context,
          ),
          ValidationIssue(
            severity: ValidationSeverity.info,
            message: 'info message',
            context: context,
          ),
        ];

        // Should not throw (logging is silent in current implementation)
        PackErrorHandling.logIssues(issues);
      });
    });
  });
}
