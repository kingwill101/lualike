import 'package:source_span/source_span.dart';

import 'ast.dart';

/// Validates goto/label usage in a parsed chunk.
///
/// Mirrors Lua's compile-time checks to ensure we reject invalid
/// goto statements during `load()` rather than at runtime.
class GotoLabelValidator {
  /// Checks the provided [program] for goto/label rule violations.
  ///
  /// Returns an error string if a violation is found, or `null` when
  /// the AST complies with Lua's rules.
  String? checkGotoLabelViolations(Program program) {
    final state = _ValidatorState();
    return state.validateChunk(program.statements);
  }

  /// Validates a nested [FunctionBody]. Used when function literals or
  /// declarations appear inside a chunk.
  String? checkFunctionBody(FunctionBody body) {
    final state = _ValidatorState();
    return state.validateChunk(
      body.body,
      parameters: body.parameters ?? const <Identifier>[],
    );
  }
}

class _ValidatorState {
  final List<_LocalInfo> _activeLocals = [];

  String? validateChunk(
    List<AstNode> statements, {
    List<Identifier> parameters = const <Identifier>[],
  }) {
    final root = _BlockContext(
      parent: null,
      depth: 0,
      activeLocalStartIndex: _activeLocals.length,
    );

    for (final param in parameters) {
      _addLocal(param.name, param.span, root);
    }

    final error = _processBlock(statements, root);
    if (error != null) {
      return error;
    }

    final finishError = _finishBlock(root, isRoot: true);
    if (finishError != null) {
      return finishError;
    }

    return null;
  }

