@Tags(['core'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';

void main() {
  group('State Error Reporting', () {
    // test('reports error on unexpected input', () {
    //   // Provide input that is expected to fail parsing.
    //   var source = "invalid input";
    //   // We assume the parser is invoked via parse() in grammar_parser.dart.
    //   // Since our grammar is designed to parse a program, we expect it to throw a FormatException.
    //   expect(() => parse(source), throwsA(isA<FormatException>()));
    // });

    test('returns error spans with message', () {
      var source =
          "if true then 1"; // Incomplete if-statement missing else/end.
      try {
        final   a = parse(source);
        fail("Expected FormatException due to incomplete if statement.");
      } on FormatException catch (e) {
        var message = e.message;
        // Verify that error message contains expected hints (e.g., 'Expected').
        expect(message, contains("Expected"));
      }
    });
  });
}
