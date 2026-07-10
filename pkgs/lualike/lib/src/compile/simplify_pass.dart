/// Rewrites a folded AST to replace constant expressions with literals.
///
/// After the [ConstantFoldingPass] has determined which nodes are
/// compile-time constants, this pass physically rewrites the AST:
/// folded expressions become literal nodes, dead branches are removed,
/// and inlined function calls are replaced by their return values.
///
/// Downstream compilers can then emit the simplified AST directly
/// without consulting a side-channel.
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/fold_result.dart';

/// Rewrites a [Program] AST, replacing folded expressions with literals.
///
/// Usage:
/// ```dart
/// final foldPass = ConstantFoldingPass();
/// foldPass.fold(program);
/// final simplified = ASTSimplifier(foldPass.result).simplify(program);
/// ```
class ASTSimplifier {
  /// The folding result to use for determining which nodes are constant.
  final ConstantFoldingResult result;

  ASTSimplifier(this.result);

  /// Returns a new [Program] with all folding simplifications applied.
  ///
  /// Folded expressions become [NumberLiteral], [StringLiteral],
  /// [BooleanLiteral], or [NilValue] nodes.  Dead if/while branches
  /// are removed entirely.  The original [program] is not modified.
  Program simplify(Program program) {
    final stmts = _simplifyBlock(program.statements);
    return identical(stmts, program.statements) ? program : Program(stmts);
  }

  List<AstNode> _simplifyBlock(List<AstNode> stmts) {
    List<AstNode>? result;
    for (var i = 0; i < stmts.length; i++) {
      final simplified = _simplifyStmt(stmts[i]);
      if (simplified != null) {
        (result ??= List<AstNode>.of(stmts))[i] = simplified;
      }
    }
    return result ?? stmts;
  }

  /// Returns a replacement for [node], or `null` if unchanged.
  AstNode? _simplifyStmt(AstNode node) {
    switch (node) {
      case IfStatement(
        :final cond,
        :final thenBlock,
        :final elseIfs,
        :final elseBlock,
      ):
        if (result.isConstant(cond)) {
          final cv = result.getValue(cond);
          if (_isTruthy(cv)) {
            // Condition is truthy — emit only the then-branch.
            final live = _simplifyBlock(thenBlock);
            if (live.length == 1) return live[0];
            return live.isEmpty ? null : DoBlock(live);
          }
          // Condition is falsy — walk else-if chain.
          for (final clause in elseIfs) {
            if (result.isConstant(clause.cond) &&
                _isTruthy(result.getValue(clause.cond))) {
              final live = _simplifyBlock(clause.thenBlock);
              if (live.length == 1) return live[0];
              return live.isEmpty ? null : DoBlock(live);
            }
          }
          // All falsy — emit else-block or nothing.
          if (elseBlock.isNotEmpty) {
            final live = _simplifyBlock(elseBlock);
            if (live.length == 1) return live[0];
            return live.isEmpty ? null : DoBlock(live);
          }
          return null; // Entire if is dead.
        }
        // Non-const condition: recurse into all branches.
        final then = _simplifyBlock(thenBlock);
        final els = _simplifyBlock(elseBlock);
        final eifs = elseIfs
            .map((c) => ElseIfClause(c.cond, _simplifyBlock(c.thenBlock)))
            .toList();
        if (identical(then, thenBlock) &&
            identical(els, elseBlock) &&
            identical(eifs, elseIfs)) {
          return null;
        }
        return IfStatement(cond, eifs, then, els);

      case WhileStatement(:final cond, :final body):
        if (result.isConstant(cond) &&
            !_isTruthy(result.getValue(cond))) {
          return null; // Entire loop is dead code.
        }
        final simplified = _simplifyBlock(body);
        return identical(simplified, body)
            ? null
            : WhileStatement(cond, simplified);

      case DoBlock(:final body):
        final simplified = _simplifyBlock(body);
        if (identical(simplified, body)) return null;
        if (simplified.length == 1) return simplified[0];
        if (simplified.isEmpty) return null;
        return DoBlock(simplified);

      case ReturnStatement(:final expr):
        final s = _simplifyExpr(expr.isNotEmpty ? expr.first : null);
        return s != null ? ReturnStatement([s]) : null;

      case ExpressionStatement(:final expr):
        final s = _simplifyExpr(expr);
        return s != null ? ExpressionStatement(s) : null;

      case Assignment(:final targets, :final exprs):
        var changed = false;
        final newExprs = exprs.map((e) {
          final s = _simplifyExpr(e);
          if (s != null) {
            changed = true;
            return s;
          }
          return e;
        }).toList();
        return changed ? Assignment(targets, newExprs) : null;

      case LocalDeclaration(
        :final names,
        :final attributes,
        :final exprs,
      ):
        var changed = false;
        final newExprs = exprs.map((e) {
          final s = _simplifyExpr(e);
          if (s != null) {
            changed = true;
            return s;
          }
          return e;
        }).toList();
        return changed
            ? LocalDeclaration(names, attributes, newExprs)
            : null;

      default:
        return null;
    }
  }

  /// Returns a literal replacement for a folded expression, or `null`.
  AstNode? _simplifyExpr(AstNode? node) {
    if (node == null) return null;

    // Expression reassociation: pull constants up for further folding.
    if (node is BinaryExpression) {
      final r = _tryReassociate(node);
      if (r != null) return r;
    }

    if (!result.isConstant(node)) return null;
    final value = result.getValue(node);
    if (value == ConstantFoldingResult.constantNil) return NilValue();
    if (value is bool) return BooleanLiteral(value);
    if (value is int) return NumberLiteral(value);
    if (value is double) return NumberLiteral(value);
    if (value is BigInt) return NumberLiteral(value);
    if (value is List<int>) {
      return StringLiteral(String.fromCharCodes(value), isLongString: false);
    }
    return null;
  }

  /// Reassociates `(nonconst + C1) + C2` into `nonconst + (C1 + C2)`.
  ///
  /// Only applies to associative operators (`+`, `*`).  This allows
  /// subsequent passes to fold the combined constant.
  AstNode? _tryReassociate(BinaryExpression node) {
    if (node.left is! BinaryExpression) return null;
    final inner = node.left as BinaryExpression;
    if (inner.op != node.op) return null;
    if (!_reassociationSupported.contains(node.op)) return null;
    if (!result.isConstant(inner.right)) return null;
    if (!result.isConstant(node.right)) return null;

    final lv = result.getValue(inner.right);
    final rv = result.getValue(node.right);
    Object? combined;
    if (lv is num && rv is num) {
      switch (node.op) {
        case '+': combined = lv + rv;
        case '*': combined = lv * rv;
      }
    }
    if (combined == null) return null;
    final newRight = _literalFor(combined);
    return BinaryExpression(inner.left, node.op, newRight ?? inner.right);
  }

  static const _reassociationSupported = {'+', '*'};

  /// Returns a literal node for [value], or `null`.
  AstNode? _literalFor(Object? value) {
    if (value == ConstantFoldingResult.constantNil) return NilValue();
    if (value is bool) return BooleanLiteral(value);
    if (value is int) return NumberLiteral(value);
    if (value is double) return NumberLiteral(value);
    return null;
  }

  /// Whether [value] is truthy following Lua semantics.
  bool _isTruthy(Object? value) {
    if (value == null || value == ConstantFoldingResult.constantNil) {
      return false;
    }
    if (value is bool) return value;
    return true;
  }
}
