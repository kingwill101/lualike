import 'ast.dart';

/// Semantic analyzer for detecting compile-time errors like const variable assignments
class SemanticAnalyzer implements AstVisitor<void> {
  /// Tracks which variables are declared as const in each scope
  final List<Map<String, bool>> _scopes = [];
  final List<String> _errors = [];

  /// Current scope depth
  // int get _currentScopeDepth => _scopes.length - 1;

  /// Analyze a program and return any semantic errors found
  List<String> analyze(Program program) {
    print("DEBUG: SemanticAnalyzer.analyze() called");
    _errors.clear();
    _scopes.clear();
    _pushScope(); // Global scope

    try {
      program.accept(this);
    } catch (e) {
      // Catch any analysis errors
      print("DEBUG: Analysis error: $e");
      _errors.add('Analysis error: $e');
    }

    print("DEBUG: Analysis complete, found ${_errors.length} errors: $_errors");
    _popScope();
    return List.from(_errors);
  }

  void _pushScope() {
    _scopes.add(<String, bool>{});
  }

  void _popScope() {
    if (_scopes.isNotEmpty) {
      _scopes.removeLast();
    }
  }

  void _declareVariable(String name, {bool isConst = false}) {
    if (_scopes.isNotEmpty) {
      _scopes.last[name] = isConst;
    }
  }

  bool _isConstVariable(String name) {
    print(
      "DEBUG: _isConstVariable('$name') - checking ${_scopes.length} scopes",
    );
    // Search through scopes from innermost to outermost
    for (var i = _scopes.length - 1; i >= 0; i--) {
      print("DEBUG: Scope $i contains keys: ${_scopes[i].keys}");
      if (_scopes[i].containsKey(name)) {
        final result = _scopes[i][name] ?? false;
        print("DEBUG: Found '$name' in scope $i, isConst: $result");
        return result;
      }
    }
    print("DEBUG: Variable '$name' not found in any scope");
    return false;
  }

  @override
  Future<void> visitProgram(Program node) async {
    print(
      "DEBUG: visitProgram called with ${node.statements.length} statements",
    );
    for (int i = 0; i < node.statements.length; i++) {
      final stmt = node.statements[i];
      print("DEBUG: Processing statement $i: ${stmt.runtimeType}");
      await stmt.accept(this);
      print("DEBUG: Completed statement $i");
    }
    print("DEBUG: visitProgram completed");
  }

  @override
  Future<void> visitLocalDeclaration(LocalDeclaration node) async {
    print(
      "DEBUG: visitLocalDeclaration called with names: ${node.names.map((n) => n.name)}, attributes: ${node.attributes}",
    );

    // Declare variables with their attributes FIRST
    for (var i = 0; i < node.names.length; i++) {
      final name = node.names[i].name;
      final attribute = i < node.attributes.length ? node.attributes[i] : '';
      final isConst = attribute == 'const';

      print(
        "DEBUG: Declaring variable '$name' with attribute '$attribute' (isConst: $isConst)",
      );
      _declareVariable(name, isConst: isConst);
    }

    // Then process expressions
    for (final expr in node.exprs) {
      await expr.accept(this);
    }
  }

  @override
  Future<void> visitAssignment(Assignment node) async {
    print(
      "DEBUG: visitAssignment called with targets: ${node.targets.map((t) => t.runtimeType)}",
    );

    // Check expressions first
    for (final expr in node.exprs) {
      await expr.accept(this);
    }

    // Check each assignment target
    for (final target in node.targets) {
      if (target is Identifier) {
        final name = target.name;
        print(
          "DEBUG: Checking assignment to variable '$name', isConst: ${_isConstVariable(name)}",
        );
        if (_isConstVariable(name)) {
          print("DEBUG: Found const assignment error for '$name'");
          _errors.add(":1: attempt to assign to const variable '$name'");
        }
      } else {
        // Process other types of targets
        await target.accept(this);
      }
    }
  }

