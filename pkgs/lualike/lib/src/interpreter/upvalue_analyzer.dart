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

    // Analyze the function body
    for (final stmt in functionBody.body) {
      await stmt.accept(analyzer);
    }

    // Reset global access flag since we'll re-evaluate it properly now
    analyzer._accessesGlobals = false;

    final upvalues = <Upvalue>[];
    final upvalueNames = <String>{};

    // For each referenced variable, determine if it's an upvalue
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

      // Look for the variable in the environment chain starting from current
      // This ensures local variables shadow global variables (Lua semantics)
      Environment? env = currentEnv;
      bool foundAsUpvalue = false;
      while (env != null) {
        if (env.values.containsKey(varName)) {
          final box = env.values[varName]!;

          // Only add if it's a local variable (upvalue candidate)
          if (box.isLocal) {
            final upvalue = Upvalue(valueBox: box, name: varName);
            upvalues.add(upvalue);
            upvalueNames.add(varName);
            foundAsUpvalue = true;

            break;
          }
        }
        env = env.parent;
      }

      if (!foundAsUpvalue) {
        // This variable is truly a global access since it's not an upvalue
        analyzer._accessesGlobals = true;
      }
    }

    // Only add _ENV as upvalue if the function actually accesses globals
    // Don't add it just because there are other upvalues
    if (analyzer._accessesGlobals) {
      final envValue = currentEnv.get('_ENV');
      if (envValue != null) {
        // Create a synthetic box for _ENV
        final envBox = Box<dynamic>(envValue);
        final envUpvalue = Upvalue(valueBox: envBox, name: '_ENV');
        upvalues.add(envUpvalue);
      }
    }

    // Sort upvalues to match Lua's ordering behavior
    // In Lua, regular upvalues come first in declaration order, then _ENV comes last
    upvalues.sort((a, b) {
      final nameA = a.name ?? '';
      final nameB = b.name ?? '';

      // _ENV should always come last
      if (nameA == '_ENV' && nameB != '_ENV') return 1;
      if (nameB == '_ENV' && nameA != '_ENV') return -1;
      if (nameA == '_ENV' && nameB == '_ENV') return 0;

      // For regular upvalues, sort by name (which generally matches declaration order)
      return nameA.compareTo(nameB);
    });

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
  Future<void> visitAssignment(Assignment node) async {
    // Visit the expressions first to catch references
    for (final expr in node.exprs) {
      await expr.accept(this);
    }

    // Visit targets to catch any table accesses
    for (final target in node.targets) {
      await target.accept(this);
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
    await node.methodName.accept(this);
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
    await node.fieldName.accept(this);
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
    for (final part in node.rest) {
      await part.accept(this);
    }
    if (node.method != null) {
      await node.method!.accept(this);
    }
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
