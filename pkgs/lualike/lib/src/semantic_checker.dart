import 'ast.dart';
import 'const_checker.dart';

String? validateProgramSemantics(Program program) {
  final constChecker = ConstChecker();
  final constError = constChecker.checkConstViolations(program);
  if (constError != null) {
    return constError;
  }

  final globalError = GlobalChecker().check(program);
  if (globalError != null) {
    return globalError;
  }

  final upvalueError = UpvalueLimitChecker().check(program);
  if (upvalueError != null) {
    return upvalueError;
  }

  return LoadLimitChecker().check(program);
}

const int _maxRegisterLikeArity = 255;
const int _maxLocalVariables = 200;
const int _maxUpvalues = 255;
const int _maxExpressionNesting = 250;
const int _maxStatementNesting = 250;

final class UpvalueLimitChecker {
  String? check(Program program) =>
      _visitStatements(program.statements, _UpvalueFunctionContext.root());

  String? _visitStatements(
    List<AstNode> statements,
    _UpvalueFunctionContext context,
  ) {
    for (final statement in statements) {
      final error = _visitStatement(statement, context);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitStatement(
    AstNode statement,
    _UpvalueFunctionContext context,
  ) => switch (statement) {
    LocalDeclaration() => (() {
      final error = _visitExpressions(statement.exprs, context);
      if (error != null) {
        return error;
      }
      for (final name in statement.names) {
        final localError = context.declareLocal(name.name);
        if (localError != null) {
          return localError;
        }
      }
      return null;
    })(),
    GlobalDeclaration() => _visitExpressions(statement.exprs, context),
    Assignment() => (() {
      final targetError = _visitExpressions(statement.targets, context);
      if (targetError != null) {
        return targetError;
      }
      return _visitExpressions(statement.exprs, context);
    })(),
    ReturnStatement() => _visitExpressions(statement.expr, context),
    DoBlock() => _visitScopedStatements(statement.body, context),
    IfStatement() => _visitIfStatement(statement, context),
    WhileStatement() => (() {
      final conditionError = _visitExpression(statement.cond, context);
      if (conditionError != null) {
        return conditionError;
      }
      return _visitScopedStatements(statement.body, context);
    })(),
    RepeatUntilLoop() => (() {
      context.pushScope();
      final bodyError = _visitStatements(statement.body, context);
      if (bodyError != null) {
        context.popScope();
        return bodyError;
      }
      final conditionError = _visitExpression(statement.cond, context);
      context.popScope();
      return conditionError;
    })(),
    ForLoop() => (() {
      final startError = _visitExpression(statement.start, context);
      if (startError != null) {
        return startError;
      }
      final endError = _visitExpression(statement.endExpr, context);
      if (endError != null) {
        return endError;
      }
      final stepError = _visitExpression(statement.stepExpr, context);
      if (stepError != null) {
        return stepError;
      }
      context.pushScope();
      final localError = context.declareLocal(statement.varName.name);
      if (localError != null) {
        context.popScope();
        return localError;
      }
      final bodyError = _visitStatements(statement.body, context);
      context.popScope();
      return bodyError;
    })(),
    ForInLoop() => (() {
      final iteratorError = _visitExpressions(statement.iterators, context);
      if (iteratorError != null) {
        return iteratorError;
      }
      context.pushScope();
      for (final name in statement.names) {
        final localError = context.declareLocal(name.name);
        if (localError != null) {
          context.popScope();
          return localError;
        }
      }
      final bodyError = _visitStatements(statement.body, context);
      context.popScope();
      return bodyError;
    })(),
    FunctionDef() => (() {
      _visitFunctionNameTarget(statement, context);
      return _visitFunctionBody(
        statement.body,
        capturableOuterLocals: context.snapshotCapturableLocals(),
        implicitSelf: statement.implicitSelf || statement.body.implicitSelf,
        errorLine: _lineOf(statement.name.first),
      );
    })(),
    LocalFunctionDef() => (() {
      final localError = context.declareLocal(statement.name.name);
      if (localError != null) {
        return localError;
      }
      return _visitFunctionBody(
        statement.funcBody,
        capturableOuterLocals: context.snapshotCapturableLocals(),
        errorLine: _lineOf(statement.name),
      );
    })(),
    YieldStatement() => _visitExpressions(statement.expr, context),
    ExpressionStatement() => _visitExpression(statement.expr, context),
    AssignmentIndexAccessExpr() => (() {
      final targetError = _visitExpression(statement.target, context);
      if (targetError != null) {
        return targetError;
      }
      final indexError = _visitExpression(statement.index, context);
      if (indexError != null) {
        return indexError;
      }
      return _visitExpression(statement.value, context);
    })(),
    Break() || Goto() || Label() => null,
    final other => _visitExpression(other, context),
  };

  String? _visitIfStatement(
    IfStatement statement,
    _UpvalueFunctionContext context,
  ) {
    final conditionError = _visitExpression(statement.cond, context);
    if (conditionError != null) {
      return conditionError;
    }

    final thenError = _visitScopedStatements(statement.thenBlock, context);
    if (thenError != null) {
      return thenError;
    }

    for (final clause in statement.elseIfs) {
      final elseIfConditionError = _visitExpression(clause.cond, context);
      if (elseIfConditionError != null) {
        return elseIfConditionError;
      }

      final clauseError = _visitScopedStatements(clause.thenBlock, context);
      if (clauseError != null) {
        return clauseError;
      }
    }

    return _visitScopedStatements(statement.elseBlock, context);
  }

  String? _visitScopedStatements(
    List<AstNode> statements,
    _UpvalueFunctionContext context,
  ) {
    context.pushScope();
    final error = _visitStatements(statements, context);
    context.popScope();
    return error;
  }

  String? _visitExpressions(
    List<AstNode> expressions,
    _UpvalueFunctionContext context,
  ) {
    for (final expression in expressions) {
      final error = _visitExpression(expression, context);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitExpression(
    AstNode expression,
    _UpvalueFunctionContext context,
  ) => switch (expression) {
    Identifier() => (() {
      context.recordIdentifierUse(expression.name);
      return null;
    })(),
    NumberLiteral() ||
    StringLiteral() ||
    BooleanLiteral() ||
    NilValue() ||
    VarArg() => null,
    GroupedExpression() => _visitExpression(expression.expr, context),
    UnaryExpression() => _visitExpression(expression.expr, context),
    BinaryExpression() => (() {
      final leftError = _visitExpression(expression.left, context);
      if (leftError != null) {
        return leftError;
      }
      return _visitExpression(expression.right, context);
    })(),
    FunctionCall() => (() {
      final targetError = _visitExpression(expression.name, context);
      if (targetError != null) {
        return targetError;
      }
      return _visitExpressions(expression.args, context);
    })(),
    MethodCall() => (() {
      final prefixError = _visitExpression(expression.prefix, context);
      if (prefixError != null) {
        return prefixError;
      }
      return _visitExpressions(expression.args, context);
    })(),
    TableFieldAccess() => _visitExpression(expression.table, context),
    TableIndexAccess() => (() {
      final tableError = _visitExpression(expression.table, context);
      if (tableError != null) {
        return tableError;
      }
      return _visitExpression(expression.index, context);
    })(),
    TableAccessExpr() => (() {
      final tableError = _visitExpression(expression.table, context);
      if (tableError != null) {
        return tableError;
      }
      return _visitExpression(expression.index, context);
    })(),
    TableConstructor() => _visitTableConstructor(expression, context),
    FunctionLiteral() => _visitFunctionBody(
      expression.funcBody,
      capturableOuterLocals: context.snapshotCapturableLocals(),
      implicitSelf: expression.funcBody.implicitSelf,
      errorLine: _lineOf(expression),
    ),
    YieldStatement() => _visitExpressions(expression.expr, context),
    final other => _visitStatement(other, context),
  };

  String? _visitTableConstructor(
    TableConstructor constructor,
    _UpvalueFunctionContext context,
  ) {
    for (final entry in constructor.entries) {
      final error = switch (entry) {
        KeyedTableEntry() => _visitExpression(entry.value, context),
        IndexedTableEntry() => (() {
          final keyError = _visitExpression(entry.key, context);
          if (keyError != null) {
            return keyError;
          }
          return _visitExpression(entry.value, context);
        })(),
        TableEntryLiteral() => _visitExpression(entry.expr, context),
        final other => _visitExpression(other, context),
      };
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  void _visitFunctionNameTarget(
    FunctionDef definition,
    _UpvalueFunctionContext context,
  ) {
    if (definition.explicitGlobal &&
        definition.name.rest.isEmpty &&
        definition.name.method == null) {
      context.recordGlobalAccess();
      return;
    }

    context.recordIdentifierUse(definition.name.first.name);
  }

  String? _visitFunctionBody(
    FunctionBody body, {
    required Set<String> capturableOuterLocals,
    bool implicitSelf = false,
    int? errorLine,
  }) {
    final context = _UpvalueFunctionContext(
      capturableOuterLocals: capturableOuterLocals,
      functionLine: errorLine ?? _lineOf(body),
    );

    if (implicitSelf) {
      final selfError = context.declareLocal('self');
      if (selfError != null) {
        return selfError;
      }
    }
    for (final parameter in body.parameters ?? const <Identifier>[]) {
      final parameterError = context.declareLocal(parameter.name);
      if (parameterError != null) {
        return parameterError;
      }
    }
    if (body.varargName case final Identifier name) {
      final varargError = context.declareLocal(name.name);
      if (varargError != null) {
        return varargError;
      }
    }

    final bodyError = _visitStatements(body.body, context);
    if (bodyError != null) {
      return bodyError;
    }

    if (context.upvalueCount > _maxUpvalues) {
      return "line ${errorLine ?? _lineOf(body)}: too many upvalues";
    }

    return null;
  }

  int _lineOf(AstNode node) => (node.span?.start.line ?? 0) + 1;
}

final class _UpvalueFunctionContext {
  _UpvalueFunctionContext({
    required this.capturableOuterLocals,
    required this.functionLine,
  });

  factory _UpvalueFunctionContext.root() => _UpvalueFunctionContext(
    capturableOuterLocals: const <String>{},
    functionLine: 1,
  );

  final Set<String> capturableOuterLocals;
  final int functionLine;
  final List<Set<String>> _scopes = <Set<String>>[<String>{}];
  final Map<String, int> _visibleLocalCounts = <String, int>{};
  final Set<String> _capturedNames = <String>{};
  bool _accessesGlobals = false;
  int _activeLocals = 0;

  void pushScope() {
    _scopes.add(<String>{});
  }

  void popScope() {
    final removed = _scopes.removeLast();
    _activeLocals -= removed.length;
    for (final name in removed) {
      final count = _visibleLocalCounts[name];
      if (count == null || count <= 1) {
        _visibleLocalCounts.remove(name);
      } else {
        _visibleLocalCounts[name] = count - 1;
      }
    }
  }

  String? declareLocal(String name) {
    if (_scopes.last.add(name)) {
      _visibleLocalCounts[name] = (_visibleLocalCounts[name] ?? 0) + 1;
      _activeLocals++;
      if (_activeLocals > _maxLocalVariables) {
        return "line $functionLine: too many local variables";
      }
    }
    return null;
  }

  void recordIdentifierUse(String name) {
    if (name == '...' || name == '_ENV' || name == '_G') {
      return;
    }

    if (_visibleLocalCounts.containsKey(name)) {
      return;
    }

    if (capturableOuterLocals.contains(name)) {
      _capturedNames.add(name);
      return;
    }

    _accessesGlobals = true;
  }

  void recordGlobalAccess() {
    _accessesGlobals = true;
  }

  Set<String> snapshotCapturableLocals() => <String>{
    ...capturableOuterLocals,
    ..._visibleLocalCounts.keys,
  };

  int get upvalueCount => _capturedNames.length + (_accessesGlobals ? 1 : 0);
}

final class LoadLimitChecker {
  String? check(Program program) => _visitStatements(
    program.statements,
    expressionDepth: 0,
    statementDepth: 0,
  );

  String? _visitStatements(
    List<AstNode> statements, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    for (final statement in statements) {
      final error = _visitStatement(
        statement,
        expressionDepth: expressionDepth,
        statementDepth: statementDepth,
      );
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitStatement(
    AstNode statement, {
    required int expressionDepth,
    required int statementDepth,
  }) => switch (statement) {
    LocalDeclaration() => _visitLocalDeclaration(
      statement,
      expressionDepth: expressionDepth,
    ),
    GlobalDeclaration() => _visitGlobalDeclaration(
      statement,
      expressionDepth: expressionDepth,
    ),
    Assignment() => _visitAssignment(statement, expressionDepth: expressionDepth),
    ReturnStatement() => _visitExpressions(
      statement.expr,
      expressionDepth: expressionDepth,
    ),
    DoBlock() => _visitNestedStatements(
      statement,
      statement.body,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    ),
    IfStatement() => _visitIfStatement(
      statement,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    ),
    WhileStatement() => _visitWhileStatement(
      statement,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    ),
    RepeatUntilLoop() => _visitRepeatUntil(
      statement,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    ),
    ForLoop() => _visitForLoop(
      statement,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    ),
    ForInLoop() => _visitForInLoop(
      statement,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    ),
    FunctionDef() => _visitFunctionBody(
      statement.body,
      implicitSelf: statement.implicitSelf,
      statementDepth: statementDepth,
    ),
    LocalFunctionDef() => _visitFunctionBody(
      statement.funcBody,
      statementDepth: statementDepth,
    ),
    YieldStatement() => _visitExpressions(
      statement.expr,
      expressionDepth: expressionDepth,
    ),
    ExpressionStatement() => _visitExpression(
      statement.expr,
      expressionDepth: expressionDepth,
    ),
    AssignmentIndexAccessExpr() => _visitAssignmentIndex(
      statement,
      expressionDepth: expressionDepth,
    ),
    Break() || Goto() || Label() => null,
    final node => _visitExpression(node, expressionDepth: expressionDepth),
  };

  String? _visitLocalDeclaration(
    LocalDeclaration statement, {
    required int expressionDepth,
  }) {
    if (statement.names.length > _maxLocalVariables) {
      return "line ${_lineOf(statement)}: too many local variables";
    }
    return _visitExpressions(statement.exprs, expressionDepth: expressionDepth);
  }

  String? _visitGlobalDeclaration(
    GlobalDeclaration statement, {
    required int expressionDepth,
  }) {
    if (statement.names.length > _maxRegisterLikeArity ||
        statement.exprs.length > _maxRegisterLikeArity) {
      return "line ${_lineOf(statement)}: too many assignment values";
    }
    return _visitExpressions(statement.exprs, expressionDepth: expressionDepth);
  }

  String? _visitAssignment(
    Assignment statement, {
    required int expressionDepth,
  }) {
    if (statement.targets.length > _maxRegisterLikeArity ||
        statement.exprs.length > _maxRegisterLikeArity) {
      return "line ${_lineOf(statement)}: too many assignment values";
    }

    final targetError = _visitExpressions(
      statement.targets,
      expressionDepth: expressionDepth,
    );
    if (targetError != null) {
      return targetError;
    }
    return _visitExpressions(statement.exprs, expressionDepth: expressionDepth);
  }

  String? _visitIfStatement(
    IfStatement statement, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    final conditionError = _visitExpression(
      statement.cond,
      expressionDepth: expressionDepth,
    );
    if (conditionError != null) {
      return conditionError;
    }

    final thenError = _visitNestedStatements(
      statement,
      statement.thenBlock,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    );
    if (thenError != null) {
      return thenError;
    }

    for (final clause in statement.elseIfs) {
      final elseIfError = _visitExpression(
        clause.cond,
        expressionDepth: expressionDepth,
      );
      if (elseIfError != null) {
        return elseIfError;
      }
      final blockError = _visitNestedStatements(
        clause,
        clause.thenBlock,
        expressionDepth: expressionDepth,
        statementDepth: statementDepth,
      );
      if (blockError != null) {
        return blockError;
      }
    }

    return _visitNestedStatements(
      statement,
      statement.elseBlock,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    );
  }

  String? _visitWhileStatement(
    WhileStatement statement, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    final conditionError = _visitExpression(
      statement.cond,
      expressionDepth: expressionDepth,
    );
    if (conditionError != null) {
      return conditionError;
    }
    return _visitNestedStatements(
      statement,
      statement.body,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    );
  }

  String? _visitRepeatUntil(
    RepeatUntilLoop statement, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    final bodyError = _visitNestedStatements(
      statement,
      statement.body,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    );
    if (bodyError != null) {
      return bodyError;
    }
    return _visitExpression(statement.cond, expressionDepth: expressionDepth);
  }

  String? _visitForLoop(
    ForLoop statement, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    final startError = _visitExpression(
      statement.start,
      expressionDepth: expressionDepth,
    );
    if (startError != null) {
      return startError;
    }
    final endError = _visitExpression(
      statement.endExpr,
      expressionDepth: expressionDepth,
    );
    if (endError != null) {
      return endError;
    }
    final stepError = _visitExpression(
      statement.stepExpr,
      expressionDepth: expressionDepth,
    );
    if (stepError != null) {
      return stepError;
    }
    return _visitNestedStatements(
      statement,
      statement.body,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    );
  }

  String? _visitForInLoop(
    ForInLoop statement, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    final iteratorError = _visitExpressions(
      statement.iterators,
      expressionDepth: expressionDepth,
    );
    if (iteratorError != null) {
      return iteratorError;
    }
    return _visitNestedStatements(
      statement,
      statement.body,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth,
    );
  }

  String? _visitFunctionBody(
    FunctionBody body, {
    bool implicitSelf = false,
    required int statementDepth,
  }) {
    final parameterCount =
        (body.parameters?.length ?? 0) +
        (implicitSelf ? 1 : 0) +
        (body.varargName != null ? 1 : 0);
    if (parameterCount > _maxLocalVariables) {
      return "line ${_lineOf(body)}: too many local variables";
    }
    return _visitNestedStatements(
      body,
      body.body,
      expressionDepth: 0,
      statementDepth: statementDepth,
    );
  }

  String? _visitAssignmentIndex(
    AssignmentIndexAccessExpr statement, {
    required int expressionDepth,
  }) {
    final targetError = _visitExpression(
      statement.target,
      expressionDepth: expressionDepth,
    );
    if (targetError != null) {
      return targetError;
    }
    final indexError = _visitExpression(
      statement.index,
      expressionDepth: expressionDepth,
    );
    if (indexError != null) {
      return indexError;
    }
    return _visitExpression(statement.value, expressionDepth: expressionDepth);
  }

  String? _visitExpressions(
    List<AstNode> expressions, {
    required int expressionDepth,
  }) {
    for (final expression in expressions) {
      final error = _visitExpression(
        expression,
        expressionDepth: expressionDepth,
      );
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitExpression(
    AstNode expression, {
    required int expressionDepth,
  }) {
    if (expressionDepth > _maxExpressionNesting) {
      return "line ${_lineOf(expression)}: expression nesting overflow";
    }

    return switch (expression) {
      Identifier() || NumberLiteral() || StringLiteral() || BooleanLiteral() || NilValue() || VarArg() => null,
      GroupedExpression() => _visitExpression(
        expression.expr,
        expressionDepth: expressionDepth + 1,
      ),
      UnaryExpression() => _visitExpression(
        expression.expr,
        expressionDepth: expressionDepth,
      ),
      BinaryExpression() => (() {
        final leftError = _visitExpression(
          expression.left,
          expressionDepth: expressionDepth + 1,
        );
        if (leftError != null) {
          return leftError;
        }
        return _visitExpression(
          expression.right,
          expressionDepth: expressionDepth + 1,
        );
      })(),
      FunctionCall() => (() {
        if (expression.args.length > _maxRegisterLikeArity) {
          return "line ${_lineOf(expression)}: too many registers";
        }
        final targetError = _visitExpression(
          expression.name,
          expressionDepth: expressionDepth,
        );
        if (targetError != null) {
          return targetError;
        }
        return _visitExpressions(
          expression.args,
          expressionDepth: expressionDepth + 1,
        );
      })(),
      MethodCall() => (() {
        if (expression.args.length > _maxRegisterLikeArity) {
          return "line ${_lineOf(expression)}: too many registers";
        }
        final prefixError = _visitExpression(
          expression.prefix,
          expressionDepth: expressionDepth,
        );
        if (prefixError != null) {
          return prefixError;
        }
        return _visitExpressions(
          expression.args,
          expressionDepth: expressionDepth + 1,
        );
      })(),
      TableFieldAccess() => _visitExpression(
        expression.table,
        expressionDepth: expressionDepth,
      ),
      TableIndexAccess() => (() {
        final tableError = _visitExpression(
          expression.table,
          expressionDepth: expressionDepth,
        );
        if (tableError != null) {
          return tableError;
        }
        return _visitExpression(
          expression.index,
          expressionDepth: expressionDepth,
        );
      })(),
      TableAccessExpr() => (() {
        final tableError = _visitExpression(
          expression.table,
          expressionDepth: expressionDepth,
        );
        if (tableError != null) {
          return tableError;
        }
        return _visitExpression(
          expression.index,
          expressionDepth: expressionDepth,
        );
      })(),
      TableConstructor() => _visitTableConstructor(
        expression,
        expressionDepth: expressionDepth + 1,
      ),
      FunctionLiteral() => _visitFunctionBody(
        expression.funcBody,
        statementDepth: 0,
      ),
      YieldStatement() => _visitExpressions(
        expression.expr,
        expressionDepth: expressionDepth,
      ),
      final node => _visitStatement(
        node,
        expressionDepth: expressionDepth,
        statementDepth: 0,
      ),
    };
  }

  String? _visitTableConstructor(
    TableConstructor node, {
    required int expressionDepth,
  }) {
    for (final entry in node.entries) {
      final error = switch (entry) {
        KeyedTableEntry() => _visitExpression(
          entry.value,
          expressionDepth: expressionDepth,
        ),
        IndexedTableEntry() => (() {
          final keyError = _visitExpression(
            entry.key,
            expressionDepth: expressionDepth,
          );
          if (keyError != null) {
            return keyError;
          }
          return _visitExpression(
            entry.value,
            expressionDepth: expressionDepth,
          );
        })(),
        TableEntryLiteral() => _visitExpression(
          entry.expr,
          expressionDepth: expressionDepth,
        ),
        final other => _visitExpression(other, expressionDepth: expressionDepth),
      };
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  int _lineOf(AstNode node) => (node.span?.start.line ?? 0) + 1;

  String? _visitNestedStatements(
    AstNode node,
    List<AstNode> statements, {
    required int expressionDepth,
    required int statementDepth,
  }) {
    if (statementDepth >= _maxStatementNesting) {
      return "line ${_lineOf(node)}: statement nesting overflow";
    }
    return _visitStatements(
      statements,
      expressionDepth: expressionDepth,
      statementDepth: statementDepth + 1,
    );
  }
}

final class GlobalChecker {
  final List<_FunctionScopeState> _functions = <_FunctionScopeState>[];

  String? check(Program program) {
    _functions
      ..clear()
      ..add(_FunctionScopeState.root());
    return _visitStatements(program.statements);
  }

  String? _visitStatements(List<AstNode> statements) {
    for (final statement in statements) {
      final error = _visitStatement(statement);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitStatement(AstNode statement) => switch (statement) {
    LocalDeclaration() => _visitLocalDeclaration(statement),
    GlobalDeclaration() => _visitGlobalDeclaration(statement),
    Assignment() => _visitAssignment(statement),
    DoBlock() => _visitScopedBlock(statement.body),
    IfStatement() => _visitIfStatement(statement),
    WhileStatement() => _visitWhileStatement(statement),
    ForLoop() => _visitForLoop(statement),
    ForInLoop() => _visitForInLoop(statement),
    RepeatUntilLoop() => _visitRepeatUntil(statement),
    FunctionDef() => _visitFunctionDef(statement),
    LocalFunctionDef() => _visitLocalFunctionDef(statement),
    ReturnStatement() => _visitReturnStatement(statement),
    YieldStatement() => _visitExpressions(statement.expr),
    ExpressionStatement() => _visitExpression(statement.expr),
    AssignmentIndexAccessExpr() => _visitAssignmentIndex(statement),
    Break() || Goto() || Label() => null,
    final node => _visitExpression(node),
  };

  String? _visitScopedBlock(List<AstNode> body) {
    _enterScope();
    final error = _visitStatements(body);
    _exitScope();
    return error;
  }

  String? _visitLocalDeclaration(LocalDeclaration statement) {
    final error = _visitExpressions(statement.exprs);
    if (error != null) {
      return error;
    }

    final closeIndexes = <int>[];
    for (var index = 0; index < statement.names.length; index++) {
      final attribute = index < statement.attributes.length
          ? statement.attributes[index]
          : '';
      if (attribute == 'close') {
        closeIndexes.add(index);
      }
    }

    if (closeIndexes.length > 1) {
      return ":${_lineOf(statement)}: multiple to-be-closed variables in local declaration";
    }

    for (var index = 0; index < statement.names.length; index++) {
      final attribute = index < statement.attributes.length
          ? statement.attributes[index]
          : '';
      _currentScope.locals[statement.names[index].name] = attribute;
    }
    return null;
  }

  String? _visitGlobalDeclaration(GlobalDeclaration statement) {
    if (statement.defaultAttribute == 'close') {
      return ":${_lineOf(statement)}: global variables cannot be to-be-closed";
    }

    final error = _visitExpressions(statement.exprs);
    if (error != null) {
      return error;
    }

    if (statement.isWildcard) {
      _currentScope.collectiveAttribute = statement.defaultAttribute;
      return null;
    }

    if (statement.names.any((name) => name.name == '_ENV')) {
      _currentScope.invalidatesImplicitGlobals = true;
      return null;
    }

    for (var index = 0; index < statement.names.length; index++) {
      final attribute =
          index < statement.attributes.length &&
              statement.attributes[index].isNotEmpty
          ? statement.attributes[index]
          : statement.defaultAttribute;
      if (attribute == 'close') {
        return ":${_lineOf(statement)}: global variables cannot be to-be-closed";
      }
      _currentScope.namedGlobals[statement.names[index].name] = attribute;
    }
    return null;
  }

  String? _visitReturnStatement(ReturnStatement statement) {
    if (statement.expr.length > 254) {
      return ":${_lineOf(statement)}: too many returns";
    }
    return _visitExpressions(statement.expr);
  }

  String? _visitAssignment(Assignment statement) {
    final error = _visitExpressions(statement.exprs);
    if (error != null) {
      return error;
    }

    for (final target in statement.targets) {
      final targetError = _visitStoreTarget(target);
      if (targetError != null) {
        return targetError;
      }
    }
    return null;
  }

  String? _visitAssignmentIndex(AssignmentIndexAccessExpr statement) {
    final targetError = _visitExpression(statement.target);
    if (targetError != null) {
      return targetError;
    }

    final indexError = _visitExpression(statement.index);
    if (indexError != null) {
      return indexError;
    }

    return _visitExpression(statement.value);
  }

  String? _visitIfStatement(IfStatement statement) {
    final conditionError = _visitExpression(statement.cond);
    if (conditionError != null) {
      return conditionError;
    }

    final thenError = _visitScopedBlock(statement.thenBlock);
    if (thenError != null) {
      return thenError;
    }

    for (final clause in statement.elseIfs) {
      final clauseConditionError = _visitExpression(clause.cond);
      if (clauseConditionError != null) {
        return clauseConditionError;
      }
      final clauseError = _visitScopedBlock(clause.thenBlock);
      if (clauseError != null) {
        return clauseError;
      }
    }

    return _visitScopedBlock(statement.elseBlock);
  }

  String? _visitWhileStatement(WhileStatement statement) {
    final conditionError = _visitExpression(statement.cond);
    if (conditionError != null) {
      return conditionError;
    }
    return _visitScopedBlock(statement.body);
  }

  String? _visitForLoop(ForLoop statement) {
    final startError = _visitExpression(statement.start);
    if (startError != null) {
      return startError;
    }
    final endError = _visitExpression(statement.endExpr);
    if (endError != null) {
      return endError;
    }
    final stepError = _visitExpression(statement.stepExpr);
    if (stepError != null) {
      return stepError;
    }

    _enterScope();
    _currentScope.locals[statement.varName.name] = 'const';
    final bodyError = _visitStatements(statement.body);
    _exitScope();
    return bodyError;
  }

  String? _visitForInLoop(ForInLoop statement) {
    final iterError = _visitExpressions(statement.iterators);
    if (iterError != null) {
      return iterError;
    }

    _enterScope();
    for (final name in statement.names) {
      _currentScope.locals[name.name] = '';
    }
    final bodyError = _visitStatements(statement.body);
    _exitScope();
    return bodyError;
  }

  String? _visitRepeatUntil(RepeatUntilLoop statement) {
    _enterScope();
    final bodyError = _visitStatements(statement.body);
    if (bodyError != null) {
      _exitScope();
      return bodyError;
    }
    final conditionError = _visitExpression(statement.cond);
    _exitScope();
    return conditionError;
  }

  String? _visitFunctionDef(FunctionDef statement) {
    if (statement.explicitGlobal &&
        statement.name.rest.isEmpty &&
        statement.name.method == null) {
      final resolution = _resolveExplicitGlobalTarget(statement.name.first.name);
      if (resolution != null && _isImmutable(resolution.attribute)) {
        return _constAssignmentError(statement, statement.name.first.name);
      }
      _currentScope.namedGlobals[statement.name.first.name] = '';
    }

    final bodyError = _visitFunctionBody(
      statement.body,
      implicitSelf: statement.implicitSelf,
    );
    if (bodyError != null) {
      return bodyError;
    }

    if (!statement.explicitGlobal && statement.name.rest.isEmpty) {
      return _visitStoreTarget(statement.name.first);
    }

    return _visitFunctionNameStore(statement.name);
  }

  String? _visitLocalFunctionDef(LocalFunctionDef statement) {
    _currentScope.locals[statement.name.name] = '';
    return _visitFunctionBody(statement.funcBody);
  }

  String? _visitFunctionBody(FunctionBody body, {bool implicitSelf = false}) {
    _enterFunction();
    if (implicitSelf) {
      _currentScope.locals['self'] = '';
    }
    for (final parameter in body.parameters ?? const <Identifier>[]) {
      _currentScope.locals[parameter.name] = '';
    }
    if (body.varargName case final Identifier name) {
      _currentScope.locals[name.name] = 'const';
    }
    final error = _visitStatements(body.body);
    _exitFunction();
    return error;
  }

  String? _visitFunctionNameStore(FunctionName name) {
    final resolution = _resolveName(name.first.name);
    if (resolution.kind == _ResolvedNameKind.undeclared) {
      return _undeclaredError(name.first);
    }
    final isDirectNameStore = name.rest.isEmpty && name.method == null;
    if (isDirectNameStore && _isImmutable(resolution.attribute)) {
      return _constAssignmentError(name.first, name.first.name);
    }
    return null;
  }

  String? _visitExpressions(List<AstNode> expressions) {
    for (final expression in expressions) {
      final error = _visitExpression(expression);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitExpression(AstNode node) => switch (node) {
    Identifier() => _visitIdentifier(node),
    GroupedExpression() => _visitExpression(node.expr),
    BinaryExpression() => _visitBinaryExpression(node),
    UnaryExpression() => _visitExpression(node.expr),
    FunctionCall() => _visitFunctionCall(node),
    MethodCall() => _visitMethodCall(node),
    TableFieldAccess() => _visitExpression(node.table),
    TableIndexAccess() => _visitTableIndexAccess(node),
    TableAccessExpr() => _visitTableAccess(node),
    TableConstructor() => _visitTableConstructor(node),
    FunctionLiteral() => _visitFunctionBody(node.funcBody),
    YieldStatement() => _visitExpressions(node.expr),
    NumberLiteral() ||
    StringLiteral() ||
    BooleanLiteral() ||
    NilValue() ||
    VarArg() => null,
    final other => _visitStatement(other),
  };

  String? _visitIdentifier(Identifier node) {
    final resolution = _resolveName(node.name);
    if (resolution.kind == _ResolvedNameKind.undeclared) {
      return _undeclaredError(node);
    }
    return null;
  }

  String? _visitBinaryExpression(BinaryExpression node) {
    final leftError = _visitExpression(node.left);
    if (leftError != null) {
      return leftError;
    }
    return _visitExpression(node.right);
  }

  String? _visitFunctionCall(FunctionCall node) {
    final targetError = _visitExpression(node.name);
    if (targetError != null) {
      return targetError;
    }
    return _visitExpressions(node.args);
  }

  String? _visitMethodCall(MethodCall node) {
    final prefixError = _visitExpression(node.prefix);
    if (prefixError != null) {
      return prefixError;
    }
    return _visitExpressions(node.args);
  }

  String? _visitTableIndexAccess(TableIndexAccess node) {
    final tableError = _visitExpression(node.table);
    if (tableError != null) {
      return tableError;
    }
    return _visitExpression(node.index);
  }

  String? _visitTableAccess(TableAccessExpr node) {
    final tableError = _visitExpression(node.table);
    if (tableError != null) {
      return tableError;
    }
    return _visitExpression(node.index);
  }

  String? _visitTableConstructor(TableConstructor node) {
    for (final entry in node.entries) {
      final error = switch (entry) {
        KeyedTableEntry() => _visitExpression(entry.value),
        IndexedTableEntry() => (() {
          final keyError = _visitExpression(entry.key);
          if (keyError != null) {
            return keyError;
          }
          return _visitExpression(entry.value);
        })(),
        TableEntryLiteral() => _visitExpression(entry.expr),
        final other => _visitExpression(other),
      };
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _visitStoreTarget(AstNode target) => switch (target) {
    Identifier() => (() {
      final resolution = _resolveName(target.name);
      return switch (resolution.kind) {
        _ResolvedNameKind.undeclared => _undeclaredError(target),
        _ when _isImmutable(resolution.attribute) => _constAssignmentError(
          target,
          target.name,
        ),
        _ => null,
      };
    })(),
    TableFieldAccess() => _visitExpression(target.table),
    TableIndexAccess() => _visitTableIndexAccess(target),
    TableAccessExpr() => _visitTableAccess(target),
    AssignmentIndexAccessExpr() => _visitAssignmentIndex(target),
    final other => _visitExpression(other),
  };

  _ResolvedName _resolveName(String name) {
    if (name == '_ENV') {
      return const _ResolvedName.implicitGlobal();
    }
    return _resolveNameInFunction(_functions.length - 1, name, _LookupState());
  }

  _ResolvedName _resolveNameInFunction(
    int functionIndex,
    String name,
    _LookupState state,
  ) {
    final function = _functions[functionIndex];
    for (final scope in function.scopes.reversed) {
      if (scope.locals[name] case final attribute?) {
        return _ResolvedName.local(attribute);
      }
      if (scope.namedGlobals[name] case final attribute?) {
        return _ResolvedName.global(attribute);
      }
      if (state.collectiveAttribute == null &&
          scope.collectiveAttribute != null) {
        final collective = scope.collectiveAttribute!;
        state.collectiveAttribute = collective;
      }
      if (state.collectiveAttribute == null &&
          (scope.namedGlobals.isNotEmpty || scope.invalidatesImplicitGlobals)) {
        state.hasNamedDeclaration = true;
      }
    }

    if (functionIndex > 0) {
      final outer = _resolveNameInFunction(functionIndex - 1, name, state);
      if (outer.kind != _ResolvedNameKind.implicitGlobal &&
          outer.kind != _ResolvedNameKind.undeclared) {
        return outer;
      }
    }

    if (state.collectiveAttribute case final collective?) {
      return _ResolvedName.global(collective);
    }
    if (state.hasNamedDeclaration) {
      return const _ResolvedName.undeclared();
    }
    return const _ResolvedName.implicitGlobal();
  }

  _ResolvedName? _resolveExplicitGlobalTarget(String name) {
    for (var functionIndex = _functions.length - 1; functionIndex >= 0; functionIndex--) {
      final function = _functions[functionIndex];
      for (final scope in function.scopes.reversed) {
        if (scope.locals[name] case final attribute?) {
          return _ResolvedName.local(attribute);
        }
        if (scope.namedGlobals[name] case final attribute?) {
          return _ResolvedName.global(attribute);
        }
      }
    }
    return null;
  }

  bool _isImmutable(String attribute) =>
      attribute == 'const' || attribute == 'close';

  String _undeclaredError(AstNode node) {
    final name = node is Identifier ? node.name : node.toSource();
    return ":${_lineOf(node)}: variable '$name' not declared";
  }

  String _constAssignmentError(AstNode node, String name) =>
      ":${_lineOf(node)}: attempt to assign to const variable '$name'";

  int _lineOf(AstNode node) => (node.span?.start.line ?? 0) + 1;

  _ScopeState get _currentScope => _functions.last.scopes.last;

  void _enterScope() {
    _functions.last.scopes.add(_ScopeState());
  }

  void _exitScope() {
    _functions.last.scopes.removeLast();
  }

  void _enterFunction() {
    _functions.add(_FunctionScopeState.root());
  }

  void _exitFunction() {
    _functions.removeLast();
  }
}

final class _FunctionScopeState {
  _FunctionScopeState.root() : scopes = <_ScopeState>[_ScopeState()];

  final List<_ScopeState> scopes;
}

final class _ScopeState {
  final Map<String, String> locals = <String, String>{};
  final Map<String, String> namedGlobals = <String, String>{};
  String? collectiveAttribute;
  bool invalidatesImplicitGlobals = false;
}

final class _LookupState {
  String? collectiveAttribute;
  bool hasNamedDeclaration = false;
}

enum _ResolvedNameKind { local, global, implicitGlobal, undeclared }

final class _ResolvedName {
  const _ResolvedName.local(this.attribute) : kind = _ResolvedNameKind.local;

  const _ResolvedName.global(this.attribute) : kind = _ResolvedNameKind.global;

  const _ResolvedName.implicitGlobal()
    : kind = _ResolvedNameKind.implicitGlobal,
      attribute = '';

  const _ResolvedName.undeclared()
    : kind = _ResolvedNameKind.undeclared,
      attribute = '';

  final _ResolvedNameKind kind;
  final String attribute;
}
