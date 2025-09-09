import 'package:test/test.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/ast_dump.dart';

void main() {
  group('AST Dump/Restore Tests', () {
    test('NilValue dump/restore', () {
      final original = NilValue();
      final dumped = original.dump();
      final restored = undumpAst(dumped) as NilValue;

      expect(restored.toSource(), equals(original.toSource()));
    });

    test('BooleanLiteral dump/restore', () {
      final original = BooleanLiteral(true);
      final dumped = original.dump();
      final restored = undumpAst(dumped) as BooleanLiteral;

      expect(restored.value, equals(original.value));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('NumberLiteral dump/restore', () {
      final original = NumberLiteral(42.5);
      final dumped = original.dump();
      final restored = undumpAst(dumped) as NumberLiteral;

      expect(restored.value, equals(original.value));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('StringLiteral dump/restore', () {
      final original = StringLiteral('hello world');
      final dumped = original.dump();
      final restored = undumpAst(dumped) as StringLiteral;

      expect(restored.value, equals(original.value));
      expect(restored.isLongString, equals(original.isLongString));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('Identifier dump/restore', () {
      final original = Identifier('myVar');
      final dumped = original.dump();
      final restored = undumpAst(dumped) as Identifier;

      expect(restored.name, equals(original.name));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('BinaryExpression dump/restore', () {
      final left = NumberLiteral(10);
      final right = NumberLiteral(20);
      final original = BinaryExpression(left, '+', right);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as BinaryExpression;

      expect(restored.op, equals(original.op));
      expect((restored.left as NumberLiteral).value, equals(10));
      expect((restored.right as NumberLiteral).value, equals(20));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('UnaryExpression dump/restore', () {
      final expr = NumberLiteral(5);
      final original = UnaryExpression('-', expr);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as UnaryExpression;

      expect(restored.op, equals(original.op));
      expect((restored.expr as NumberLiteral).value, equals(5));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('Assignment dump/restore', () {
      final target = Identifier('x');
      final value = NumberLiteral(100);
      final original = Assignment([target], [value]);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as Assignment;

      expect(restored.targets.length, equals(1));
      expect(restored.exprs.length, equals(1));
      expect((restored.targets[0] as Identifier).name, equals('x'));
      expect((restored.exprs[0] as NumberLiteral).value, equals(100));
    });

    test('FunctionCall dump/restore', () {
      final name = Identifier('print');
      final arg = StringLiteral('hello');
      final original = FunctionCall(name, [arg]);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as FunctionCall;

      expect((restored.name as Identifier).name, equals('print'));
      expect(restored.args.length, equals(1));
      expect((restored.args[0] as StringLiteral).value, equals('hello'));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('ReturnStatement dump/restore', () {
      final expr = NumberLiteral(42);
      final original = ReturnStatement([expr]);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as ReturnStatement;

      expect(restored.expr.length, equals(1));
      expect((restored.expr[0] as NumberLiteral).value, equals(42));
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('TableConstructor dump/restore', () {
      final entry1 = KeyedTableEntry(Identifier('name'), StringLiteral('John'));
      final entry2 = IndexedTableEntry(
        NumberLiteral(1),
        StringLiteral('first'),
      );
      final entry3 = TableEntryLiteral(NumberLiteral(100));
      final original = TableConstructor([entry1, entry2, entry3]);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as TableConstructor;

      expect(restored.entries.length, equals(3));

      final restoredEntry1 = restored.entries[0] as KeyedTableEntry;
      expect((restoredEntry1.key as Identifier).name, equals('name'));
      expect((restoredEntry1.value as StringLiteral).value, equals('John'));

      final restoredEntry2 = restored.entries[1] as IndexedTableEntry;
      expect((restoredEntry2.key as NumberLiteral).value, equals(1));
      expect((restoredEntry2.value as StringLiteral).value, equals('first'));

      final restoredEntry3 = restored.entries[2] as TableEntryLiteral;
      expect((restoredEntry3.expr as NumberLiteral).value, equals(100));
    });

    test('FunctionLiteral dump/restore', () {
      final param = Identifier('x');
      final returnStmt = ReturnStatement([Identifier('x')]);
      final funcBody = FunctionBody([param], [returnStmt], false);
      final original = FunctionLiteral(funcBody);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as FunctionLiteral;

      expect(restored.funcBody.parameters?.length, equals(1));
      expect(restored.funcBody.parameters?[0].name, equals('x'));
      expect(restored.funcBody.body.length, equals(1));
      expect(restored.funcBody.isVararg, equals(false));
    });

    test('Program dump/restore', () {
      final stmt1 = Assignment([Identifier('x')], [NumberLiteral(10)]);
      final stmt2 = ReturnStatement([Identifier('x')]);
      final original = Program([stmt1, stmt2]);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as Program;

      expect(restored.statements.length, equals(2));
      expect(restored.statements[0] is Assignment, isTrue);
      expect(restored.statements[1] is ReturnStatement, isTrue);
    });

    test('Complex nested expression dump/restore', () {
      // Create: (x + 5) * (y - 2)
      final x = Identifier('x');
      final five = NumberLiteral(5);
      final y = Identifier('y');
      final two = NumberLiteral(2);

      final left = BinaryExpression(x, '+', five);
      final right = BinaryExpression(y, '-', two);
      final original = BinaryExpression(left, '*', right);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as BinaryExpression;

      expect(restored.op, equals('*'));

      final restoredLeft = restored.left as BinaryExpression;
      expect(restoredLeft.op, equals('+'));
      expect((restoredLeft.left as Identifier).name, equals('x'));
      expect((restoredLeft.right as NumberLiteral).value, equals(5));

      final restoredRight = restored.right as BinaryExpression;
      expect(restoredRight.op, equals('-'));
      expect((restoredRight.left as Identifier).name, equals('y'));
      expect((restoredRight.right as NumberLiteral).value, equals(2));

      expect(restored.toSource(), equals(original.toSource()));
    });

    test('IfStatement dump/restore', () {
      final cond = BinaryExpression(Identifier('x'), '>', NumberLiteral(0));
      final thenStmt = ReturnStatement([StringLiteral('positive')]);
      final elseStmt = ReturnStatement([StringLiteral('non-positive')]);
      final original = IfStatement(cond, [], [thenStmt], [elseStmt]);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as IfStatement;

      expect(restored.cond is BinaryExpression, isTrue);
      expect(restored.thenBlock.length, equals(1));
      expect(restored.elseBlock.length, equals(1));
      expect(restored.elseIfs.length, equals(0));
    });

    test('ForLoop dump/restore', () {
      final varName = Identifier('i');
      final start = NumberLiteral(1);
      final end = NumberLiteral(10);
      final step = NumberLiteral(1);
      final body = [
        ExpressionStatement(
          FunctionCall(Identifier('print'), [Identifier('i')]),
        ),
      ];
      final original = ForLoop(varName, start, end, step, body);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as ForLoop;

      expect(restored.varName.name, equals('i'));
      expect((restored.start as NumberLiteral).value, equals(1));
      expect((restored.endExpr as NumberLiteral).value, equals(10));
      expect((restored.stepExpr as NumberLiteral).value, equals(1));
      expect(restored.body.length, equals(1));
    });

    test('LocalDeclaration dump/restore', () {
      final names = [Identifier('x'), Identifier('y')];
      final attributes = ['', 'const'];
      final exprs = [NumberLiteral(10), StringLiteral('hello')];
      final original = LocalDeclaration(names, attributes, exprs);

      final dumped = original.dump();
      final restored = undumpAst(dumped) as LocalDeclaration;

      expect(restored.names.length, equals(2));
      expect(restored.names[0].name, equals('x'));
      expect(restored.names[1].name, equals('y'));
      expect(restored.attributes, equals(['', 'const']));
      expect(restored.exprs.length, equals(2));
      expect((restored.exprs[0] as NumberLiteral).value, equals(10));
      expect((restored.exprs[1] as StringLiteral).value, equals('hello'));
    });

    test('Complex round-trip test with nested structures', () {
      // Create a complex AST structure that includes many different node types
      // function fibonacci(n)
      //   if n <= 1 then
      //     return n
      //   else
      //     return fibonacci(n-1) + fibonacci(n-2)
      //   end
      // end
      //
      // local result = fibonacci(10)
      // print("Result:", result)

      final param = Identifier('n');
      final one = NumberLiteral(1);
      final two = NumberLiteral(2);
      final ten = NumberLiteral(10);

      // if n <= 1 then return n
      final condition = BinaryExpression(param, '<=', one);
      final thenBlock = [
        ReturnStatement([param]),
      ];

      // fibonacci(n-1) + fibonacci(n-2)
      final fibCall1 = FunctionCall(Identifier('fibonacci'), [
        BinaryExpression(param, '-', one),
      ]);
      final fibCall2 = FunctionCall(Identifier('fibonacci'), [
        BinaryExpression(param, '-', two),
      ]);
      final fibSum = BinaryExpression(fibCall1, '+', fibCall2);
      final elseBlock = [
        ReturnStatement([fibSum]),
      ];

      // Complete if statement
      final ifStmt = IfStatement(condition, [], thenBlock, elseBlock);

      // Function definition
      final funcName = FunctionName(Identifier('fibonacci'), [], null);
      final funcBody = FunctionBody([param], [ifStmt], false);
      final funcDef = FunctionDef(funcName, funcBody);

      // Local declaration with function call
      final fibCall = FunctionCall(Identifier('fibonacci'), [ten]);
      final localDecl = LocalDeclaration([Identifier('result')], [''], [
        fibCall,
      ]);

      // Print statement
      final printCall = FunctionCall(Identifier('print'), [
        StringLiteral('Result:'),
        Identifier('result'),
      ]);
      final printStmt = ExpressionStatement(printCall);

      // Complete program
      final original = Program([funcDef, localDecl, printStmt]);

      // Dump and restore
      final dumped = original.dump();
      final restored = undumpAst(dumped) as Program;

      // Verify structure
      expect(restored.statements.length, equals(3));

      // Check function definition
      final restoredFunc = restored.statements[0] as FunctionDef;
      expect(restoredFunc.name.first.name, equals('fibonacci'));
      expect(restoredFunc.body.parameters?.length, equals(1));
      expect(restoredFunc.body.parameters?[0].name, equals('n'));
      expect(restoredFunc.body.body.length, equals(1));

      // Check if statement in function body
      final restoredIf = restoredFunc.body.body[0] as IfStatement;
      expect(restoredIf.cond is BinaryExpression, isTrue);
      expect(restoredIf.thenBlock.length, equals(1));
      expect(restoredIf.elseBlock.length, equals(1));

      // Check local declaration
      final restoredLocal = restored.statements[1] as LocalDeclaration;
      expect(restoredLocal.names[0].name, equals('result'));
      expect(restoredLocal.exprs.length, equals(1));
      expect(restoredLocal.exprs[0] is FunctionCall, isTrue);

      // Check print statement
      final restoredPrint = restored.statements[2] as ExpressionStatement;
      expect(restoredPrint.expr is FunctionCall, isTrue);
      final printFunc = restoredPrint.expr as FunctionCall;
      expect((printFunc.name as Identifier).name, equals('print'));
      expect(printFunc.args.length, equals(2));

      // Verify that the restored AST generates the same source code
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('Round-trip with table operations', () {
      // Create: local t = {x = 10, [5] = "five", 42}
      //         t.y = t.x + 1
      //         print(t[5])

      final tableEntry1 = KeyedTableEntry(Identifier('x'), NumberLiteral(10));
      final tableEntry2 = IndexedTableEntry(
        NumberLiteral(5),
        StringLiteral('five'),
      );
      final tableEntry3 = TableEntryLiteral(NumberLiteral(42));

      final tableConstructor = TableConstructor([
        tableEntry1,
        tableEntry2,
        tableEntry3,
      ]);

      final localDecl = LocalDeclaration([Identifier('t')], [''], [
        tableConstructor,
      ]);

      final fieldAssign = Assignment(
        [TableFieldAccess(Identifier('t'), Identifier('y'))],
        [
          BinaryExpression(
            TableFieldAccess(Identifier('t'), Identifier('x')),
            '+',
            NumberLiteral(1),
          ),
        ],
      );

      final printStmt = ExpressionStatement(
        FunctionCall(Identifier('print'), [
          TableIndexAccess(Identifier('t'), NumberLiteral(5)),
        ]),
      );

      final original = Program([localDecl, fieldAssign, printStmt]);

      // Dump and restore
      final dumped = original.dump();
      final restored = undumpAst(dumped) as Program;

      // Verify structure
      expect(restored.statements.length, equals(3));

      // Check local declaration with table
      final restoredLocal = restored.statements[0] as LocalDeclaration;
      final restoredTable = restoredLocal.exprs[0] as TableConstructor;
      expect(restoredTable.entries.length, equals(3));
      expect(restoredTable.entries[0] is KeyedTableEntry, isTrue);
      expect(restoredTable.entries[1] is IndexedTableEntry, isTrue);
      expect(restoredTable.entries[2] is TableEntryLiteral, isTrue);

      // Check field assignment
      final restoredAssign = restored.statements[1] as Assignment;
      expect(restoredAssign.targets[0] is TableFieldAccess, isTrue);
      expect(restoredAssign.exprs[0] is BinaryExpression, isTrue);

      // Check print with index access
      final restoredPrint = restored.statements[2] as ExpressionStatement;
      final printFunc = restoredPrint.expr as FunctionCall;
      expect(printFunc.args[0] is TableIndexAccess, isTrue);

      // Verify source code match
      expect(restored.toSource(), equals(original.toSource()));
    });

    test('Round-trip with control flow structures', () {
      // Create: for i = 1, 10 do
      //           if i % 2 == 0 then
      //             print("even:", i)
      //           else
      //             print("odd:", i)
      //           end
      //         end

      final printEven = ExpressionStatement(
        FunctionCall(Identifier('print'), [
          StringLiteral('even:'),
          Identifier('i'),
        ]),
      );

      final printOdd = ExpressionStatement(
        FunctionCall(Identifier('print'), [
          StringLiteral('odd:'),
          Identifier('i'),
        ]),
      );

      final condition = BinaryExpression(
        BinaryExpression(Identifier('i'), '%', NumberLiteral(2)),
        '==',
        NumberLiteral(0),
      );

      final ifStmt = IfStatement(condition, [], [printEven], [printOdd]);

      final forLoop = ForLoop(
        Identifier('i'),
        NumberLiteral(1),
        NumberLiteral(10),
        NumberLiteral(1),
        [ifStmt],
      );

      final original = Program([forLoop]);

      // Dump and restore
      final dumped = original.dump();
      final restored = undumpAst(dumped) as Program;

      // Verify structure
      expect(restored.statements.length, equals(1));

      final restoredFor = restored.statements[0] as ForLoop;
      expect(restoredFor.varName.name, equals('i'));
      expect((restoredFor.start as NumberLiteral).value, equals(1));
      expect((restoredFor.endExpr as NumberLiteral).value, equals(10));
      expect((restoredFor.stepExpr as NumberLiteral).value, equals(1));
      expect(restoredFor.body.length, equals(1));

      final restoredIf = restoredFor.body[0] as IfStatement;
      expect(restoredIf.cond is BinaryExpression, isTrue);
      expect(restoredIf.thenBlock.length, equals(1));
      expect(restoredIf.elseBlock.length, equals(1));

      // Verify source code match
      expect(restored.toSource(), equals(original.toSource()));
    });
  });
}
