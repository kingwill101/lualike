/// Common interface for compiler passes in the lualike pipeline.
///
/// Each pass transforms a [Program] AST.  Passes are composed in the
/// [CompilePipeline] and run sequentially.  A pass can carry its own
/// configuration and produce side-channel data (like folding results)
/// that downstream passes access through [CompilerContext].
///
/// To add a new pass:
/// ```dart
/// class MyPass extends CompilerPass {
///   @override
///   String get name => 'my_pass';
///
///   @override
///   Program run(Program program, CompilerContext context) {
///     // transform program...
///     return program;
///   }
/// }
/// ```
library;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/fold_result.dart';

/// Shared context passed through the compilation pipeline.
///
/// Passes can store and retrieve data here instead of communicating
/// through side-channels.  The [foldingResult] is the primary example:
/// the fold pass writes it, the simplifier pass reads it.
class CompilerContext {
  /// The current program being compiled.
  Program program;

  /// Folding result, populated by the fold pass and consumed by simplifier.
  ConstantFoldingResult? foldingResult;

  CompilerContext(this.program);
}

/// Base class for a single compilation pass.
///
/// Subclasses override [run] to transform the AST.  A pass can also
/// store data in [context] for downstream passes to consume.
abstract class CompilerPass {
  /// A short, kebab-case name for this pass (e.g. `"constant_folding"`).
  String get name;

  /// Applies this pass to [context.program] and returns the result.
  ///
  /// The default implementation calls [run] and updates [context.program].
  /// Override if the pass needs multiple steps or conditional execution.
  Program run(Program program, CompilerContext context);
}
