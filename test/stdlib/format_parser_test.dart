import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lualike/src/stdlib/format_parser.dart';

void main() {
  group('FormatStringParser', () {
    group('.escape', () {
      test('handles simple strings', () {
        final bytes = Uint8List.fromList('hello'.codeUnits);
        expect(FormatStringParser.escape(bytes), 'hello');
      });

      test('escapes double quotes', () {
        final bytes = Uint8List.fromList('"hello"'.codeUnits);
        expect(FormatStringParser.escape(bytes), r'\"hello\"');
      });

      test('escapes backslashes', () {
        final bytes = Uint8List.fromList(r'a\b'.codeUnits);
        expect(FormatStringParser.escape(bytes), r'a\\b');
      });

      test('escapes newlines', () {
        final bytes = Uint8List.fromList('a\nb'.codeUnits);
        expect(FormatStringParser.escape(bytes), 'a\\\nb');
      });

      test('escapes control characters', () {
        final bytes = Uint8List.fromList([1, 2, 31]);
        expect(FormatStringParser.escape(bytes), r'\1\2\31');
      });

      test('escapes non-printable ascii', () {
        final bytes = Uint8List.fromList([127, 255]);
        expect(FormatStringParser.escape(bytes), '\\127\\255');
      });

      test('handles mixed characters', () {
        final bytes = Uint8List.fromList('a"\n\b\\c\x01'.codeUnits);
        expect(
          FormatStringParser.escape(bytes),
          r'a\"'
          '\\\n'
          r'\8\\c\1',
        );
      });

      test('handles null byte specifically', () {
        final bytes = Uint8List.fromList([0]);
        expect(FormatStringParser.escape(bytes), r'\0');
      });

      test('handles safe extended ASCII without escaping', () {
        final bytes = Uint8List.fromList([224]); // à in Latin-1 (safe byte)
        expect(FormatStringParser.escape(bytes), 'à');
      });

      test('escapes extended ASCII that causes round-trip issues', () {
        final bytes = Uint8List.fromList([
          225,
        ]); // byte 225 causes round-trip issues
        expect(FormatStringParser.escape(bytes), '\\225');
      });
    });

    void expectParts(String input, List<Type> expectedTypes) {
      final parts = FormatStringParser.parse(input);
      expect(
        parts.length,
        expectedTypes.length,
        reason: 'Expected ${expectedTypes.length} parts, got ${parts.length}',
      );
      for (var i = 0; i < parts.length; i++) {
        if (expectedTypes[i] == LiteralPart) {
          expect(
            parts[i],
            isA<LiteralPart>(),
            reason:
                'Part $i should be LiteralPart, got ${parts[i].runtimeType}',
          );
        } else if (expectedTypes[i] == SpecifierPart) {
          expect(
            parts[i],
            isA<SpecifierPart>(),
            reason:
                'Part $i should be SpecifierPart, got ${parts[i].runtimeType}',
          );
        } else {
          fail('Unknown expected type: ${expectedTypes[i]}');
        }
      }
    }

    test('parses simple literal', () {
      expectParts('hello world', [LiteralPart]);
    });

    test('parses single specifier', () {
      expectParts('%d', [SpecifierPart]);
    });

    test('parses literal and specifier', () {
      expectParts('foo %s bar', [LiteralPart, SpecifierPart, LiteralPart]);
    });

    test('parses multiple specifiers', () {
      expectParts('%d %s %q', [
        SpecifierPart,
        LiteralPart,
        SpecifierPart,
        LiteralPart,
        SpecifierPart,
      ]);
    });

    test('parses single specifier %p', () {
      final part = FormatStringParser.parse('%p')[0];
      expect(part, isA<SpecifierPart>());
      expect((part as SpecifierPart).specifier, 'p');
      expect((part).flags, '');
      expect(part.width, isNull);
      expect(part.precision, isNull);
    });

    test('parses flags, width, precision', () {
      final part = FormatStringParser.parse('%-+ 0#10.5f')[0];
      expect(part, isA<SpecifierPart>());
      final s = part as SpecifierPart;
      expect(s.flags, '-+ 0#');
      expect(s.width, '10');
      expect(s.precision, '.5');
      expect(s.specifier, 'f');
    });

    test('parses %% as specifier', () {
      final part = FormatStringParser.parse('%%')[0];
      expect(part, isA<SpecifierPart>());
      expect((part as SpecifierPart).specifier, '%');
    });

    test('parses complex format string', () {
      final input = 'foo %10.2f bar %q baz %% end';
      final parts = FormatStringParser.parse(input);
      expect(parts.length, 7);
      expect(parts[0], isA<LiteralPart>());
      expect(parts[1], isA<SpecifierPart>());
      expect(parts[2], isA<LiteralPart>());
      expect(parts[3], isA<SpecifierPart>());
      expect(parts[4], isA<LiteralPart>());
      expect(parts[5], isA<SpecifierPart>());
      expect(parts[6], isA<LiteralPart>());
    });

    test('throws on invalid format', () {
      expect(() => FormatStringParser.parse('%'), throwsFormatException);
      expect(() => FormatStringParser.parse('%z'), throwsFormatException);
    });
  });
}
