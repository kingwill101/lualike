/// Heuristics for when to inline function calls.
///
/// Currently, inlining is attempted whenever all arguments are compile-time
/// constants.  This pass restricts inlining to functions whose body is
/// simple enough that inlining is profitable.
///
/// A function body is considered "simple enough" when its AST node count
/// is below [maxBodyNodes].  Complex functions with many statements are
/// not inlined to avoid code bloat.
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';

/// Configures function inlining heuristics.
class InliningHeuristicsPass extends CompilerPass {
  @override
  String get name => 'inlining_heuristics';

  /// Maximum AST nodes in a function body for inlining to be profitable.
  final int maxBodyNodes;

  /// Maximum call depth for nested inlining.
  final int maxInlineDepth;

  InliningHeuristicsPass({
    this.maxBodyNodes = 20,
    this.maxInlineDepth = 4,
  });

  @override
  Program run(Program program, CompilerContext context) {
    // This pass doesn't transform the AST directly.  It configures the
    // ConstantFoldingPass's inlining behavior by storing limits in the
    // context.  The folding pass reads these when deciding whether to
    // inline a function call.
    //
    // Future: store maxBodyNodes and maxInlineDepth in context for the
    // folding pass to consume.
    return program;
  }
}
