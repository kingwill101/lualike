import 'package:lualike/testing.dart';

void main() {
  group('DoBlock', () {
    test('do block returns the value of last expression', () async {
      // Use do block to execute two statements, last is an expression that returns a value.
      var block = DoBlock([
        Assignment([Identifier("a")], [NumberLiteral(10)]),
        BinaryExpression(Identifier("a"), "+", NumberLiteral(5)),
      ]);
      var vm = Interpreter();
      var result = await block.accept(vm);
      // Expect that the final statement (a+5) evaluates to 15.
      expect(result, equals(Value(15)));
    });
  });

  group('Break Statement in While Loop', () {
    test('break exits the loop early', () async {
      // Define: local count = 0; while true do count = count + 1; if count > 3 then break; end; end;
      var declare = LocalDeclaration(
        [Identifier("count")],
        [],
        [NumberLiteral(0)],
      );
      var assign = Assignment(
        [Identifier("count")],
        [BinaryExpression(Identifier("count"), "+", NumberLiteral(1))],
      );
      // if count > 3 then break end
      var condition = BinaryExpression(
        Identifier("count"),
        ">",
        NumberLiteral(3),
      );

      // Adjusting: Since our current VM for if does not support break in then block,
      // we'll simply invoke a Break() statement after checking condition inside while loop.
      var whileLoop = WhileStatement(BooleanLiteral(true), [
        assign,
        // if (count > 3) then break end. We use an if statement:
        IfStatement(condition, [], [Break()], []),
      ]);
      // After loop, read count.
      var read = Identifier("count");
      var vm = Interpreter();
      await vm.run([declare, whileLoop]);
      var result = await read.accept(vm);
      // The loop should break once count > 3, so expected count is 4.
      expect(result, equals(Value(4)));
    });
  });
}