  String? _processBlock(List<AstNode> statements, _BlockContext block) {
    for (final stmt in statements) {
      final error = _visitStatement(stmt, block);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? _finishBlock(_BlockContext block, {required bool isRoot}) {
    if (_activeLocals.length > block.activeLocalStartIndex) {
      _activeLocals.removeRange(
        block.activeLocalStartIndex,
        _activeLocals.length,
      );
    }

    final parent = block.parent;
    if (parent != null) {
      for (final pending in block.pendingGotos) {
        if (pending.activeLocalCount > _activeLocals.length) {
          pending.activeLocalCount = _activeLocals.length;
        }
        parent.pendingGotos.add(pending);
      }
    } else if (isRoot) {
      if (block.pendingGotos.isNotEmpty) {
        return _errorNoVisibleLabel(block.pendingGotos.first);
      }
    }

    return null;
  }

  String? _visitStatement(AstNode node, _BlockContext block) {
    if (node is Label) {
      return _handleLabel(node, block);
    }

    if (node is Goto) {
      block.pendingGotos.add(
        _PendingGoto(
          node: node,
          labelName: node.label.name,
          activeLocalCount: _activeLocals.length,
          originBlock: block,
        ),
      );
      return null;
    }

    if (node is LocalDeclaration) {
      for (final name in node.names) {
        _addLocal(name.name, name.span ?? node.span, block);
      }
      for (final expr in node.exprs) {
        final error = _visitExpression(expr, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is LocalFunctionDef) {
      _addLocal(node.name.name, node.name.span ?? node.span, block);
      return _validateFunctionBody(node.funcBody);
    }

    if (node is FunctionDef) {
      return _validateFunctionBody(node.body);
    }

    if (node is Assignment) {
      for (final expr in node.exprs) {
        final error = _visitExpression(expr, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is ExpressionStatement) {
      return _visitExpression(node.expr, block);
    }

    if (node is ReturnStatement) {
      for (final expr in node.expr) {
        final error = _visitExpression(expr, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is YieldStatement) {
      for (final expr in node.expr) {
        final error = _visitExpression(expr, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is DoBlock) {
      return _withChildBlock(node.body, block);
    }

    if (node is WhileStatement) {
      final condError = _visitExpression(node.cond, block);
      if (condError != null) return condError;
      return _withChildBlock(node.body, block);
    }

    if (node is RepeatUntilLoop) {
      final bodyError = _withChildBlock(node.body, block);
      if (bodyError != null) return bodyError;
      return _visitExpression(node.cond, block);
    }

    if (node is IfStatement) {
      final condError = _visitExpression(node.cond, block);
      if (condError != null) return condError;

      final thenError = _withChildBlock(node.thenBlock, block);
      if (thenError != null) return thenError;

      for (final clause in node.elseIfs) {
        final clauseCondError = _visitExpression(clause.cond, block);
        if (clauseCondError != null) return clauseCondError;
        final clauseError = _withChildBlock(clause.thenBlock, block);
        if (clauseError != null) return clauseError;
      }

      if (node.elseBlock.isNotEmpty) {
        final elseError = _withChildBlock(node.elseBlock, block);
        if (elseError != null) return elseError;
      }
      return null;
    }

    if (node is ForLoop) {
      final startError = _visitExpression(node.start, block);
      if (startError != null) return startError;
      final endError = _visitExpression(node.endExpr, block);
      if (endError != null) return endError;
      final stepError = _visitExpression(node.stepExpr, block);
      if (stepError != null) return stepError;

      return _withChildBlock(
        node.body,
        block,
        onEnter: (child) =>
            _addLocal(node.varName.name, node.varName.span, child),
      );
    }

    if (node is ForInLoop) {
      for (final iterator in node.iterators) {
        final error = _visitExpression(iterator, block);
        if (error != null) return error;
      }

      return _withChildBlock(
        node.body,
        block,
        onEnter: (child) {
          for (final name in node.names) {
            _addLocal(name.name, name.span ?? node.span, child);
          }
        },
      );
    }

    if (node is FunctionBody) {
      return _validateFunctionBody(node);
    }

    if (node is AssignmentIndexAccessExpr) {
      final valueError = _visitExpression(node.value, block);
      if (valueError != null) return valueError;
      final targetError = _visitExpression(node.target, block);
      if (targetError != null) return targetError;
      return _visitExpression(node.index, block);
    }

    // Other statement types either do not introduce scopes or
    // do not contain nested statements relevant for goto validation.
    return null;
  }

  String? _withChildBlock(
    List<AstNode> statements,
    _BlockContext parent, {
    void Function(_BlockContext child)? onEnter,
  }) {
    final child = _BlockContext(
      parent: parent,
      depth: parent.depth + 1,
      activeLocalStartIndex: _activeLocals.length,
    );

    onEnter?.call(child);

    final error = _processBlock(statements, child);
    if (error != null) {
      return error;
    }

    return _finishBlock(child, isRoot: false);
  }

  String? _visitExpression(AstNode node, _BlockContext block) {
    if (node is FunctionLiteral) {
      return _validateFunctionBody(node.funcBody);
    }

    if (node is TableConstructor) {
      for (final entry in node.entries) {
        final error = _visitExpression(entry, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is KeyedTableEntry) {
      final keyError = _visitExpression(node.key, block);
      if (keyError != null) return keyError;
      return _visitExpression(node.value, block);
    }

    if (node is IndexedTableEntry) {
      final keyError = _visitExpression(node.key, block);
      if (keyError != null) return keyError;
      return _visitExpression(node.value, block);
    }

    if (node is TableEntryLiteral) {
      return _visitExpression(node.expr, block);
    }

    if (node is BinaryExpression) {
      final leftError = _visitExpression(node.left, block);
      if (leftError != null) return leftError;
      return _visitExpression(node.right, block);
    }

    if (node is UnaryExpression) {
      return _visitExpression(node.expr, block);
    }

    if (node is FunctionCall) {
      final nameError = _visitExpression(node.name, block);
      if (nameError != null) return nameError;
      for (final arg in node.args) {
        final error = _visitExpression(arg, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is MethodCall) {
      final prefixError = _visitExpression(node.prefix, block);
      if (prefixError != null) return prefixError;
      final methodError = _visitExpression(node.methodName, block);
      if (methodError != null) return methodError;
      for (final arg in node.args) {
        final error = _visitExpression(arg, block);
        if (error != null) return error;
      }
      return null;
    }

    if (node is TableAccessExpr) {
      final targetError = _visitExpression(node.table, block);
      if (targetError != null) return targetError;
      return _visitExpression(node.index, block);
    }

    if (node is GroupedExpression) {
      return _visitExpression(node.expr, block);
    }

    if (node is AssignmentIndexAccessExpr) {
      final targetError = _visitExpression(node.target, block);
      if (targetError != null) return targetError;
      final indexError = _visitExpression(node.index, block);
      if (indexError != null) return indexError;
      return _visitExpression(node.value, block);
    }

    // Literals, identifiers, and other nodes do not contain nested
    // statements that affect goto validation.
    return null;
  }

  String? _handleLabel(Label label, _BlockContext block) {
    final name = label.label.name;

    for (_BlockContext? ctx = block; ctx != null; ctx = ctx.parent) {
      final current = ctx;
      if (current.labels.containsKey(name)) {
        final line = _line(label.span);
        return "label '$name' already defined at line $line";
      }
    }

    block.labels[name] = label;

    for (_BlockContext? ctx = block; ctx != null; ctx = ctx.parent) {
      final current = ctx;
      final remaining = <_PendingGoto>[];
      for (final pending in current.pendingGotos) {
        if (pending.labelName != name) {
          remaining.add(pending);
          continue;
        }

        if (!pending.originBlock.isDescendantOf(block)) {
          remaining.add(pending);
          continue;
        }

        final error = _validateGotoAgainstLabel(pending);
        if (error != null) {
          return error;
        }
      }
      current.pendingGotos
        ..clear()
        ..addAll(remaining);
    }

    return null;
  }

  String? _validateGotoAgainstLabel(_PendingGoto pending) {
    if (pending.activeLocalCount < _activeLocals.length) {
      final local = _activeLocals[pending.activeLocalCount];
      final line = _line(pending.node.span);
      return "<goto ${pending.labelName}> at line $line jumps into the scope of local '${local.name}'";
    }
    return null;
  }

  void _addLocal(String name, SourceSpan? span, _BlockContext block) {
    _activeLocals.add(_LocalInfo(name: name, span: span, declaredIn: block));
  }

  String _errorNoVisibleLabel(_PendingGoto pending) {
    final line = _line(pending.node.span);
    return "no visible label '${pending.labelName}' for <goto> at line $line";
  }

  String _line(SourceSpan? span) {
    if (span == null) {
      return '0';
    }
    return (span.start.line + 1).toString();
  }

  String? _validateFunctionBody(FunctionBody body) {
    final validator = GotoLabelValidator();
    return validator.checkFunctionBody(body);
  }
}

class _BlockContext {
  _BlockContext({
    required this.parent,
    required this.depth,
    required this.activeLocalStartIndex,
  });

  final _BlockContext? parent;
  final int depth;
  final int activeLocalStartIndex;
  final Map<String, Label> labels = {};
  final List<_PendingGoto> pendingGotos = [];

  bool isDescendantOf(_BlockContext other) {
    for (_BlockContext? ctx = this; ctx != null; ctx = ctx.parent) {
      final current = ctx;
      if (identical(current, other)) {
        return true;
      }
    }
    return false;
  }
}

class _PendingGoto {
  _PendingGoto({
    required this.node,
    required this.labelName,
    required this.activeLocalCount,
    required this.originBlock,
  });

  final Goto node;
  final String labelName;
  int activeLocalCount;
  final _BlockContext originBlock;
}

class _LocalInfo {
  _LocalInfo({
    required this.name,
    required this.span,
    required this.declaredIn,
  });

  final String name;
  final SourceSpan? span;
  final _BlockContext declaredIn;
}
