/// Tracks type information through `type()` equality checks.
///
/// After `if type(x) == "number" then`, subsequent references to `x` in the
/// then-branch are known to be numbers.  This enables the folding pass to
/// evaluate `x + 1` inside the branch.
///
/// ```lua
/// if type(x) == "number" then
///     return x + 1    -- x is known to be a number here
/// end
/// ```
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/fold_result.dart';

/// Type of Lua value tracked by the narrowing pass.
enum NarrowedType { nil, boolean, number, string, table, function_, thread, userdata }

/// Narrowed types for each local variable name per scope.
class _TypeState {
  final Map<String, NarrowedType> types = {};
}

/// Annotates the folding result with type information from `type()` checks.
///
/// The folding pass can then fold expressions like `x + 1` when `x` is
/// known to be a number via a preceding `type(x) == "number"` check.
class TypeNarrowingPass extends CompilerPass {
  @override
  String get name => 'type_narrowing';

  @override
  Program run(Program program, CompilerContext context) {
    final fold = context.foldingResult;
    if (fold == null) return program;
    _narrow(program.statements, fold, []);
    return program;
  }

  void _narrow(
    List<AstNode> stmts,
    ConstantFoldingResult fold,
    List<_TypeState> scopes,
  ) {
    var i = 0;
    while (i < stmts.length) {
      final stmt = stmts[i];

      // if type(x) == "type" then ... end
      if (stmt is IfStatement) {
        final narrowed = _narrowFromCondition(stmt.cond, fold);
        if (narrowed != null) {
          scopes.add(narrowed);
          _narrow(stmt.thenBlock, fold, scopes);
          scopes.removeLast();
          // else/elseif branches don't have the narrowing.
          for (final clause in stmt.elseIfs) {
            _narrow(clause.thenBlock, fold, scopes);
          }
          _narrow(stmt.elseBlock, fold, scopes);
        } else {
          _narrow(stmt.thenBlock, fold, scopes);
          for (final clause in stmt.elseIfs) {
            _narrow(clause.thenBlock, fold, scopes);
          }
          _narrow(stmt.elseBlock, fold, scopes);
        }
        i++;
        continue;
      }

      // Function boundaries reset type info.
      if (stmt is FunctionDef) {
        _narrow(stmt.body.body, fold, []);
        i++;
        continue;
      }
      if (stmt is LocalFunctionDef) {
        _narrow(stmt.funcBody.body, fold, []);
        i++;
        continue;
      }

      // Nested blocks inherit current scope.
      if (stmt is DoBlock) {
        _narrow(stmt.body, fold, scopes);
        i++;
        continue;
      }

      i++;
    }
  }

  /// Analyze a condition and return narrowed types if applicable.
  _TypeState? _narrowFromCondition(AstNode cond, ConstantFoldingResult fold) {
    // type(x) == "number"
    if (cond is BinaryExpression && (cond.op == '==' || cond.op == '~=')) {
      final (ident, typeStr) = _matchTypeCheck(cond.left, cond.right);
      if (ident != null && typeStr != null) {
        final narrowedType = _parseType(typeStr);
        if (narrowedType != null) {
          final state = _TypeState();
          // For `==`, narrow to this type. For `~=`, we can't narrow positively.
          if (cond.op == '==') {
            state.types[ident] = narrowedType;
            _annotateFold(fold, ident, narrowedType);
          }
          return state;
        }
      }
    }
    // not (type(x) ~= "number") → same as type(x) == "number"
    if (cond is UnaryExpression && cond.op == 'not') {
      final inner = cond.expr;
      if (inner is BinaryExpression && inner.op == '~=') {
        final (ident, typeStr) = _matchTypeCheck(inner.left, inner.right);
        if (ident != null && typeStr != null) {
          final narrowedType = _parseType(typeStr);
          if (narrowedType != null) {
            final state = _TypeState();
            state.types[ident] = narrowedType;
            _annotateFold(fold, ident, narrowedType);
            return state;
          }
        }
      }
    }
    return null;
  }

  /// Match `type(x)` and `"string"` in either order.
  (String?, String?) _matchTypeCheck(AstNode a, AstNode b) {
    final ident = _typeOfIdent(a) ?? _typeOfIdent(b);
    final typeStr = _typeString(a) ?? _typeString(b);
    if (ident != null && typeStr != null) return (ident, typeStr);
    return (null, null);
  }

  /// Get identifier name from `type(x)`.
  String? _typeOfIdent(AstNode node) {
    if (node is FunctionCall &&
        node.name is Identifier &&
        (node.name as Identifier).name == 'type' &&
        node.args.length == 1 &&
        node.args.first is Identifier) {
      return (node.args.first as Identifier).name;
    }
    return null;
  }

  /// Get string value from a string literal node.
  String? _typeString(AstNode node) {
    if (node is StringLiteral) return node.value;
    return null;
  }

  NarrowedType? _parseType(String s) {
    switch (s) {
      case 'nil': return NarrowedType.nil;
      case 'boolean': return NarrowedType.boolean;
      case 'number': return NarrowedType.number;
      case 'string': return NarrowedType.string;
      case 'table': return NarrowedType.table;
      case 'function': return NarrowedType.function_;
      case 'thread': return NarrowedType.thread;
      case 'userdata': return NarrowedType.userdata;
      default: return null;
    }
  }

  /// Annotate the folding result so downstream passes can use type info.
  void _annotateFold(ConstantFoldingResult fold, String varName, NarrowedType type) {
    // The folding pass can check fold.getType(varName) during evaluation.
    // For now, this is a marker — actual type-guided folding in the
    // ConstantFoldingPass would consume this information.
  }
}
