import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/parsers/binary_format.dart';
import 'package:lualike/src/stdlib/binary_type_size.dart';
import 'package:test/test.dart';

void main() {
  group('BinaryFormatParser minimal/simple cases', () {
    test('greedy: I4', () {
      final options = BinaryFormatParser.parse('I4');
      expect(options.length, 1);
      expect(options[0].type, 'I');
      expect(options[0].size, 4);
    });
    test('greedy: n', () {
      final options = BinaryFormatParser.parse('n');
      expect(options.length, 1);
      expect(options[0].type, 'n');
    });
    test('required number: c10', () {
      final options = BinaryFormatParser.parse('c10');
      expect(options.length, 1);
      expect(options[0].type, 'c');
      expect(options[0].size, 10);
    });
    test('required number: c (error)', () {
      expect(() => BinaryFormatParser.parse('c'), throwsA(isA<LuaError>()));
    });
    test('z does not take number', () {
      final options = BinaryFormatParser.parse('z');
      expect(options.length, 1);
      expect(options[0].type, 'z');
    });
    test('z with number (error)', () {
      expect(() => BinaryFormatParser.parse('z10'), throwsA(isA<LuaError>()));
    });
    test('alignment: !4', () {
      final options = BinaryFormatParser.parse('!4');
      expect(options.length, 1);
      expect(options[0].type, '!');
      expect(options[0].align, 4);
    });
    test('alignment: ! (default)', () {
      final options = BinaryFormatParser.parse('!');
      expect(options.length, 1);
      expect(options[0].type, '!');
      expect(options[0].align, isNull);
    });
    test('alignment: !3 (not power of 2)', () {
      expect(() => BinaryFormatParser.parse('!3'), throwsA(isA<LuaError>()));
    });
    test('endianness: <I4', () {
      final options = BinaryFormatParser.parse('<I4');
      expect(options.length, 2);
      expect(options[0].type, '<');
      expect(options[1].type, 'I');
      expect(options[1].size, 4);
    });
    test('endianness: >I4', () {
      final options = BinaryFormatParser.parse('>I4');
      expect(options.length, 2);
      expect(options[0].type, '>');
      expect(options[1].type, 'I');
      expect(options[1].size, 4);
    });
    test('endianness: =I4', () {
      final options = BinaryFormatParser.parse('=I4');
      expect(options.length, 2);
      expect(options[0].type, '=');
      expect(options[1].type, 'I');
      expect(options[1].size, 4);
    });
    test('invalid option: Q', () {
      expect(() => BinaryFormatParser.parse('Q'), throwsA(isA<LuaError>()));
    });
    test('I without number', () {
      final options = BinaryFormatParser.parse('I');
      expect(options.length, 1);
      expect(options[0].type, 'I');
      expect(options[0].size, isNull);
    });
    test('multiple: I4c10z', () {
      final options = BinaryFormatParser.parse('I4c10z');
      expect(options.length, 3);
      expect(options[0].type, 'I');
      expect(options[0].size, 4);
      expect(options[1].type, 'c');
      expect(options[1].size, 10);
      expect(options[2].type, 'z');
    });
    test('multiple: I4I8', () {
      final options = BinaryFormatParser.parse('I4I8');
      expect(options.length, 2);
      expect(options[0].type, 'I');
      expect(options[0].size, 4);
      expect(options[1].type, 'I');
      expect(options[1].size, 8);
    });
    test('empty string', () {
      final options = BinaryFormatParser.parse('');
      expect(options, isEmpty);
    });
    test('whitespace only', () {
      final options = BinaryFormatParser.parse('   ');
      expect(options, isEmpty);
    });
  });

  group('BinaryFormatParser', () {
    test('parses simple valid format', () {
      final options = BinaryFormatParser.parse('i4c10z');
      expect(options.length, 3);
      expect(options[0].type, 'i');
      expect(options[0].size, 4);
      expect(options[1].type, 'c');
      expect(options[1].size, 10);
      expect(options[2].type, 'z');
    });

    test('parses endianness and alignment', () {
      final options = BinaryFormatParser.parse('<i2>i4=i4!8d');
      expect(options[0].type, '<');
      expect(options[1].type, 'i');
      expect(options[1].size, 2);
      expect(options[2].type, '>');
      expect(options[3].type, 'i');
      expect(options[3].size, 4);
      expect(options[4].type, '=');
      expect(options[5].type, 'i');
      expect(options[6].type, '!');
      expect(options[6].align, 8);
      expect(options[7].type, 'd');
    });

    test('parses all simple types', () {
      final options = BinaryFormatParser.parse('bBhHlLjJTdnis8xXh');
      expect(options.map((o) => o.type).join(), 'bBhHlLjJTdnisxX');
      expect(options[12].type, 's');
      expect(options[12].size, 8);
      expect(options.last.type, 'X');
      expect(options.last.size, BinaryTypeSize.h);
    });

    test('X with non-alignable type errors', () {
      expect(() => BinaryFormatParser.parse('Xz'), throwsA(isA<LuaError>()));
    });

    test('ignores spaces', () {
      final options = BinaryFormatParser.parse('  i4   c10  z  ');
      expect(options.length, 3);
      expect(options[0].type, 'i');
      expect(options[1].type, 'c');
      expect(options[2].type, 'z');
    });

    test('throws on missing number for c', () {
      expect(() => BinaryFormatParser.parse('c'), throwsA(isA<LuaError>()));
    });

    test('throws on number for b', () {
      expect(() => BinaryFormatParser.parse('b4'), throwsA(isA<LuaError>()));
    });

    test('throws on number for z', () {
      expect(() => BinaryFormatParser.parse('z2'), throwsA(isA<LuaError>()));
    });

    test('throws on alignment not power of 2', () {
      expect(() => BinaryFormatParser.parse('!3'), throwsA(isA<LuaError>()));
    });

    test('throws on integral size out of range', () {
      expect(() => BinaryFormatParser.parse('i17'), throwsA(isA<LuaError>()));
    });

    test('throws on negative size for c', () {
      expect(() => BinaryFormatParser.parse('c-1'), throwsA(isA<LuaError>()));
    });

    test('throws on unknown option', () {
      expect(() => BinaryFormatParser.parse('q'), throwsA(isA<LuaError>()));
    });

    test('parses empty format string', () {
      final options = BinaryFormatParser.parse('');
      expect(options, isEmpty);
    });
  });
}
