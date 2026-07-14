/// Reserved pass boundary for future metatable-aware constant folding.
///
/// This pass intentionally performs no annotations or rewrites. Tables and
/// metatables are mutable, identity-bearing values, `setmetatable` can be
/// shadowed, and metamethod lookup is observable at the time of each operation.
/// Treating the arguments to `setmetatable` as constants is therefore not
/// enough to fold either the call or later operations safely.
///
/// The configuration flag remains available for API compatibility while a
/// sound alias, mutation, identity, and environment model is developed.
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';

/// Preserves the extension point for metatable-aware folding without changing
/// program semantics.
class MetatableFoldingPass extends CompilerPass {
  @override
  String get name => 'metatable_folding';

  @override
  Program run(Program program, CompilerContext context) {
    // Do not annotate setmetatable calls as constants. The call may resolve to
    // a shadowed binding, and both returned table identity and future metatable
    // mutations are observable.
    return program;
  }
}
