import '../ast.dart';
import 'bytecode.dart';
import 'opcode.dart';

/// Compiles AST nodes to bytecode
class VariableScope {
  final Map<String, int> variables = {};
  final int baseRegister;

  VariableScope(this.baseRegister);
}

class Compiler implements AstVisitor<void> {
  final List<Instruction> instructions = [];
  final List<dynamic> constants = [];
  int nextRegister = 0;

  // Scope management
  final List<VariableScope> scopes = [];

  // Maps labels to instruction indices for control flow
  final Map<String, int> labels = {};
  final List<int> breaks = [];

  void _pushScope() {
    scopes.add(VariableScope(nextRegister));
  }

  void _popScope() {
    if (scopes.isNotEmpty) {
      nextRegister = scopes.last.baseRegister;
      scopes.removeLast();
    }
  }

  int getOrCreateRegister(String name) {
    // Look in current and outer scopes
    for (final scope in scopes.reversed) {
      if (scope.variables.containsKey(name)) {
        return scope.variables[name]!;
      }
    }

    // Create new variable in current scope
    if (scopes.isEmpty) _pushScope(); // Ensure we have at least one scope
    final reg = nextRegister++;
    scopes.last.variables[name] = reg;
    return reg;
  }

  Future<BytecodeChunk> compile(List<AstNode> nodes) async {
    instructions.clear();
    constants.clear();
    nextRegister = 0;
    scopes.clear();
    labels.clear();
    breaks.clear();

    _pushScope(); // Initialize global scope

    for (final node in nodes) {
      await node.accept(this);
    }

    return BytecodeChunk(
      instructions: List.from(instructions),
      constants: List.from(constants),
      numRegisters: nextRegister,
      isMainChunk: true,
    );
  }

  int addConstant(dynamic value) {
    final index = constants.length;
    constants.add(value);
    return index;
  }

  @override
  Future<void> visitBinaryExpression(BinaryExpression node) async {
    // Compile left and right operands
    await node.left.accept(this);
    await node.right.accept(this);

    // Add operation instruction
    switch (node.op) {
      case '+':
        instructions.add(const Instruction(OpCode.ADD));
        break;
      case '-':
        instructions.add(const Instruction(OpCode.SUB));
        break;
      case '*':
        instructions.add(const Instruction(OpCode.MUL));
        break;
      case '/':
        instructions.add(const Instruction(OpCode.DIV));
        break;
      case '%':
        instructions.add(const Instruction(OpCode.MOD));
        break;
      case '^':
        instructions.add(const Instruction(OpCode.POW));
        break;
      case '==':
        instructions.add(const Instruction(OpCode.EQ));
        break;
      case '<':
        instructions.add(const Instruction(OpCode.LT));
        break;
      case '<=':
        instructions.add(const Instruction(OpCode.LE));
        break;
      default:
        throw Exception('Unknown binary operator: ${node.op}');
    }
  }

  @override
  Future<void> visitIdentifier(Identifier node) async {
    // Load variable from register
    final reg = getOrCreateRegister(node.name);
    instructions.add(Instruction(OpCode.LOAD_LOCAL, [reg]));
  }

  @override
  Future<void> visitLocalDeclaration(LocalDeclaration node) async {
    // Evaluate all expressions first
    final exprs = node.exprs;
    for (final expr in exprs) {
      await expr.accept(this);
    }

    // Create new registers for all variables in current scope
    final registers = node.names
        .map((id) => getOrCreateRegister(id.name))
        .toList();

    // Store values in registers
    for (var i = 0; i < registers.length; i++) {
      if (i < exprs.length) {
        instructions.add(Instruction(OpCode.STORE_LOCAL, [registers[i]]));
      } else {
        // No value provided - store nil
        instructions.add(Instruction(OpCode.LOAD_NIL));
        instructions.add(Instruction(OpCode.STORE_LOCAL, [registers[i]]));
      }
    }
  }

