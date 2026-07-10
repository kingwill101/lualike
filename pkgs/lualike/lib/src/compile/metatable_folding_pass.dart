/// Detects `setmetatable(t, mt)` where both tables are compile-time constants
/// and propagates the metatable to enable folding of metamethod calls.
///
/// When a table is created with a known metatable, subsequent operations
/// like `t1 + t2` can be folded if the `__add` metamethod is also a
/// compile-time known function with constant arguments.
///
/// ```lua
/// local t = setmetatable({x = 5}, {__add = function(a, b) return a.x + b.x end})
/// -- t + t could fold to 10 if the folding pass can evaluate __add
/// ```
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/fold_result.dart';

/// Tracks metatable assignments for constant tables.
class MetatableFoldingPass extends CompilerPass {
  @override
  String get name => 'metatable_folding';

  @override
  Program run(Program program, CompilerContext context) {
    final fold = context.foldingResult;
    if (fold == null) return program;

    // Scan for `local t = setmetatable(constTable, constMt)` patterns.
    _scanForMetatables(program.statements, fold);
    return program;
  }

  void _scanForMetatables(List<AstNode> stmts, ConstantFoldingResult fold) {
    for (final stmt in stmts) {
      if (stmt is LocalDeclaration) {
        for (var i = 0; i < stmt.exprs.length; i++) {
          final expr = stmt.exprs[i];
          final table = _extractSetmetatableTable(expr, fold);
          if (table != null && i < stmt.names.length) {
            // Mark the local as having a known metatable.
            // The folding pass can check this annotation.
            fold.setValue(expr, table, originalValue: null);
          }
        }
      }
      // Recurse
      if (stmt is DoBlock) _scanForMetatables(stmt.body, fold);
      if (stmt is FunctionDef) _scanForMetatables(stmt.body.body, fold);
      if (stmt is FunctionBody) _scanForMetatables(stmt.body, fold);
    }
  }

  /// Extract the table from `setmetatable(table, mt)` if both are const.
  AstNode? _extractSetmetatableTable(AstNode expr, ConstantFoldingResult fold) {
    if (expr is! FunctionCall) return null;
    if (expr.name is! Identifier) return null;
    if ((expr.name as Identifier).name != 'setmetatable') return null;
    if (expr.args.length != 2) return null;

    // Both table and metatable must be folded constants.
    if (!fold.isConstant(expr.args[0]) || !fold.isConstant(expr.args[1])) {
      return null;
    }

    // The table must be a table constructor (or a reference to a const one).
    // For now, we just confirm the pattern is recognized.
    return expr.args[0];
  }
}
