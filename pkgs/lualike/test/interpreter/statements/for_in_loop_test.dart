import 'package:lualike_test/test.dart';

void main() {
  group('ForInLoop', () {
    test('iterates over a list and sums values', () async {
      // Environment: local variable "sum" is updated in loop.
      // ForInLoop: for x in {1, 2, 3} do sum = sum + x end
      var init = LocalDeclaration([Identifier("sum")], [], [NumberLiteral(0)]);
      // ForInLoop: loop var x over a list [1,2,3]
      // Here, we simulate the iterator as a list literal.
      var loop = ForInLoop(
        [Identifier("x")],
        [
          TableConstructor([
            TableEntryLiteral(NumberLiteral(1)),
            TableEntryLiteral(NumberLiteral(2)),
            TableEntryLiteral(NumberLiteral(3)),
          ]),
        ],
        [
          FunctionCall(Identifier("print"), [StringLiteral(" in the loop")]),
          Assignment(
            [Identifier("sum")],
            [BinaryExpression(Identifier("sum"), "+", Identifier("x"))],
          ),
        ],
      );
      // Finally, read "sum"
      var read = Identifier("sum");
      var vm = Interpreter();
      await vm.run([init, loop]);
      var result = await read.accept(vm);
      // 0 + 1 + 2 + 3 = 6.
      expect((result as Value).raw, equals(6));
    });
  });
}
