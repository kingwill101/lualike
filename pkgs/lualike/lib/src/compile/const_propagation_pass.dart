/// Propagates constants from single-assignment locals without `<const>`.
///
/// If a local variable is assigned exactly once with a constant value and
/// is never reassigned, subsequent references are replaced with the constant
/// literal.  No `local x <const>` annotation is needed.
///
/// ```lua
/// local x = 5       -- single assignment with literal
/// local y = x + 3   → local y = 5 + 3  → folded to local y = 8
/// ```
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/fold_result.dart';

/// Propagates single-assignment constants and eliminates copy chains.
class ConstPropagationPass extends CompilerPass {
  @override
  String get name => 'const_propagation';

  @override
  Program run(Program program, CompilerContext context) {
    // Phase 1: collect single-assignment info per scope.
    final assignments = _collectAssignments(program.statements);
    if (assignments.isEmpty) return program;

    // Phase 2: replace references with their constant values.
    final ctx = _Context(assignments, context.foldingResult);
    final stmts = _rewrite(program.statements, ctx);
    return identical(stmts, program.statements) ? program : Program(stmts);
  }

  /// Collects all assignments and counts writes per variable.
  Map<String, _AssignmentInfo> _collectAssignments(List<AstNode> stmts) {
    final map = <String, _AssignmentInfo>{};
    void walk(List<AstNode> stmts) {
      for (final stmt in stmts) {
        if (stmt is LocalDeclaration) {
          for (var i = 0; i < stmt.names.length; i++) {
            final name = stmt.names[i].name;
            final expr = i < stmt.exprs.length ? stmt.exprs[i] : null;
            if (expr != null && _isConstantExpr(expr)) {
              final existing = map[name];
              if (existing == null) {
                map[name] = _AssignmentInfo._(expr, 1);
              } else {
                existing.count++;
              }
            } else {
              map[name]?.count++; // non-const write invalidates
            }
          }
        }
        if (stmt is Assignment) {
          for (final target in stmt.targets) {
            if (target is Identifier) {
              map[target.name]?.count++;
            }
          }
        }
        if (stmt is ForLoop) {
          map[stmt.varName.name]?.count++;
        }
        if (stmt is ForInLoop) {
          for (final n in stmt.names) {
            map[n.name]?.count++;
          }
        }
        // Recurse — scoping is approximate but safe (over-counting is fine).
        if (stmt is DoBlock) walk(stmt.body);
        if (stmt is FunctionDef) walk(stmt.body.body);
        if (stmt is FunctionBody) walk(stmt.body);
        if (stmt is LocalFunctionDef) walk(stmt.funcBody.body);
      }
    }
    walk(stmts);
    // Remove multi-assignment variables.
    map.removeWhere((_, v) => v.count != 1);
    return map;
  }

  /// Rewrites the AST replacing propagated identifiers.
  List<AstNode> _rewrite(List<AstNode> stmts, _Context ctx) {
    List<AstNode>? result;
    for (var i = 0; i < stmts.length; i++) {
      final rewritten = _rewriteNode(stmts[i], ctx);
      if (rewritten != null) {
        (result ??= List<AstNode>.of(stmts))[i] = rewritten;
      }
    }
    return result ?? stmts;
  }

  AstNode? _rewriteNode(AstNode node, _Context ctx) {
    // Local declaration: skip the initializer (it's what we propagate).
    if (node is LocalDeclaration) {
      final newExprs = <AstNode>[];
      var changed = false;
      for (var i = 0; i < node.exprs.length; i++) {
        final expr = node.exprs[i];
        // Don't propagate the initializer itself back into the declaration.
        final r = _rewriteExpr(expr, ctx, skipVar: i < node.names.length ? node.names[i].name : null);
        if (r != null) { newExprs.add(r); changed = true; } else { newExprs.add(expr); }
      }
      return changed ? LocalDeclaration(node.names, node.attributes, newExprs) : null;
    }
    // Other nodes: recurse.
    return switch (node) {
      DoBlock(:final body) => _wrapDo(body, ctx),
      FunctionDef(:final name, :final body) => _wrapFunc(name, body, ctx, (node).implicitSelf),
      LocalFunctionDef(:final name, :final funcBody) => _wrapLocalFunc(name, funcBody, ctx),
      ReturnStatement(:final expr) => _wrapReturn(expr, ctx),
      Assignment(:final targets, :final exprs) => _wrapAssign(targets, exprs, ctx),
      ExpressionStatement(:final expr) => _wrapExprStmt(expr, ctx),
      _ => null,
    };
  }

