import 'package:lualike/src/ast.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('number literals', () {
    test('parses decimal and hexadecimal numeric forms', () {
      final program = parse('return 123, 1.5, .5, 1e3, 1.e-2, 0xFF, 0x1.8p+4');
      final statement = program.statements.single as ReturnStatement;
      final values = statement.expr.cast<NumberLiteral>().map((literal) {
        return literal.value;
      }).toList();

      expect(values, equals([123, 1.5, 0.5, 1000.0, 0.01, 255, 24.0]));
    });

    test('rejects malformed numeric suffixes', () {
      expect(() => parse('return 0x.'), throwsA(isA<FormatException>()));
      expect(() => parse('return 1..2'), throwsA(isA<FormatException>()));
    });
  });
}
