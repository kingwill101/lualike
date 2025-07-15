import 'package:lualike/src/stdlib/pack_size_calculator.dart';
import 'package:lualike/src/parsers/binary_format.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:test/test.dart';

/// Unit tests for PackSizeCalculator class.
///
/// These tests focus on the centralized size calculation logic with overflow
/// detection, alignment handling, and format option processing.
void main() {
  group('PackSizeCalculator', () {
    late PackSizeCalculator calculator;

    setUp(() {
      calculator = PackSizeCalculator();
    });

    group('Basic Size Calculation', () {
      test('should start with zero size', () {
        expect(calculator.totalSize, equals(BigInt.zero));
        expect(calculator.currentOffset, equals(BigInt.zero));
        expect(calculator.maxAlign, equals(1));
      });

      test('should reset to initial state', () {
        calculator.addUnaligned(10);
        calculator.setAlignment(4);

        calculator.reset();

        expect(calculator.totalSize, equals(BigInt.zero));
        expect(calculator.currentOffset, equals(BigInt.zero));
        expect(calculator.maxAlign, equals(1));
      });

      test('should add unaligned sizes correctly', () {
        calculator.addUnaligned(5);
        expect(calculator.totalSize, equals(BigInt.from(5)));

        calculator.addUnaligned(3);
        expect(calculator.totalSize, equals(BigInt.from(8)));
      });

      test('should add sized elements with alignment', () {
        calculator.addSized(4); // 4-byte integer
        expect(calculator.totalSize, equals(BigInt.from(4)));

        calculator.addSized(2); // 2-byte short (aligned to 2-byte boundary)
        expect(calculator.totalSize, equals(BigInt.from(6)));
      });
    });

    group('Alignment Handling', () {
      test('should set and validate alignment', () {
        calculator.setAlignment(4);
        expect(calculator.maxAlign, equals(4));

        calculator.setAlignment(8);
        expect(calculator.maxAlign, equals(8));
      });

      test('should reject invalid alignments', () {
        expect(() => calculator.setAlignment(0), throwsA(isA<LuaError>()));
        expect(() => calculator.setAlignment(3), throwsA(isA<LuaError>()));
        expect(() => calculator.setAlignment(17), throwsA(isA<LuaError>()));
      });

      test('should reset alignment to default', () {
        calculator.setAlignment(8);
        calculator.resetAlignment();
        expect(calculator.maxAlign, equals(8)); // Native integer size
      });

      test('should calculate alignment padding correctly', () {
        calculator.setAlignment(4); // Set max alignment to 4
        calculator.addUnaligned(1); // offset = 1
        final padding = calculator.calculateAlignmentPadding(4);
        expect(padding, equals(BigInt.from(3))); // Need 3 bytes to align to 4
      });

      test('should add alignment padding', () {
        calculator.setAlignment(4); // Set max alignment to 4
        calculator.addUnaligned(1); // offset = 1
        calculator.addAlignmentPadding(4); // Add padding to align to 4
        expect(calculator.totalSize, equals(BigInt.from(4)));
      });
    });

    group('Overflow Detection', () {
      test('should detect overflow in addUnaligned', () {
        calculator.addUnaligned(0x7ffffff0); // Near max

        expect(
          () => calculator.addUnaligned(0x20), // Would overflow
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('too large'),
            ),
          ),
        );
      });

      test('should detect overflow in addSized', () {
        calculator.addUnaligned(0x7ffffff0); // Near max

        expect(
          () => calculator.addSized(0x20), // Would overflow
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('too large'),
            ),
          ),
        );
      });

      test('should detect overflow in alignment padding', () {
        // Set offset very close to max and alignment that would cause overflow
        calculator.setAlignment(8); // Set max alignment to 8
        calculator.addUnaligned(0x7ffffffc);

        expect(
          () => calculator.addAlignmentPadding(
            8,
          ), // Would need padding that overflows
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('too large'),
            ),
          ),
        );
      });

      test('should allow operations at exact limit', () {
        calculator.addUnaligned(0x7fffffff); // Exactly at limit
        expect(calculator.totalSize, equals(BigInt.from(0x7fffffff)));
      });
    });

    group('Format Option Processing', () {
      test('should process endianness options', () {
        final options = [
          BinaryFormatOption('<', raw: '<'),
          BinaryFormatOption('>', raw: '>'),
          BinaryFormatOption('=', raw: '='),
        ];

        for (final option in options) {
          calculator.processFormatOption(option);
          // Endianness doesn't affect size
          expect(calculator.totalSize, equals(BigInt.zero));
        }
      });

      test('should process alignment options', () {
        final resetOption = BinaryFormatOption('!', raw: '!');
        calculator.processFormatOption(resetOption);

        final alignOption = BinaryFormatOption('!', align: 4, raw: '!4');
        calculator.processFormatOption(alignOption);
        expect(calculator.maxAlign, equals(4));
      });

      test('should process integer options', () {
        final intOptions = [
          BinaryFormatOption('b', raw: 'b'),
          BinaryFormatOption('B', raw: 'B'),
          BinaryFormatOption('h', raw: 'h'),
          BinaryFormatOption('H', raw: 'H'),
          BinaryFormatOption('i', size: 4, raw: 'i4'),
          BinaryFormatOption('I', size: 8, raw: 'I8'),
        ];

        BigInt expectedSize = BigInt.zero;
        for (final option in intOptions) {
          calculator.processFormatOption(option);
          expect(calculator.totalSize, greaterThan(expectedSize));
          expectedSize = calculator.totalSize;
        }
      });

      test('should process string options', () {
        final cOption = BinaryFormatOption('c', size: 10, raw: 'c10');
        calculator.processFormatOption(cOption);
        expect(calculator.totalSize, equals(BigInt.from(10)));

        // Variable-length options don't contribute to size
        final sOption = BinaryFormatOption('s', raw: 's');
        calculator.processFormatOption(sOption);
        expect(calculator.totalSize, equals(BigInt.from(10))); // Unchanged
      });

      test('should process X alignment option', () {
        calculator.setAlignment(4); // Set max alignment to 4
        calculator.addUnaligned(1); // offset = 1

        final xOption = BinaryFormatOption('X', size: 4, raw: 'X4');
        calculator.processFormatOption(xOption);

        expect(calculator.totalSize, equals(BigInt.from(4))); // Aligned to 4
      });

      test('should handle X option with next option', () {
        calculator.setAlignment(4); // Set max alignment to 4
        calculator.addUnaligned(1); // offset = 1

        final xOption = BinaryFormatOption('X', raw: 'X');
        final nextOption = BinaryFormatOption('i', size: 4, raw: 'i4');

        calculator.processFormatOption(xOption, nextOption: nextOption);

        expect(calculator.totalSize, equals(BigInt.from(4))); // Aligned to 4
      });

      test('should reject X option without next option', () {
        final xOption = BinaryFormatOption('X', raw: 'X');

        expect(
          () => calculator.processFormatOption(xOption),
          throwsA(
            predicate(
              (e) =>
                  e is LuaError && e.toString().contains('invalid next option'),
            ),
          ),
        );
      });

      test('should reject invalid format options', () {
        final invalidOption = BinaryFormatOption('q', raw: 'q');

        expect(
          () => calculator.processFormatOption(invalidOption),
          throwsA(
            predicate(
              (e) =>
                  e is LuaError &&
                  e.toString().contains('invalid format option'),
            ),
          ),
        );
      });

      test('should reject c option without size', () {
        final cOption = BinaryFormatOption('c', raw: 'c');

        expect(
          () => calculator.processFormatOption(cOption),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('missing size'),
            ),
          ),
        );
      });
    });

    group('Static Methods', () {
      test('calculateSize should process option list', () {
        final options = [
          BinaryFormatOption('i', size: 4, raw: 'i4'),
          BinaryFormatOption('h', raw: 'h'),
          BinaryFormatOption('c', size: 10, raw: 'c10'),
        ];

        final size = PackSizeCalculator.calculateSize(options);
        expect(size, greaterThan(BigInt.from(15))); // At least 4 + 2 + 10
      });

      test('calculateSize should handle empty list', () {
        final size = PackSizeCalculator.calculateSize([]);
        expect(size, equals(BigInt.zero));
      });

      test('calculateSize should detect overflow', () {
        final options = [
          BinaryFormatOption('c', size: 0x40000000, raw: 'c1073741824'),
          BinaryFormatOption('c', size: 0x40000000, raw: 'c1073741824'),
        ];

        expect(
          () => PackSizeCalculator.calculateSize(options),
          throwsA(
            predicate(
              (e) => e is LuaError && e.toString().contains('too large'),
            ),
          ),
        );
      });

      test('validateFormatSize should validate format strings', () {
        // Valid format should not throw
        PackSizeCalculator.validateFormatSize('i4hc10');

        // Invalid format should throw
        expect(
          () => PackSizeCalculator.validateFormatSize('q'),
          throwsA(isA<LuaError>()),
        );
      });
    });

    group('Complex Scenarios', () {
      test('should handle complex format with alignment', () {
        final options = [
          BinaryFormatOption('!', align: 8, raw: '!8'),
          BinaryFormatOption('b', raw: 'b'),
          BinaryFormatOption('i', size: 4, raw: 'i4'),
          BinaryFormatOption('d', raw: 'd'),
          BinaryFormatOption('c', size: 5, raw: 'c5'),
        ];

        final size = PackSizeCalculator.calculateSize(options);
        expect(size, greaterThan(BigInt.from(18))); // With alignment padding
      });

      test('should handle endianness changes', () {
        final options = [
          BinaryFormatOption('<', raw: '<'),
          BinaryFormatOption('i', size: 4, raw: 'i4'),
          BinaryFormatOption('>', raw: '>'),
          BinaryFormatOption('i', size: 4, raw: 'i4'),
          BinaryFormatOption('=', raw: '='),
          BinaryFormatOption('i', size: 4, raw: 'i4'),
        ];

        final size = PackSizeCalculator.calculateSize(options);
        expect(size, equals(BigInt.from(12))); // 3 * 4 bytes
      });

      test('should handle multiple X alignments', () {
        final options = [
          BinaryFormatOption('b', raw: 'b'),
          BinaryFormatOption('X', size: 4, raw: 'X4'),
          BinaryFormatOption('i', size: 4, raw: 'i4'),
          BinaryFormatOption('X', size: 8, raw: 'X8'),
          BinaryFormatOption('d', raw: 'd'),
        ];

        final size = PackSizeCalculator.calculateSize(options);
        expect(
          size,
          greaterThanOrEqualTo(BigInt.from(13)),
        ); // With alignment padding
      });

      test('should accumulate size correctly with mixed options', () {
        final options = [
          BinaryFormatOption('!', align: 4, raw: '!4'),
          BinaryFormatOption('b', raw: 'b'), // 1 byte
          BinaryFormatOption('x', raw: 'x'), // 1 padding byte
          BinaryFormatOption('h', raw: 'h'), // 2 bytes (aligned)
          BinaryFormatOption('c', size: 3, raw: 'c3'), // 3 bytes
          BinaryFormatOption('i', size: 4, raw: 'i4'), // 4 bytes (aligned)
        ];

        final size = PackSizeCalculator.calculateSize(options);
        // Should be at least 1 + 1 + 2 + 3 + 4 = 11, plus alignment padding
        expect(size, greaterThanOrEqualTo(BigInt.from(11)));
      });
    });
  });
}
