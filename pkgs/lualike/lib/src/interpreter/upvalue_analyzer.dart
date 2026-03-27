import 'package:lualike/src/ast.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/upvalue.dart';

/// Analyzes AST nodes to determine which variables are upvalues.
///
/// An upvalue is a variable that is:
/// 1. Referenced inside a function
/// 2. Defined in an outer (enclosing) scope
/// 3. Not a parameter of the current function
class UpvalueAnalyzer extends AstVisitor<void> {
  /// Variables referenced in the current function
  final Set<String> _referencedVars = {};

  /// Parameters of the current function
  final Set<String> _parameters = {};

  /// Local variables declared in the current function
  final Set<String> _localVars = {};

  /// Whether the function accesses globals (needs _ENV)
  bool _accessesGlobals = false;

  static Box<dynamic>? _resolveCapturedEnvBox(Environment currentEnv) {
    final envBox = currentEnv.findBox('_ENV');
    if (envBox != null) {
      return envBox;
    }

    final runtime = currentEnv.interpreter;
    if (runtime != null) {
      try {
        final currentFunction = (runtime as dynamic).getCurrentFunction();
        if (currentFunction?.upvalues case final upvalues?) {
          for (final upvalue in upvalues) {
            if (upvalue.name == '_ENV') {
              return upvalue.valueBox;
            }
          }
        }
      } catch (_) {}
    }

    final envValue = currentEnv.get('_ENV');
    if (envValue == null) {
      return null;
    }

    return Box<dynamic>(
      envValue,
      isTransient: true,
      interpreter: currentEnv.interpreter,
    );
  }

  /// Analyzes a function body and returns the upvalues it needs
  static Future<List<Upvalue>> analyzeFunction(
    FunctionBody functionBody,
    Environment currentEnv,
  ) async {
    final analyzer = UpvalueAnalyzer();

    // Record function parameters
    if (functionBody.parameters != null) {
      for (final param in functionBody.parameters!) {
        analyzer._parameters.add(param.name);
      }
    }
    if (functionBody.varargName case final Identifier name) {
      analyzer._localVars.add(name.name);
    }

    // Analyze the function body
    for (final stmt in functionBody.body) {
      await stmt.accept(analyzer);
    }

    // Reset global access flag since we'll re-evaluate it properly now
    analyzer._accessesGlobals = false;

    final upvalues = <Upvalue>[];
    final unresolvedReferences = <String>{};
    for (final varName in analyzer._referencedVars) {
      // Skip if it's a parameter or local variable declared within the function
      if (analyzer._parameters.contains(varName) ||
          analyzer._localVars.contains(varName)) {
        continue;
      }

      // Skip special cases
      if (varName == '...' || varName == '_ENV' || varName == '_G') {
        continue;
      }

      unresolvedReferences.add(varName);
    }

    // Preserve first-reference order for upvalue slots, but still resolve each
    // name lexically through the enclosing local environments.
    for (final varName in analyzer._referencedVars) {
      if (!unresolvedReferences.contains(varName)) {
        continue;
      }

      Environment? env = currentEnv;
      while (env != null) {
        final box = env.values[varName];
        if (box != null && box.isLocal) {
          upvalues.add(
            Upvalue(
              valueBox: box,
              name: varName,
              interpreter: currentEnv.interpreter,
            ),
          );
          unresolvedReferences.remove(varName);
          break;
        }
        env = env.parent;
      }
    }

    if (unresolvedReferences.isNotEmpty) {
      // These names were referenced but not captured from any enclosing local.
      // They are therefore resolved as globals through _ENV.
      analyzer._accessesGlobals = true;
    }

    // Only add _ENV as upvalue if the function actually accesses globals
    // Don't add it just because there are other upvalues
    if (analyzer._accessesGlobals) {
      final envBox = _resolveCapturedEnvBox(currentEnv);
      if (envBox != null) {
        final envUpvalue = Upvalue(
          valueBox: envBox,
          name: '_ENV',
          interpreter: currentEnv.interpreter,
        );
        upvalues.add(envUpvalue);
      }
    }

    return upvalues;
  }

  @override
  Future<void> visitIdentifier(Identifier node) async {
    _referencedVars.add(node.name);

    // Don't mark variables as global access during traversal
    // We'll determine what's truly global vs upvalue during final analysis
  }

  @override
  Future<void> visitLocalDeclaration(LocalDeclaration node) async {
    // Record local variable declarations
    for (final name in node.names) {
      _localVars.add(name.name);
    }

    // Visit the expressions to catch any references
    for (final expr in node.exprs) {
      await expr.accept(this);
    }
  }

  @override
  Future<void> visitGlobalDeclaration(GlobalDeclaration node) async {
    for (final expr in node.exprs) {
      await expr.accept(this);
    }
  }

