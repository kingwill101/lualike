import 'package:lualike_test/test.dart';

void main() {
  group('Goto with repeated loops', () {
    test('goto repeats a for loop until condition met', () async {
      var program = <AstNode>[
        LocalDeclaration([Identifier('i')], [], [NumberLiteral(0)]),
        Label(Identifier('doagain')),
        ForLoop(
          Identifier('j'),
          NumberLiteral(1),
          NumberLiteral(2),
          NumberLiteral(1),
          [
            Assignment(
              [Identifier('i')],
              [BinaryExpression(Identifier('i'), '+', NumberLiteral(1))],
            ),
          ],
        ),
        IfStatement(
          BinaryExpression(Identifier('i'), '<', NumberLiteral(5)),
          [],
          [Goto(Identifier('doagain'))],
          [],
        ),
        ExpressionStatement(Identifier('i')),
      ];

      var vm = Interpreter();
      await vm.run(program);
      expect(vm.globals.get('i'), equals(Value(6)));
    });
  });
}
