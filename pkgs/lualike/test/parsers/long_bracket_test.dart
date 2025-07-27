import 'package:test/test.dart';
import 'package:lualike/src/parsers/lua.dart';
import 'package:lualike/src/ast.dart';

void main() {
  group('Long bracket literals and comments', () {
    test('parses various long-string delimiters and contents', () {
      const src = '''
        local a = [[simple]]
        local b = [=[nested]=]
        local c = [==[even deeper]==]
      ''';

      final program = parse(src);
      final Map<String, StringLiteral> bindings = {};

      for (final stmt in program.statements) {
        if (stmt is LocalDeclaration) {
          for (var i = 0; i < stmt.names.length; i++) {
            final name = stmt.names[i].name;
            final expr = stmt.exprs.isNotEmpty ? stmt.exprs[i] : null;
            if (expr is StringLiteral) {
              bindings[name] = expr;
            }
          }
        }
      }

      expect(bindings['a']?.value, equals('simple'));
      expect(bindings['b']?.value, equals('nested'));
      expect(bindings['c']?.value, equals('even deeper'));

      // Ensure they were recognised as long strings (no escape processing).
      expect(bindings['a']?.isLongString, isTrue);
      expect(bindings['b']?.isLongString, isTrue);
      expect(bindings['c']?.isLongString, isTrue);
    });

    test('parses long comments with = nesting', () {
      const src = '''
        --[[ basic comment ]]
        --[=[ nested = comment ]=]
        --[==[ deeper comment ]==]
        local x = 1
      ''';
      expect(() => parse(src), returnsNormally);
    });

    test('parses multi-line long strings', () {
      const src = '''
        local m = [[first line
second line]]
        local n = [=[line A
line B
line C]=]
      ''';

      final program = parse(src);

      final Map<String, StringLiteral> bindings = {};

      for (final stmt in program.statements) {
        if (stmt is LocalDeclaration) {
          for (var i = 0; i < stmt.names.length; i++) {
            final name = stmt.names[i].name;
            final expr = stmt.exprs.isNotEmpty ? stmt.exprs[i] : null;
            if (expr is StringLiteral) bindings[name] = expr;
          }
        }
      }

      expect(bindings['m']?.value, equals('first line\nsecond line'));
      expect(bindings['n']?.value, equals('line A\nline B\nline C'));

      expect(bindings['m']?.isLongString, isTrue);
      expect(bindings['n']?.isLongString, isTrue);
    });
  });
}
