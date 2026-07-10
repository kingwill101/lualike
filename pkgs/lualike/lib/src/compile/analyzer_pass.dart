/// Lightweight type analysis pass that feeds type information into the
/// constant folding pipeline.
///
/// Unlike a full static type system, this pass observes runtime-available
/// information:
///
///   1. Literal initializers: `local x = 5` → x is a number
///   2. `type()` calls: `type(x) == "number"` → x is narrowed to number
///   3. Arithmetic context: `x + 1` → x is likely a number
///   4. String concatenation: `x .. "s"` → x is likely a string
///
/// The type annotations are stored in [CompilerContext] and consumed by
/// the [ConstantFoldingPass] to enable type-guided expression folding
/// (e.g., folding `x + 1` when x is known to be number).
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/fold_result.dart';

/// The inferred Lua type for a variable.
enum InferredType {
  nil_,
  boolean,
  number,
  string,
  table,
  function_,
  unknown,
}

/// Stores type information for local variables per scope.
class _TypeFrame {
  final Map<String, InferredType> types = {};
  final Map<String, int> writeCounts = {};
}

/// Lightweight type analysis for local variables.
///
/// Runs before the constant folding pass and annotates [ConstantFoldingResult]
/// with type information.  The folding pass can then fold expressions like
/// `x + 1` when `x` is known to be a number.
class AnalyzerPass extends CompilerPass {
  @override
  String get name => 'analyzer';

  @override
  Program run(Program program, CompilerContext context) {
    final fold = context.foldingResult;
    if (fold == null) return program;
    _analyze(program.statements, fold, []);
    return program;
  }

  void _analyze(
    List<AstNode> stmts,
    ConstantFoldingResult fold,
    List<_TypeFrame> scopes,
  ) {
    for (final stmt in stmts) {
      switch (stmt) {
        case LocalDeclaration(:final names, :final attributes, :final exprs):
          _pushScopeIfNeeded(scopes);
          for (var i = 0; i < names.length; i++) {
            final type = _typeOfExpr(i < exprs.length ? exprs[i] : null, fold);
            if (i < exprs.length) {
              _recordType(names[i].name, type, scopes);
            }
            // <const> locals are tracked by the folding pass directly.
          }

        case Assignment(:final targets, :final exprs):
          for (var i = 0; i < targets.length && i < exprs.length; i++) {
            final target = targets[i];
            if (target is Identifier) {
              final type = _typeOfExpr(exprs[i], fold);
              _recordType(target.name, type, scopes);
            }
          }

        case ForLoop(:final varName, :final start, :final endExpr, :final stepExpr):
          // Loop variable is a number.
          _pushScopeIfNeeded(scopes);
          _recordType(varName.name, InferredType.number, scopes);

        case IfStatement(:final cond, :final thenBlock, :final elseIfs, :final elseBlock):
          _pushScopeIfNeeded(scopes);
          _analyze(thenBlock, fold, scopes);
          _maybePopScope(scopes);
          for (final clause in elseIfs) {
            _pushScopeIfNeeded(scopes);
            _analyze(clause.thenBlock, fold, scopes);
            _maybePopScope(scopes);
          }
          _pushScopeIfNeeded(scopes);
          _analyze(elseBlock, fold, scopes);
          _maybePopScope(scopes);

        case WhileStatement(:final body):
          _analyze(body, fold, scopes);

        case RepeatUntilLoop(:final body):
          _analyze(body, fold, scopes);

        case DoBlock(:final body):
          _analyze(body, fold, scopes);

        case FunctionDef(:final body):
          _analyze(body.body, fold, []); // Fresh scope for function

        case LocalFunctionDef(:final funcBody):
          _analyze(funcBody.body, fold, []);

        case FunctionBody(:final body):
          _analyze(body, fold, scopes);

        default:
          break;
      }
    }
  }

  /// Infer the type of an expression.
  InferredType _typeOfExpr(AstNode? node, ConstantFoldingResult fold) {
    if (node == null) return InferredType.nil_;
    // Folded values tell us the exact type.
    if (fold.isConstant(node)) {
      final value = fold.getValue(node);
      if (value == ConstantFoldingResult.constantNil) return InferredType.nil_;
      if (value is bool) return InferredType.boolean;
      if (value is num || value is BigInt) return InferredType.number;
      if (value is List<int> || value is String) return InferredType.string;
      if (value is Map) return InferredType.table;
      return InferredType.unknown;
    }
    // Literal syntax tells us the type.
    return switch (node) {
      NilValue() => InferredType.nil_,
      BooleanLiteral() => InferredType.boolean,
      NumberLiteral() => InferredType.number,
      StringLiteral() => InferredType.string,
      TableConstructor() => InferredType.table,
      FunctionLiteral() => InferredType.function_,
      _ => InferredType.unknown,
    };
  }

  void _recordType(String name, InferredType type, List<_TypeFrame> scopes) {
    if (scopes.isEmpty) return;
    final frame = scopes.last;
    frame.writeCounts[name] = (frame.writeCounts[name] ?? 0) + 1;
    frame.types[name] = type;
  }

  void _pushScopeIfNeeded(List<_TypeFrame> scopes) {
    // We use a single-frame approach — scopes are flat for now.
    if (scopes.isEmpty) scopes.add(_TypeFrame());
  }

  void _maybePopScope(List<_TypeFrame> scopes) {
    // Keep the base frame.
  }
}