  @override
  Future<void> visitGlobalDeclaration(GlobalDeclaration node) async {
    // Global declarations are not yet compiled to bytecode.
    // Treat them as simple assignments for now.
    for (final expr in node.exprs) {
      await expr.accept(this);
    }
    for (final name in node.names) {
      final reg = getOrCreateRegister(name.name);
      instructions.add(Instruction(OpCode.STORE_LOCAL, [reg]));
    }
  }

  @override
  Future<void> visitNumberLiteral(NumberLiteral node) async {
    final constIndex = addConstant(node.value);
    instructions.add(Instruction(OpCode.LOAD_CONST, [constIndex]));
  }

  @override
  Future<void> visitStringLiteral(StringLiteral node) async {
    final constIndex = addConstant(node.value);
    instructions.add(Instruction(OpCode.LOAD_CONST, [constIndex]));
  }

  @override
  Future<void> visitBooleanLiteral(BooleanLiteral node) async {
    instructions.add(Instruction(OpCode.LOAD_BOOL, [node.value]));
  }

  @override
  Future<void> visitNilValue(NilValue node) async {
    instructions.add(const Instruction(OpCode.LOAD_NIL));
  }

  @override
  Future<void> visitProgram(Program node) async {
    for (final stmt in node.statements) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitRepeatUntilLoop(RepeatUntilLoop node) async {
    final loopStart = instructions.length;

    // Compile body
    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    // Compile condition
    await node.cond.accept(this);
    instructions.add(Instruction(OpCode.NOT)); // Invert condition

    // Jump back to start if condition is false
    final offset = loopStart - instructions.length;
    instructions.add(Instruction(OpCode.JMPF, [offset]));
  }

  @override
  Future<void> visitMethodCall(MethodCall node) async {
    // Push object
    await node.prefix.accept(this);

    // Push method name
    if (node.methodName is Identifier) {
      final name = (node.methodName as Identifier).name;
      final constIndex = addConstant(name);
      instructions.add(Instruction(OpCode.LOAD_CONST, [constIndex]));
    } else {
      await node.methodName.accept(this);
    }

    // Setup self and method
    instructions.add(const Instruction(OpCode.SELF));

    // Push arguments
    for (final arg in node.args) {
      await arg.accept(this);
    }

    // Call with argument count including self
    instructions.add(Instruction(OpCode.CALL, [node.args.length + 1]));
  }

  @override
  Future<void> visitVarArg(VarArg node) async {
    instructions.add(
      const Instruction(OpCode.VARARGS, [-1]),
    ); // -1 means all varargs
  }

  @override
  Future<void> visitForInLoop(ForInLoop node) async {
    // Create loop variables
    for (final name in node.names) {
      getOrCreateRegister(name.name);
    }

    // Compile iterator expressions
    for (final iter in node.iterators) {
      await iter.accept(this);
    }

    // Setup for-in state at start of registers
    final iterReg = nextRegister;
    nextRegister += 3; // iterator + state + index
    instructions.add(Instruction(OpCode.SETUPFORLOOP, [iterReg]));

    // Jump position for loop start
    final loopStart = instructions.length;

    // Get next value(s)
    instructions.add(Instruction(OpCode.FORNEXT, [iterReg]));

    // Save break positions
    final oldBreaks = List<int>.from(breaks);
    breaks.clear();

    // Compile body
    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    // Jump back to start
    final offset = loopStart - instructions.length;
    instructions.add(Instruction(OpCode.JMP, [offset]));

    // Patch break jumps
    for (final breakPos in breaks) {
      final breakOffset = instructions.length - breakPos;
      instructions[breakPos] = Instruction(OpCode.JMP, [breakOffset]);
    }

    // Restore old break positions
    breaks
      ..clear()
      ..addAll(oldBreaks);
  }

  @override
  Future<void> visitGoto(Goto node) async {
    final label = node.label.name;
    if (!labels.containsKey(label)) {
      // Forward jump - add to fixup list
      final pos = instructions.length;
      instructions.add(Instruction(OpCode.JMP, [0])); // Placeholder
      labels[label] = pos;
    } else {
      // Backward jump
      final targetPos = labels[label]!;
      final offset = targetPos - instructions.length;
      instructions.add(Instruction(OpCode.JMP, [offset]));
    }
  }

  @override
  Future<void> visitLabel(Label node) async {
    final label = node.label.name;
    final pos = instructions.length;

    // If forward referenced, patch jumps
    if (labels.containsKey(label)) {
      final jumpPos = labels[label]!;
      final offset = pos - jumpPos;
      instructions[jumpPos] = Instruction(OpCode.JMP, [offset]);
    }

    labels[label] = pos;
  }

  @override
  Future<void> visitDoBlock(DoBlock node) async {
    _pushScope();

    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    _popScope();
  }

  @override
  Future<void> visitUnaryExpression(UnaryExpression node) async {
    await node.expr.accept(this);

    switch (node.op) {
      case '-':
        instructions.add(const Instruction(OpCode.UNM));
        break;
      case 'not':
        instructions.add(const Instruction(OpCode.NOT));
        break;
      case '#':
        instructions.add(const Instruction(OpCode.LEN));
        break;
      case '~':
        instructions.add(const Instruction(OpCode.BNOT));
        break;
      default:
        throw Exception('Unknown unary operator: ${node.op}');
    }
  }

  @override
  Future<void> visitExpressionStatement(ExpressionStatement node) async {
    await node.expr.accept(this);
    // Pop result if not used
    instructions.add(const Instruction(OpCode.POP));
  }

  @override
  Future<void> visitTableConstructor(TableConstructor node) async {
    // Create an empty table and leave it on the top of the stack.
    instructions.add(const Instruction(OpCode.NEWTABLE));

    // For each table entry, update the table that is already on the stack.
    // Note: We assume our SETTABLE opcode pops the key and value and then pushes the table
    // back onto the stack so that successive SETTABLE operations can update the same table.
    for (final entry in node.entries) {
      //FIXME: can be identifier/literal
      if (entry is KeyedTableEntry) {
        // If the key is an Identifier, load its name as a constant.
        dynamic keyName;
        if (entry.key is Identifier) {
          keyName = (entry.key as Identifier).name;
        } else {
          keyName = entry.key;
        }
        final constIndex = addConstant(keyName);
        instructions.add(Instruction(OpCode.LOAD_CONST, [constIndex]));

        // Compile the value of the table entry. In many cases this will emit a LOAD_CONST.
        await entry.value.accept(this);

        // Emit SETTABLE to set this key-value pair in the table.
        // SETTABLE is expected to pop the key and value (and the table), then push the
        // updated table back onto the stack.
        instructions.add(const Instruction(OpCode.SETTABLE));
      } else if (entry is TableEntryLiteral) {
        // For literal entries (with an implicit key ordering), if needed do similar:
        // For example, we could use an automatic index key here.
        // (This branch can be modified based on your language's semantics.)
        instructions.add(Instruction(OpCode.LOAD_CONST, [addConstant(1)]));
        await entry.expr.accept(this);
        instructions.add(const Instruction(OpCode.SETTABLE));
      }
    }
    // No need to issue a STORE_LOCAL here – the table is left on the stack.
  }

  @override
  Future<void> visitTableAccess(TableAccessExpr node) async {
    await node.table.accept(this);
    // Instead of "await node.index.accept(this);", do:
    final name = (node.index as Identifier).name;
    final constIndex = addConstant(name);
    instructions.add(Instruction(OpCode.LOAD_CONST, [constIndex]));
    instructions.add(const Instruction(OpCode.GETTABLE));
  }

  @override
  Future<void> visitIfStatement(IfStatement node) async {
    // Keep track of all conditional jumps that need patching
    final List<int> conditionalJumps = [];
    final List<int> endJumps = [];

    // Handle main if condition
    await node.cond.accept(this);
    conditionalJumps.add(instructions.length);
    instructions.add(Instruction(OpCode.JMPF, [0]));

    // Compile then block
    for (final stmt in node.thenBlock) {
      await stmt.accept(this);
    }

    // Jump over else/elseif blocks when then block completes
    if (node.elseIfs.isNotEmpty || node.elseBlock.isNotEmpty) {
      endJumps.add(instructions.length);
      instructions.add(Instruction(OpCode.JMP, [0]));
    }

    // Handle elseif clauses
    for (final elseif in node.elseIfs) {
      // Patch previous conditional jump to this position
      final lastJump = conditionalJumps.last;
      final offset = instructions.length - lastJump;
      instructions[lastJump] = Instruction(OpCode.JMPF, [offset]);

      // Compile elseif condition
      await elseif.cond.accept(this);
      conditionalJumps.add(instructions.length);
      instructions.add(Instruction(OpCode.JMPF, [0]));

      for (final stmt in elseif.thenBlock) {
        await stmt.accept(this);
      }
    }

    // Handle else block
    if (node.elseBlock.isNotEmpty) {
      // Patch the last conditional jump to this position
      final lastJump = conditionalJumps.last;
      final offset = instructions.length - lastJump;
      instructions[lastJump] = Instruction(OpCode.JMPF, [offset]);

      // Compile else block statements
      for (final stmt in node.elseBlock) {
        await stmt.accept(this);
      }
    }

    // Patch all end jumps to point to this position
    final endPos = instructions.length;
    for (final jumpPos in endJumps) {
      final offset = endPos - jumpPos;
      instructions[jumpPos] = Instruction(OpCode.JMP, [offset]);
    }

    // Patch any remaining conditional jumps to the end
    if (conditionalJumps.isNotEmpty && node.elseBlock.isEmpty) {
      final lastJump = conditionalJumps.last;
      final offset = endPos - lastJump;
      instructions[lastJump] = Instruction(OpCode.JMPF, [offset]);
    }
  }

  @override
  Future<void> visitWhileStatement(WhileStatement node) async {
    final loopStart = instructions.length;

    // Compile condition
    await node.cond.accept(this);

    // Add conditional jump
    final jmpPos = instructions.length;
    instructions.add(Instruction(OpCode.JMPF, [0]));

    // Save current break positions
    final oldBreaks = List<int>.from(breaks);
    breaks.clear();

    // Compile body
    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    // Add jump back to start
    final offset = loopStart - instructions.length;
    instructions.add(Instruction(OpCode.JMP, [offset]));

    // Patch conditional jump
    final endOffset = instructions.length - jmpPos;
    instructions[jmpPos] = Instruction(OpCode.JMPF, [endOffset]);

    // Patch break jumps
    for (final breakPos in breaks) {
      final breakOffset = instructions.length - breakPos;
      instructions[breakPos] = Instruction(OpCode.JMP, [breakOffset]);
    }

    // Restore old break positions
    breaks.clear();
    breaks.addAll(oldBreaks);
  }

  @override
  Future<void> visitFunctionDef(FunctionDef node) async {
    // Create new scope for function
    _pushScope();

    final savedInstructions = List<Instruction>.from(instructions);
    final savedConstants = List<dynamic>.from(constants);
    final savedNextRegister = nextRegister;
    instructions.clear();
    nextRegister = 0;

    // Compile parameters
    for (final param in node.body.parameters!) {
      final reg = getOrCreateRegister(param.name);
      instructions.add(Instruction(OpCode.STORE_LOCAL, [reg]));
    }

    // Compile function body
    for (final stmt in node.body.body) {
      await stmt.accept(this);
    }

    // Add implicit return nil if needed
    if (instructions.isEmpty || instructions.last.op != OpCode.RETURN) {
      instructions.add(const Instruction(OpCode.LOAD_NIL));
      instructions.add(const Instruction(OpCode.RETURN));
    }

    // Create function chunk
    final functionChunk = BytecodeChunk(
      instructions: List.from(instructions),
      constants: List.from(constants),
      numRegisters: nextRegister,
      name: node.name.toString(),
    );

    // Restore original compilation state
    instructions.clear();
    instructions.addAll(savedInstructions);
    constants.clear();
    constants.addAll(savedConstants);
    nextRegister = savedNextRegister;

    // Add function chunk to constants and create closure
    final funcIndex = addConstant(functionChunk);
    instructions.add(Instruction(OpCode.CLOSURE, [funcIndex]));

    // Store function
    final reg = getOrCreateRegister(node.name.first.name);
    instructions.add(Instruction(OpCode.STORE_LOCAL, [reg]));

    // Restore old scope
    _popScope();
  }

  @override
  Future<void> visitFunctionCall(FunctionCall node) async {
    // Push function
    await node.name.accept(this);

    // Push arguments
    for (final arg in node.args) {
      await arg.accept(this);
    }

    // Call with argument count
    instructions.add(Instruction(OpCode.CALL, [node.args.length]));
  }

  @override
  Future<void> visitReturnStatement(ReturnStatement node) async {
    if (node.expr.isEmpty) {
      instructions.add(const Instruction(OpCode.LOAD_NIL));
    } else {
      for (final expr in node.expr) {
        await expr.accept(this);
      }
    }
    instructions.add(const Instruction(OpCode.RETURN));
  }

  @override
  Future<void> visitBreak(Break node) async {
    final pos = instructions.length;
    breaks.add(pos);
    instructions.add(Instruction(OpCode.JMP, [0])); // Placeholder offset
  }

  @override
  Future<void> visitAssignment(Assignment node) async {
    // Evaluate right side first
    for (final expr in node.exprs) {
      await expr.accept(this);
    }

    // For multiple targets, we need to store the result in a temporary register
    // and then load it for each target
    final tempReg = nextRegister++;
    instructions.add(Instruction(OpCode.STORE_LOCAL, [tempReg]));

    // Handle multiple targets
    for (var i = 0; i < node.targets.length; i++) {
      final target = node.targets[i];

      // Load the value from temp register for each target except the first one
      if (i > 0) {
        instructions.add(Instruction(OpCode.LOAD_LOCAL, [tempReg]));
      } else {
        // For the first target, the value is already on the stack
        instructions.add(Instruction(OpCode.LOAD_LOCAL, [tempReg]));
      }

      if (target is Identifier) {
        // Simple variable assignment
        final reg = getOrCreateRegister(target.name);
        instructions.add(Instruction(OpCode.STORE_LOCAL, [reg]));
      } else if (target is TableAccessExpr) {
        // Table field assignment
        await target.table.accept(this);
        await target.index.accept(this);
        instructions.add(const Instruction(OpCode.SETTABLE));
      }
    }
  }

  @override
  Future<void> visitForLoop(ForLoop node) async {
    // Save loop start position
    final loopStart = instructions.length;

    // Initialize loop variable
    await node.start.accept(this);
    final reg = getOrCreateRegister(node.varName.name);
    instructions.add(Instruction(OpCode.STORE_LOCAL, [reg]));

    // Evaluate end condition
    await node.endExpr.accept(this);
    instructions.add(Instruction(OpCode.LOAD_LOCAL, [reg]));
    instructions.add(const Instruction(OpCode.LE));

    // Conditional jump to end
    final jumpPos = instructions.length;
    instructions.add(Instruction(OpCode.JMPF, [0])); // Will patch this

    // Loop body
    _pushScope();

    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    // Increment
    instructions.add(Instruction(OpCode.LOAD_LOCAL, [reg]));
    await node.stepExpr.accept(this);
    instructions.add(const Instruction(OpCode.ADD));
    instructions.add(Instruction(OpCode.STORE_LOCAL, [reg]));

    // Jump back to start
    instructions.add(
      Instruction(OpCode.JMP, [loopStart - instructions.length]),
    );

    // Patch the forward jump
    final offset = instructions.length - jumpPos;
    instructions[jumpPos] = Instruction(OpCode.JMPF, [offset]);

    _popScope();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw Exception(
      'Compiler: Unhandled AST node type: ${invocation.memberName}',
    );
  }
}
