import 'package:lualike_test/test.dart';

void main() {
  group('Goto and Label', () {
    test('goto jumps to label and skips intermediate statements', () async {
      // Program:
      // local x = 1;
      // goto L;
      // assignment: x = 2;   <-- This statement should be skipped.
      // label L:
      // ExpressionStatement: read x.

      var prog = <AstNode>[
        // local declare x = 1
        LocalDeclaration([Identifier("x")], [], [NumberLiteral(1)]),
        // goto L
        Goto(Identifier("L")),
        // This assignment should never execute.
        Assignment([Identifier('x')], [NumberLiteral(2)]),
        // label L
        Label(Identifier("L")),
        // Expression statement to read x.
        ExpressionStatement(Identifier("x")),
      ];

      var vm = Interpreter();
      await vm.run(prog);

      // Expect x to remain 1 since we jumped to label "L" skipping assignment x = 2.
      expect(vm.globals.get("x"), equals(Value(1)));
    });

    test('undefined label throws exception', () async {
      // Program with a goto referencing an undefined label.
      var prog = <AstNode>[
        // local declare x = 10
        LocalDeclaration([Identifier("x")], [], [NumberLiteral(10)]),
        // goto label "NoSuchLabel" which is not defined in the program.
        Goto(Identifier("NoSuchLabel")),
        // A dummy assignment (should not get executed).
        Assignment([Identifier('x')], [NumberLiteral(20)]),
      ];

      var vm = Interpreter();
      expect(
        () async => await vm.run(prog),
        throwsA(
          predicate(
            (e) =>
                e is GotoException &&
                e.toString().contains("Undefined label: NoSuchLabel"),
          ),
        ),
      );
    });

    test('goto can jump backward within the same block', () async {
      var prog = <AstNode>[
        LocalDeclaration([Identifier('x')], [], [NumberLiteral(0)]),
        Label(Identifier('loop')),
        Assignment(
          [Identifier('x')],
          [BinaryExpression(Identifier('x'), '+', NumberLiteral(1))],
        ),
        IfStatement(
          BinaryExpression(Identifier('x'), '<', NumberLiteral(3)),
          [],
          [Goto(Identifier('loop'))],
          [],
        ),
      ];

      var vm = Interpreter();
      await vm.run(prog);

      expect(vm.globals.get('x'), equals(Value(3)));
    });

    test('labels with same name are scoped per block', () async {
      var prog = <AstNode>[
        LocalDeclaration(
          [Identifier('x'), Identifier('y')],
          [],
          [NumberLiteral(0), NumberLiteral(5)],
        ),
        DoBlock([
          Label(Identifier('repeat')),
          Assignment(
            [Identifier('x')],
            [BinaryExpression(Identifier('x'), '+', NumberLiteral(1))],
          ),
          IfStatement(
            BinaryExpression(Identifier('x'), '<', NumberLiteral(3)),
            [],
            [Goto(Identifier('repeat'))],
            [],
          ),
        ]),
        DoBlock([
          Label(Identifier('repeat')),
          Assignment(
            [Identifier('y')],
            [BinaryExpression(Identifier('y'), '-', NumberLiteral(1))],
          ),
          IfStatement(
            BinaryExpression(Identifier('y'), '>', NumberLiteral(0)),
            [],
            [Goto(Identifier('repeat'))],
            [],
          ),
        ]),
      ];

      var vm = Interpreter();
      await vm.run(prog);

      expect(vm.globals.get('x'), equals(Value(3)));
      expect(vm.globals.get('y'), equals(Value(0)));
    });
  });
}