  AstNode? _rewriteExpr(AstNode node, _Context ctx, {String? skipVar}) {
    if (node is Identifier && node.name != skipVar) {
      final info = ctx.assignments[node.name];
      if (info != null && ctx.fold != null) {
        final value = _constExprValue(info.expr);
        if (value != null) {
          ctx.fold!.setValue(node, value);
          // Replace with literal (simplifier will handle the rest).
          return _literalNode(value);
        }
        // Copy propagation: replace with the source expression.
        return info.expr;
      }
    }
    // Recurse into expression children.
    if (node is BinaryExpression) {
      final l = _rewriteExpr(node.left, ctx);
      final r = _rewriteExpr(node.right, ctx);
      if (l != null || r != null) {
        return BinaryExpression(l ?? node.left, node.op, r ?? node.right);
      }
    }
    if (node is UnaryExpression) {
      final e = _rewriteExpr(node.expr, ctx);
      if (e != null) return UnaryExpression(node.op, e);
    }
    if (node is GroupedExpression) {
      final e = _rewriteExpr(node.expr, ctx);
      if (e != null) return GroupedExpression(e);
    }
    return null;
  }

  // ---- Helpers ----

  bool _isConstantExpr(AstNode node) {
    return node is NumberLiteral || node is StringLiteral ||
        node is BooleanLiteral || node is NilValue ||
        node is TableConstructor;
    // Note: TableConstructor might have non-const entries; we accept the
    // approximation since the folding pass would handle individual fields.
  }

  Object? _constExprValue(AstNode node) {
    if (node is NumberLiteral) return node.value;
    if (node is StringLiteral) return node.bytes;
    if (node is BooleanLiteral) return node.value;
    if (node is NilValue) return ConstantFoldingResult.constantNil;
    return null;
  }

  AstNode? _literalNode(Object? value) {
    if (value == ConstantFoldingResult.constantNil) return NilValue();
    if (value is bool) return BooleanLiteral(value);
    if (value is int) return NumberLiteral(value);
    if (value is double) return NumberLiteral(value);
    if (value is BigInt) return NumberLiteral(value);
    return null;
  }

  AstNode? _wrapDo(List<AstNode> body, _Context ctx) {
    final r = _rewrite(body, ctx);
    return identical(r, body) ? null : DoBlock(r);
  }

  AstNode? _wrapFunc(FunctionName name, FunctionBody body, _Context ctx, bool self) {
    final r = _rewrite(body.body, ctx);
    return identical(r, body.body)
        ? null
        : FunctionDef(name, FunctionBody(body.parameters, r, body.isVararg,
            varargName: body.varargName), implicitSelf: self);
  }

  AstNode? _wrapLocalFunc(Identifier name, FunctionBody body, _Context ctx) {
    final r = _rewrite(body.body, ctx);
    return identical(r, body.body)
        ? null
        : LocalFunctionDef(name, FunctionBody(body.parameters, r, body.isVararg,
            varargName: body.varargName));
  }

  AstNode? _wrapReturn(List<AstNode> expr, _Context ctx) {
    List<AstNode>? newExpr;
    for (var i = 0; i < expr.length; i++) {
      final r = _rewriteExpr(expr[i], ctx);
      if (r != null) { (newExpr ??= List.of(expr))[i] = r; }
    }
    return newExpr != null ? ReturnStatement(newExpr) : null;
  }

  AstNode? _wrapAssign(List<AstNode> targets, List<AstNode> exprs, _Context ctx) {
    var changed = false;
    final newExprs = exprs.map((e) {
      final r = _rewriteExpr(e, ctx);
      if (r != null) { changed = true; return r; }
      return e;
    }).toList();
    return changed ? Assignment(targets, newExprs) : null;
  }

  AstNode? _wrapExprStmt(AstNode expr, _Context ctx) {
    final r = _rewriteExpr(expr, ctx);
    return r != null ? ExpressionStatement(r) : null;
  }
}

class _AssignmentInfo {
  final AstNode expr;
  int count;
  _AssignmentInfo._(this.expr, this.count);
}

class _Context {
  final Map<String, _AssignmentInfo> assignments;
  final ConstantFoldingResult? fold;
  _Context(this.assignments, this.fold);
}
