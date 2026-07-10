/// Simplifies a folded AST by replacing constant expressions with literals
/// and removing dead branches.
///
/// Run after [ConstantFoldingPass.fold()] to produce a clean AST that
/// downstream compilers can emit without checking a side-channel.
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/fold_result.dart';

class ASTSimplifier {
  final ConstantFoldingResult result;

  ASTSimplifier(this.result);

  /// Apply folding results to produce a simplified [Program].
  ///
  /// Folded expressions → literals, dead branches removed, inlined calls
  /// replaced by their return values.
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
            final liveBlock = _simplifyBlock(thenBlock);
            if (liveBlock.length == 1) return liveBlock[0];
            if (liveBlock.isEmpty) return null;
            return DoBlock(liveBlock);
          }
          for (final clause in elseIfs) {
            if (result.isConstant(clause.cond) &&
                _isTruthy(result.getValue(clause.cond))) {
              final liveBlock = _simplifyBlock(clause.thenBlock);
              if (liveBlock.length == 1) return liveBlock[0];
              if (liveBlock.isEmpty) return null;
              return DoBlock(liveBlock);
            }
          }
          if (elseBlock.isNotEmpty) {
            final liveBlock = _simplifyBlock(elseBlock);
            if (liveBlock.length == 1) return liveBlock[0];
            if (liveBlock.isEmpty) return null;
            return DoBlock(liveBlock);
          }
          return null;
        }
        final simplified = _simplifyBlock(thenBlock);
        final simplifiedElse = _simplifyBlock(elseBlock);
        final simplifiedElseIfs = elseIfs
            .map(
              (c) => ElseIfClause(c.cond, _simplifyBlock(c.thenBlock)),
            )
            .toList();
        if (identical(simplified, thenBlock) &&
            identical(simplifiedElse, elseBlock) &&
            identical(simplifiedElseIfs, elseIfs)) {
          return null;
        }
        return IfStatement(
          cond,
          simplifiedElseIfs,
          simplified,
          simplifiedElse,
        );

      case WhileStatement(:final cond, :final body):
        if (result.isConstant(cond) &&
            !_isTruthy(result.getValue(cond))) {
          return null;
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
        final simplified =
            _simplifyExpr(expr.isNotEmpty ? expr.first : null);
        if (simplified != null) return ReturnStatement([simplified]);
        return null;

      case ExpressionStatement(:final expr):
        final simplified = _simplifyExpr(expr);
        return simplified != null
            ? ExpressionStatement(simplified)
            : null;

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

      case LocalDeclaration(:final names, :final attributes, :final exprs):
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

  /// Simplify an expression to a literal if folded, else null.
  AstNode? _simplifyExpr(AstNode? node) {
    if (node == null) return null;

    // Expression reassociation: (nonconst + C1) + C2 → nonconst + (C1 + C2)
    if (node is BinaryExpression) {
      final reassociated = _tryReassociate(node);
      if (reassociated != null) return reassociated;
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

  /// (nonconst + 2) + 3  →  nonconst + 5
  AstNode? _tryReassociate(BinaryExpression node) {
    if (node.left is! BinaryExpression) return null;
    final inner = node.left as BinaryExpression;
    if (inner.op != node.op) return null;
    if (!_reassociationSupported.contains(node.op)) return null;
    if (!result.isConstant(inner.right)) return null;
    if (!result.isConstant(node.right)) return null;

    final combined = BinaryExpression(inner.right, node.op, node.right);
    // Fold the combined constants using the analysis pass.
    // Since we're post-fold, we check if the inner.right and node.right
    // are already individually folded; we need to compute their combined
    // value.  We use result.getValue directly for the two constants.
    final lv = result.getValue(inner.right);
    final rv = result.getValue(node.right);
    Object? combinedValue;
    if (lv is num && rv is num) {
      switch (node.op) {
        case '+': combinedValue = lv + rv;
        case '*': combinedValue = lv * rv;
      }
    }
    if (combinedValue == null) return null;

    // Build: nonconst OP combinedValue
    final newRight = _literalFor(combinedValue);
    return BinaryExpression(inner.left, node.op, newRight ?? combined);
  }

  static const _reassociationSupported = {'+', '*'};

  AstNode? _literalFor(Object? value) {
    if (value == ConstantFoldingResult.constantNil) return NilValue();
    if (value is bool) return BooleanLiteral(value);
    if (value is int) return NumberLiteral(value);
    if (value is double) return NumberLiteral(value);
    return null;
  }

  bool _isTruthy(Object? value) {
    if (value == null || value == ConstantFoldingResult.constantNil) {
      return false;
    }
    if (value is bool) return value;
    return true;
  }
}
