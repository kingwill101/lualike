@Tags(['bytecode'])
import 'package:test/test.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/bytecode.dart';

void main() {
  group('Compiler', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('compiles number literal', () async {
      final ast = NumberLiteral(42);
      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains(42));
      expect(chunk.instructions[0].op, equals(OpCode.LOAD_CONST));
    });

    test('compiles binary expression', () async {
      final ast = BinaryExpression(NumberLiteral(10), '+', NumberLiteral(20));

      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains(10));
      expect(chunk.constants, contains(20));
      expect(chunk.constants.length, equals(2)); // Expecting 2 constants
      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.ADD]),
      );
    });

    test('compiles local declaration', () async {
      final ast = LocalDeclaration([Identifier('x')], [], [NumberLiteral(42)]);

      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains(42));
      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.STORE_LOCAL]),
      );
    });

    test('compiles if statement', () async {
      final ast = IfStatement(
        BooleanLiteral(true),
        [],
        [
          Assignment([Identifier('x')], [NumberLiteral(1)]),
        ],
        [
          Assignment([Identifier('x')], [NumberLiteral(2)]),
        ],
      );

      final chunk = await compiler.compile([ast]);

      final ops = chunk.instructions.map((i) => i.op).toList();
      expect(ops, contains(OpCode.JMPF));
      expect(ops, contains(OpCode.JMP));
      expect(chunk.constants, contains(1));
      expect(chunk.constants, contains(2));
    });

    test('compiles while loop', () async {
      final ast = WhileStatement(BooleanLiteral(true), [
        Assignment(
          [Identifier('x')],
          [BinaryExpression(Identifier('x'), '+', NumberLiteral(1))],
        ),
      ]);

      final chunk = await compiler.compile([ast]);

      final ops = chunk.instructions.map((i) => i.op).toList();
      expect(ops, contains(OpCode.JMPF));
      expect(ops, contains(OpCode.JMP));
      expect(chunk.constants, contains(1));
    });

    test('compiles function definition', () async {
      final ast = FunctionDef(
        FunctionName(Identifier('add'), [], null),
        FunctionBody(
          [Identifier('a'), Identifier('b')],
          [
            ReturnStatement([
              BinaryExpression(Identifier('a'), '+', Identifier('b')),
            ]),
          ],
          false,
        ),
      );

      final chunk = await compiler.compile([ast]);

      expect(chunk.instructions.map((i) => i.op), contains(OpCode.CLOSURE));

      // Get the function prototype from constants
      final proto = chunk.constants.whereType<BytecodeChunk>().first;
      expect(proto.numRegisters, equals(2)); // For parameters
      expect(
        proto.instructions.map((i) => i.op),
        containsAllInOrder([
          OpCode.LOAD_LOCAL,
          OpCode.LOAD_LOCAL,
          OpCode.ADD,
          OpCode.RETURN,
        ]),
      );
    });

    test('compiles table operations', () async {
      final ast = [
        // local t = {}
        LocalDeclaration([Identifier('t')], [], [TableConstructor([])]),
        // t.x = 42
        Assignment(
          [TableAccessExpr(Identifier('t'), Identifier('x'))],
          [NumberLiteral(42)],
        ),
      ];

      final chunk = await compiler.compile(ast);

      expect(
        chunk.instructions.map((i) => i.op),
        containsAllInOrder([
          OpCode.NEWTABLE,
          OpCode.LOAD_LOCAL, // Load table in register
          OpCode.LOAD_CONST, // "x"
          OpCode.LOAD_CONST, // 42
          OpCode.SETTABLE,
          OpCode.STORE_LOCAL,
        ]),
      );
    });

    test('compiles method calls', () async {
      final ast = MethodCall(Identifier('obj'), Identifier('method'), [
        NumberLiteral(42),
      ]);

      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        containsAllInOrder([
          OpCode.LOAD_LOCAL, // Load obj
          OpCode.LOAD_CONST, // Load method name
          OpCode.SELF, // Setup method call
          OpCode.LOAD_CONST, // Load argument
          OpCode.CALL,
        ]),
      );
    });

    test('handles variable scoping', () async {
      final ast = [
        LocalDeclaration([Identifier('x')], [], [NumberLiteral(1)]),
        DoBlock([
          LocalDeclaration([Identifier('x')], [], [NumberLiteral(2)]),
          Assignment([Identifier('x')], [NumberLiteral(3)]),
        ]),
      ];

      final chunk = await compiler.compile(ast);

      // Verify that different registers are used for the two 'x' variables
      final stores = chunk.instructions
          .where((i) => i.op == OpCode.STORE_LOCAL)
          .map((i) => i.operands[0])
          .toList();

      expect(stores[0], equals(0));
      expect(stores[1], equals(1));
    });

    test('compiles string literal', () async {
      final ast = StringLiteral('hello');
      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains('hello'));
      expect(chunk.instructions[0].op, equals(OpCode.LOAD_CONST));
    });

    test('compiles boolean literal', () async {
      final ast = BooleanLiteral(true);
      final chunk = await compiler.compile([ast]);

      expect(chunk.instructions[0].op, equals(OpCode.LOAD_BOOL));
      expect(chunk.instructions[0].operands, equals([true]));
    });

    test('compiles nil value', () async {
      final ast = NilValue();
      final chunk = await compiler.compile([ast]);

      expect(chunk.instructions[0].op, equals(OpCode.LOAD_NIL));
    });

    test('compiles local declaration without initializer', () async {
      final ast = LocalDeclaration([Identifier('x')], [], []);
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_NIL, OpCode.STORE_LOCAL]),
      );
    });

    test('compiles unary minus expression', () async {
      final ast = UnaryExpression('-', NumberLiteral(10));
      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains(10));
      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.UNM]),
      );
    });

    test('compiles not expression', () async {
      final ast = UnaryExpression('not', BooleanLiteral(true));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_BOOL, OpCode.NOT]),
      );
    });

    test('compiles length expression', () async {
      final ast = UnaryExpression('#', StringLiteral('test'));
      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains('test'));
      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LEN]),
      );
    });

    test('compiles bitwise not expression', () async {
      final ast = UnaryExpression('~', NumberLiteral(255));
      final chunk = await compiler.compile([ast]);

      expect(chunk.constants, contains(255));
      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.BNOT]),
      );
    });

    test('compiles subtraction expression', () async {
      final ast = BinaryExpression(NumberLiteral(20), '-', NumberLiteral(10));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.SUB]),
      );
    });

    test('compiles multiplication expression', () async {
      final ast = BinaryExpression(NumberLiteral(10), '*', NumberLiteral(20));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.MUL]),
      );
    });

    test('compiles division expression', () async {
      final ast = BinaryExpression(NumberLiteral(20), '/', NumberLiteral(10));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.DIV]),
      );
    });

    test('compiles modulo expression', () async {
      final ast = BinaryExpression(NumberLiteral(20), '%', NumberLiteral(10));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.MOD]),
      );
    });

    test('compiles power expression', () async {
      final ast = BinaryExpression(NumberLiteral(10), '^', NumberLiteral(2));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.POW]),
      );
    });

    test('compiles equal expression', () async {
      final ast = BinaryExpression(NumberLiteral(10), '==', NumberLiteral(10));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.EQ]),
      );
    });

    test('compiles less than expression', () async {
      final ast = BinaryExpression(NumberLiteral(10), '<', NumberLiteral(20));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.LT]),
      );
    });

    test('compiles less than or equal expression', () async {
      final ast = BinaryExpression(NumberLiteral(10), '<=', NumberLiteral(10));
      final chunk = await compiler.compile([ast]);

      expect(
        chunk.instructions.map((i) => i.op),
        orderedEquals([OpCode.LOAD_CONST, OpCode.LOAD_CONST, OpCode.LE]),
      );
    });

    test('compiles if-elseif-else statement', () async {
      final ast = IfStatement(
        BooleanLiteral(true),
        [
          ElseIfClause(BooleanLiteral(false), [
            ExpressionStatement(NumberLiteral(2)),
          ]),
        ],
        [ExpressionStatement(NumberLiteral(1))],

        [ExpressionStatement(NumberLiteral(3))],
      );
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.JMPF, OpCode.JMP]));
      expect(chunk.constants, containsAll([1, 2, 3]));
    });

    test('compiles repeat-until loop', () async {
      final ast = RepeatUntilLoop([
        ExpressionStatement(NumberLiteral(1)),
      ], BooleanLiteral(true));
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.JMPF, OpCode.NOT]));
      expect(chunk.constants, contains(1));
    });

    test('compiles for loop', () async {
      final ast = ForLoop(
        Identifier('i'),
        NumberLiteral(1),
        NumberLiteral(10),
        NumberLiteral(1),
        [],
      );
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([OpCode.JMPF, OpCode.JMP, OpCode.LE, OpCode.ADD]),
      );
      expect(chunk.constants, containsAll([1, 10]));
    });

    test('compiles goto and label statements', () async {
      final ast = [Goto(Identifier('label1')), Label(Identifier('label1'))];
      final chunk = await compiler.compile(ast);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, contains(OpCode.JMP));
    });

    test('compiles break statement', () async {
      final ast = WhileStatement(BooleanLiteral(true), [Break()]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.JMPF, OpCode.JMP]));
    });

    test('compiles do block', () async {
      final ast = DoBlock([
        LocalDeclaration([Identifier('x')], [], [NumberLiteral(10)]),
      ]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, contains(OpCode.STORE_LOCAL));
      expect(chunk.constants, contains(10));
    });

    test('compiles function call without arguments', () async {
      final ast = FunctionCall(Identifier('func'), []);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.LOAD_LOCAL, OpCode.CALL]));
    });

    test('compiles function call with arguments', () async {
      final ast = FunctionCall(Identifier('func'), [NumberLiteral(1)]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([OpCode.LOAD_LOCAL, OpCode.LOAD_CONST, OpCode.CALL]),
      );
      expect(chunk.constants, contains(1));
    });

    test('compiles return statement without expression', () async {
      final ast = ReturnStatement([]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.LOAD_NIL, OpCode.RETURN]));
    });

    test('compiles return statement with expression', () async {
      final ast = ReturnStatement([NumberLiteral(1)]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.LOAD_CONST, OpCode.RETURN]));
      expect(chunk.constants, contains(1));
    });

    test('compiles nested functions and closures', () async {
      final ast = FunctionDef(
        FunctionName(Identifier('outer'), [], null),
        FunctionBody([], [
          FunctionDef(
            FunctionName(Identifier('inner'), [], null),
            FunctionBody([], [
              ReturnStatement([NumberLiteral(10)]),
            ], false),
          ),
          ReturnStatement([Identifier('inner')]),
        ], false),
      );
      final chunk = await compiler.compile([ast]);

      expect(chunk.instructions.map((i) => i.op), contains(OpCode.CLOSURE));

      final outerProto = chunk.constants.whereType<BytecodeChunk>().first;
      expect(
        outerProto.instructions.map((i) => i.op),
        contains(OpCode.CLOSURE),
      );

      final innerProto = outerProto.constants.whereType<BytecodeChunk>().first;
      expect(innerProto.instructions.map((i) => i.op), contains(OpCode.RETURN));
      expect(innerProto.constants, contains(10));
    });

    test('compiles table constructor with keyed entries', () async {
      final ast = TableConstructor([
        KeyedTableEntry(Identifier('key'), NumberLiteral(42)),
      ]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([
          OpCode.NEWTABLE,
          OpCode.LOAD_CONST,
          OpCode.LOAD_CONST,
          OpCode.SETTABLE,
        ]),
      );
      expect(chunk.constants, containsAll(['key', 42]));
    });

    test('compiles table constructor with literal entries', () async {
      final ast = TableConstructor([TableEntryLiteral(NumberLiteral(42))]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([
          OpCode.NEWTABLE,
          OpCode.LOAD_CONST,
          OpCode.LOAD_CONST,
          OpCode.SETTABLE,
        ]),
      );
      expect(chunk.constants, containsAll([1, 42]));
    });

    test('compiles table access', () async {
      final ast = TableAccessExpr(Identifier('table'), Identifier('key'));
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([OpCode.LOAD_LOCAL, OpCode.LOAD_CONST, OpCode.GETTABLE]),
      );
      expect(chunk.constants, contains('key'));
    });

    test('compiles table assignment', () async {
      final ast = Assignment(
        [TableAccessExpr(Identifier('table'), Identifier('key'))],
        [NumberLiteral(42)],
      );
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([
          OpCode.LOAD_CONST, // 42
          OpCode.LOAD_LOCAL, // table
          OpCode.LOAD_CONST, // key
          OpCode.SETTABLE,
        ]),
      );
      expect(chunk.constants, containsAll(['key', 42]));
    });

    test('compiles multiple assignments in local declaration', () async {
      final ast = LocalDeclaration(
        [Identifier('x'), Identifier('y')],
        [],
        [NumberLiteral(1), NumberLiteral(2)],
      );
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAllInOrder([
          OpCode.LOAD_CONST,
          OpCode.STORE_LOCAL,
          OpCode.LOAD_CONST,
          OpCode.STORE_LOCAL,
        ]),
      );
      expect(chunk.constants, containsAll([1, 2]));
    });

    test('compiles assignment to variable', () async {
      final ast = Assignment([Identifier('x')], [NumberLiteral(42)]);
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, containsAll([OpCode.LOAD_CONST, OpCode.STORE_LOCAL]));
      expect(chunk.constants, contains(42));
    });

    test('compiles expression statement and pop result', () async {
      final ast = ExpressionStatement(NumberLiteral(42));
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, contains(OpCode.POP));
    });

    test('compiles for-in loop', () async {
      final ast = ForInLoop(
        [Identifier('k'), Identifier('v')],
        [Identifier('table')],
        [ExpressionStatement(NumberLiteral(1))],
      );
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(
        ops,
        containsAll([OpCode.SETUPFORLOOP, OpCode.FORNEXT, OpCode.JMP]),
      );
    });

    test('compiles vararg expression', () async {
      final ast = VarArg();
      final chunk = await compiler.compile([ast]);
      final ops = chunk.instructions.map((i) => i.op).toList();

      expect(ops, contains(OpCode.VARARGS));
    });
  });
}
