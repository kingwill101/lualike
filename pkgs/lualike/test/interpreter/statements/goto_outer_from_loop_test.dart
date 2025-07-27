import 'package:lualike_test/test.dart';

void main() {
  group('Goto to outer label from inside loop', () {
    test('goto jumps from loop to outer label', () async {
      var program = <AstNode>[
        LocalDeclaration([Identifier('i')], [], [NumberLiteral(0)]),
        Label(Identifier('doagain')),
        ForLoop(
          Identifier('j'),
          NumberLiteral(1),
          NumberLiteral(5),
          NumberLiteral(1),
          [
            Assignment(
              [Identifier('i')],
              [BinaryExpression(Identifier('i'), '+', NumberLiteral(1))],
            ),
            IfStatement(
              BinaryExpression(Identifier('i'), '<', NumberLiteral(3)),
              [],
              [Goto(Identifier('doagain'))],
              [],
            ),
          ],
        ),
        ExpressionStatement(Identifier('i')),
      ];

      var vm = Interpreter();
      await vm.run(program);
      expect(vm.globals.get('i'), equals(Value(7)));
    });
  });
}
