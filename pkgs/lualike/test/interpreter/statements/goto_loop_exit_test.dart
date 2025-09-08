import 'package:lualike_test/test.dart';

void main() {
  group('Goto with loops', () {
    test('goto exits a for loop to outer label', () async {
      var program = <AstNode>[
        Assignment([Identifier('i')], [NumberLiteral(0)]),
        Label(Identifier('again')),
        ForLoop(
          Identifier('j'),
          NumberLiteral(1),
          NumberLiteral(10),
          NumberLiteral(1),
          [
            Assignment(
              [Identifier('i')],
              [BinaryExpression(Identifier('i'), '+', NumberLiteral(1))],
            ),
            IfStatement(
              BinaryExpression(Identifier('i'), '>=', NumberLiteral(5)),
              [],
              [Goto(Identifier('done'))],
              [],
            ),
          ],
        ),
        Goto(Identifier('again')),
        Label(Identifier('done')),
        ExpressionStatement(Identifier('i')),
      ];

      var vm = Interpreter();
      await vm.run(program);
      expect(vm.globals.get('i'), equals(Value(5)));
    });
  });
}
