import 'ast.dart';
import 'const_checker.dart';

String? validateProgramSemantics(Program program) {
  final constChecker = ConstChecker();
  final constError = constChecker.checkConstViolations(program);
  if (constError != null) {
    return constError;
  }

  return GlobalChecker().check(program);
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
    ReturnStatement() => _visitExpressions(statement.expr),
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
      _currentScope.locals[name.name] = 'const';
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
      final resolution = _resolveName(statement.name.first.name);
      if (_isImmutable(resolution.attribute)) {
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

  String? _visitFunctionBody(
    FunctionBody body, {
    bool implicitSelf = false,
  }) {
    _enterFunction();
    if (implicitSelf) {
      _currentScope.locals['self'] = '';
    }
    for (final parameter in body.parameters ?? const <Identifier>[]) {
      _currentScope.locals[parameter.name] = '';
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
        _ when _isImmutable(resolution.attribute) =>
          _constAssignmentError(target, target.name),
        _ => null,
      };
    })(),
    TableFieldAccess() => _visitExpression(target.table),
    TableIndexAccess() => _visitTableIndexAccess(target),
    TableAccessExpr() => _visitTableAccess(target),
    AssignmentIndexAccessExpr() => _visitAssignmentIndex(target),
    final other => _visitExpression(other),
  };

  _ResolvedName _resolveName(String name) =>
      _resolveNameInFunction(_functions.length - 1, name, _LookupState());

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
