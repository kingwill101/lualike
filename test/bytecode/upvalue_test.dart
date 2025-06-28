@Tags(['bytecode'])
import 'package:lualike/lualike.dart';
import 'package:lualike/bytecode.dart';
import 'package:test/test.dart';

void main() {
  group('Upvalue handling', () {
    test('captures local variable in closure', () async {
      final ast = [
        // local x = 1
        LocalDeclaration([Identifier('x')], [], [NumberLiteral(1)]),
        // local function f() return x end
        LocalFunctionDef(
          Identifier('f'),
          FunctionBody([], [
            ReturnStatement([Identifier('x')]),
          ], false),
        ),
      ];

      final compiler = Compiler();
      final chunk = await compiler.compile(ast);

      // Find the closure creation
      final closureInst = chunk.instructions.firstWhere(
        (i) => i.op == OpCode.CLOSURE,
      );

      // Verify upvalue info in operands
      expect(closureInst.operands.length, greaterThan(1));
      expect(closureInst.operands[1], equals(1)); // One upvalue
      expect(closureInst.operands[2], isTrue); // Is local
    });

    test('handles nested closures', () async {
      final ast = [
        // local x = 1
        LocalDeclaration([Identifier('x')], [], [NumberLiteral(1)]),
        // local function outer()
        //   local y = 2
        //   return function() return x + y end
        // end
        LocalFunctionDef(
          Identifier('outer'),
          FunctionBody([], [
            LocalDeclaration([Identifier('y')], [], [NumberLiteral(2)]),
            ReturnStatement([
              FunctionLiteral(
                FunctionBody([], [
                  ReturnStatement([
                    BinaryExpression(Identifier('x'), '+', Identifier('y')),
                  ]),
                ], false),
              ),
            ]),
          ], false),
        ),
      ];

      final compiler = Compiler();
      final chunk = await compiler.compile(ast);

      // Find all CLOSURE instructions
      final closures = chunk.instructions
          .where((i) => i.op == OpCode.CLOSURE)
          .toList();

      // Should have two closures
      expect(closures.length, equals(2));

      // Inner closure should have two upvalues
      expect(closures[1].operands[1], equals(2));
    });

    test('handles upvalue closing', () async {
      final ast = [
        // local function counter()
        //   local count = 0
        //   return function() count = count + 1; return count end
        // end
        LocalFunctionDef(
          Identifier('counter'),
          FunctionBody([], [
            LocalDeclaration([Identifier('count')], [], [NumberLiteral(0)]),
            ReturnStatement([
              FunctionLiteral(
                FunctionBody([], [
                  Assignment(
                    [Identifier('count')],
                    [
                      BinaryExpression(
                        Identifier('count'),
                        '+',
                        NumberLiteral(1),
                      ),
                    ],
                  ),
                  ReturnStatement([Identifier('count')]),
                ], false),
              ),
            ]),
          ], false),
        ),
      ];

      final compiler = Compiler();
      final chunk = await compiler.compile(ast);

      // Verify that the inner function references count through an upvalue
      final functionChunk = chunk.constants.whereType<BytecodeChunk>().last;
      expect(
        functionChunk.instructions.map((i) => i.op),
        containsAllInOrder([
          OpCode.GETUPVAL,
          OpCode.LOAD_CONST, // 1
          OpCode.ADD,
          OpCode.SETUPVAL,
          OpCode.GETUPVAL,
          OpCode.RETURN,
        ]),
      );
    });
  });
}
