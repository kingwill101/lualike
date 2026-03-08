import 'package:lualike/src/ast.dart';
import 'package:lualike/src/ast_dump.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('global declarations', () {
    test('parses wildcard global declarations with a default attribute', () {
      final program = parse('global<const> *');
      final declaration = program.statements.single as GlobalDeclaration;

      expect(declaration.isWildcard, isTrue);
      expect(declaration.defaultAttribute, equals('const'));
      expect(declaration.names, isEmpty);
      expect(declaration.exprs, isEmpty);
    });

    test('parses named global declarations with per-name attributes', () {
      final program = parse('global a, b <const>, c = 1, 2, 3');
      final declaration = program.statements.single as GlobalDeclaration;

      expect(declaration.isWildcard, isFalse);
      expect(
        declaration.names.map((identifier) => identifier.name).toList(),
        equals(['a', 'b', 'c']),
      );
      expect(declaration.attributes, equals(['', 'const', '']));
      expect(declaration.exprs, hasLength(3));
    });

    test('parses global function definitions as explicit globals', () {
      final program = parse('global function foo(x) return x end');
      final function = program.statements.single as FunctionDef;

      expect(function.explicitGlobal, isTrue);
      expect(function.name.first.name, equals('foo'));
      expect(function.body.parameters?.single.name, equals('x'));
    });

    test('round-trips dumped global declarations', () {
      final original = parse('global<const> print, assert');
      final restored = undumpAst(original.dump()) as Program;
      final declaration = restored.statements.single as GlobalDeclaration;

      expect(declaration.defaultAttribute, equals('const'));
      expect(
        declaration.names.map((identifier) => identifier.name).toList(),
        equals(['print', 'assert']),
      );
    });

    test('keeps global usable as an identifier outside statement syntax', () {
      final program = parse('global = 1; return global');

      expect(program.statements.first, isA<Assignment>());
      final assignment = program.statements.first as Assignment;
      expect((assignment.targets.single as Identifier).name, equals('global'));

      final returned = program.statements.last as ReturnStatement;
      expect((returned.expr.single as Identifier).name, equals('global'));
    });

    test('parses local<const> compact default attributes', () {
      final program = parse('local<const> foo, bar <close>, baz = 1, 2, 3');
      final declaration = program.statements.single as LocalDeclaration;

      expect(
        declaration.names.map((identifier) => identifier.name).toList(),
        equals(['foo', 'bar', 'baz']),
      );
      expect(declaration.attributes, equals(['const', 'close', 'const']));
      expect(declaration.exprs, hasLength(3));
    });
  });
}