  @override
  Future<void> visitAssignment(Assignment node) async {
    // Preserve source order for upvalue slots: assignment targets appear
    // before the right-hand side in Lua source.
    for (final target in node.targets) {
      await target.accept(this);
    }

    for (final expr in node.exprs) {
      await expr.accept(this);
    }
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
  Future<void> visitTableAccess(TableAccessExpr node) async {
    await node.table.accept(this);
    await node.index.accept(this);
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
  Future<void> visitBinaryExpression(BinaryExpression node) async {
    await node.left.accept(this);
    await node.right.accept(this);
  }

  @override
  Future<void> visitUnaryExpression(UnaryExpression node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitGroupedExpression(GroupedExpression node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitReturnStatement(ReturnStatement node) async {
    for (final expr in node.expr) {
      await expr.accept(this);
    }
  }

  @override
  Future<void> visitIfStatement(IfStatement node) async {
    await node.cond.accept(this);

    for (final stmt in node.thenBlock) {
      await stmt.accept(this);
    }
    for (final elseIf in node.elseIfs) {
      await elseIf.accept(this);
    }

    for (final stmt in node.elseBlock) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitElseIfClause(ElseIfClause node) async {
    await node.cond.accept(this);
    for (final stmt in node.thenBlock) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitWhileStatement(WhileStatement node) async {
    await node.cond.accept(this);
    for (final stmt in node.body) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitForLoop(ForLoop node) async {
    await node.start.accept(this);
    await node.endExpr.accept(this);
    await node.stepExpr.accept(this);

    // The loop variable is local to the loop
    _localVars.add(node.varName.name);

    for (final stmt in node.body) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitForInLoop(ForInLoop node) async {
    for (final iterator in node.iterators) {
      await iterator.accept(this);
    }

    // Loop variables are local to the loop
    for (final name in node.names) {
      _localVars.add(name.name);
    }

    for (final stmt in node.body) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitRepeatUntilLoop(RepeatUntilLoop node) async {
    for (final stmt in node.body) {
      await stmt.accept(this);
    }
    await node.cond.accept(this);
  }

  @override
  Future<void> visitDoBlock(DoBlock node) async {
    for (final stmt in node.body) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitTableConstructor(TableConstructor node) async {
    for (final entry in node.entries) {
      await entry.accept(this);
    }
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
  Future<void> visitTableEntryLiteral(TableEntryLiteral node) async {
    await node.expr.accept(this);
  }

  @override
  Future<void> visitExpressionStatement(ExpressionStatement node) async {
    await node.expr.accept(this);
  }

  // Literals don't reference variables, so we can ignore them
  @override
  Future<void> visitStringLiteral(StringLiteral node) async {}

  @override
  Future<void> visitNumberLiteral(NumberLiteral node) async {}

  @override
  Future<void> visitBooleanLiteral(BooleanLiteral node) async {}

  @override
  Future<void> visitNilValue(NilValue node) async {}

  @override
  Future<void> visitVarArg(VarArg node) async {
    // VarArg references the special "..." parameter
    _referencedVars.add("...");
  }

  // Nested functions need their own analysis
  @override
  Future<void> visitFunctionDef(FunctionDef node) async {
    // Don't analyze nested functions here - they'll be analyzed separately
  }

  @override
  Future<void> visitLocalFunctionDef(LocalFunctionDef node) async {
    // Record the function name as a local variable
    _localVars.add(node.name.name);
    // Don't analyze the function body here - it'll be analyzed separately
  }

  @override
  Future<void> visitFunctionBody(FunctionBody node) async {
    // Don't analyze nested function bodies here - they'll be analyzed separately
  }

  @override
  Future<void> visitFunctionLiteral(FunctionLiteral node) async {
    // Don't analyze nested function literals here - they'll be analyzed separately
  }

  // Control flow statements that don't reference variables
  @override
  Future<void> visitBreak(Break node) async {}

  @override
  Future<void> visitGoto(Goto node) async {}

  @override
  Future<void> visitLabel(Label node) async {}

  @override
  Future<void> visitProgram(Program node) async {
    for (final stmt in node.statements) {
      await stmt.accept(this);
    }
  }

  @override
  Future<void> visitFunctionName(FunctionName node) async {
    await node.first.accept(this);
  }

  @override
  Future<void> visitAssignmentIndexAccessExpr(
    AssignmentIndexAccessExpr node,
  ) async {
    await node.target.accept(this);
    await node.index.accept(this);
    await node.value.accept(this);
  }

  @override
  Future<void> visitYieldStatement(YieldStatement node) async {
    for (final expr in node.expr) {
      await expr.accept(this);
    }
  }
}