  @override
  Future<void> visitIdentifier(Identifier node) async {
    // No special handling needed for identifier access
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
  Future<void> visitForLoop(ForLoop node) async {
    _pushScope();

    // Declare loop variable
    _declareVariable(node.varName.name, isConst: false);

    await node.start.accept(this);
    await node.endExpr.accept(this);
    await node.stepExpr.accept(this);

    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    _popScope();
  }

  @override
  Future<void> visitForInLoop(ForInLoop node) async {
    _pushScope();

    // Declare loop variables
    for (final name in node.names) {
      _declareVariable(name.name, isConst: false);
    }

    for (final iter in node.iterators) {
      await iter.accept(this);
    }

    for (final stmt in node.body) {
      await stmt.accept(this);
    }

    _popScope();
  }

  @override
  Future<void> visitFunctionDef(FunctionDef node) async {
    _pushScope();

    // Declare function parameters
    for (final param in node.body.parameters ?? <Identifier>[]) {
      _declareVariable(param.name, isConst: false);
    }

    for (final stmt in node.body.body) {
      await stmt.accept(this);
    }

    _popScope();
  }

  @override
  Future<void> visitLocalFunctionDef(LocalFunctionDef node) async {
    // Declare function name in current scope
    _declareVariable(node.name.name, isConst: false);

    _pushScope();

    // Declare function parameters
    for (final param in node.funcBody.parameters ?? <Identifier>[]) {
      _declareVariable(param.name, isConst: false);
    }

    for (final stmt in node.funcBody.body) {
      await stmt.accept(this);
    }

    _popScope();
  }

  @override
  Future<void> visitFunctionLiteral(FunctionLiteral node) async {
    _pushScope();

    // Declare function parameters
    for (final param in node.funcBody.parameters ?? <Identifier>[]) {
      _declareVariable(param.name, isConst: false);
    }

    for (final stmt in node.funcBody.body) {
      await stmt.accept(this);
    }

    _popScope();
  }

  @override
  Future<void> visitWhileStatement(WhileStatement node) async {
    await node.cond.accept(this);

    _pushScope();
    for (final stmt in node.body) {
      await stmt.accept(this);
    }
    _popScope();
  }

  @override
  Future<void> visitRepeatUntilLoop(RepeatUntilLoop node) async {
    _pushScope();
    for (final stmt in node.body) {
      await stmt.accept(this);
    }
    await node.cond.accept(this);
    _popScope();
  }

  @override
  Future<void> visitIfStatement(IfStatement node) async {
    await node.cond.accept(this);

    _pushScope();
    for (final stmt in node.thenBlock) {
      await stmt.accept(this);
    }
    _popScope();

    for (final elseif in node.elseIfs) {
      await elseif.cond.accept(this);
      _pushScope();
      for (final stmt in elseif.thenBlock) {
        await stmt.accept(this);
      }
      _popScope();
    }

    if (node.elseBlock.isNotEmpty) {
      _pushScope();
      for (final stmt in node.elseBlock) {
        await stmt.accept(this);
      }
      _popScope();
    }
  }

  // Default implementations for expression nodes
  @override
  Future<void> visitBinaryExpression(BinaryExpression node) async {
    await node.left.accept(this);
    await node.right.accept(this);
  }

  @override
  Future<void> visitUnaryExpression(UnaryExpression node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitFunctionCall(FunctionCall node) async {
    await node.name.accept(this);
    for (final arg in node.args) {
      await arg.accept(this);
    }
  }

  @override
  Future<void> visitMethodCall(MethodCall node) async {
    await node.prefix.accept(this);
    for (final arg in node.args) {
      await arg.accept(this);
    }
  }

  @override
  Future<void> visitTableFieldAccess(TableFieldAccess node) async {
    await node.table.accept(this);
  }

  @override
  Future<void> visitTableIndexAccess(TableIndexAccess node) async {
    await node.table.accept(this);
    await node.index.accept(this);
  }

  @override
  Future<void> visitTableConstructor(TableConstructor node) async {
    for (final entry in node.entries) {
      await entry.accept(this);
    }
  }

  @override
  Future<void> visitTableEntryLiteral(TableEntryLiteral node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitKeyedTableEntry(KeyedTableEntry node) async {
    await node.key.accept(this);
    await node.value.accept(this);
  }

  @override
  Future<void> visitIndexedTableEntry(IndexedTableEntry node) async {
    await node.key.accept(this);
    await node.value.accept(this);
  }

  @override
  Future<void> visitGroupedExpression(GroupedExpression node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitExpressionStatement(ExpressionStatement node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitReturnStatement(ReturnStatement node) async {
    for (final expr in node.expr) {
      await expr.accept(this);
    }
  }

  // Missing visitor methods
  @override
  Future<void> visitElseIfClause(ElseIfClause node) async {
    await node.cond.accept(this);
    for (final stmt in node.thenBlock) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitFunctionBody(FunctionBody node) async {
    for (final stmt in node.body) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitFunctionName(FunctionName node) async {
    // Function names don't need special processing for const analysis
  }

  @override
  Future<void> visitTableAccess(TableAccessExpr node) async {
    await node.table.accept(this);
    await node.index.accept(this);
  }

  @override
  Future<void> visitYieldStatement(YieldStatement node) async {
    for (final expr in node.expr) {
      await expr.accept(this);
    }
  }

  // Literal nodes need no special processing
  @override
  Future<void> visitNumberLiteral(NumberLiteral node) async {}

  @override
  Future<void> visitStringLiteral(StringLiteral node) async {}

  @override
  Future<void> visitBooleanLiteral(BooleanLiteral node) async {}

  @override
  Future<void> visitNilValue(NilValue node) async {}

  @override
  Future<void> visitVarArg(VarArg node) async {}

  @override
  Future<void> visitBreak(Break node) async {}

  @override
  Future<void> visitGoto(Goto node) async {}

  @override
  Future<void> visitLabel(Label node) async {}

  @override
  Future<void> visitAssignmentIndexAccessExpr(
    AssignmentIndexAccessExpr node,
  ) async {
    await node.target.accept(this);
    await node.index.accept(this);
    await node.value.accept(this);
  }
}
