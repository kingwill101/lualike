import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/bundler.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/const_propagation_pass.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/compile/dead_code_pass.dart';
import 'package:lualike/src/compile/inlining_heuristics_pass.dart';
import 'package:lualike/src/compile/analyzer_pass.dart';
import 'package:lualike/src/compile/metatable_folding_pass.dart';
import 'package:lualike/src/compile/simplify_pass.dart';
import 'package:lualike/src/compile/type_narrowing_pass.dart';
import 'package:lualike/ir.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/peephole_pass.dart' as lua_bc;
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:lualike/src/ir/ssa_dead_code_pass.dart';
import 'package:lualike/src/ir/ssa_gvn_pass.dart';
import 'package:lualike/src/ir/ssa_coalesce_pass.dart';
import 'package:lualike/src/ir/inline_pass.dart';
import 'package:lualike/src/ir/ssa_licm_pass.dart';
import 'package:lualike/src/ir/ssa_escape_pass.dart';
import 'package:lualike/src/ir/ssa_sccp_pass.dart';
import 'package:lualike/src/parse.dart';

/// Configuration for the compilation pipeline.
///
/// Controls which passes are enabled, what output format to produce, and
/// whether debug information is included.
final class CompilePipelineConfig {
  /// Whether to omit debug line information from the bytecode.
  ///
  /// When `true`, the resulting bytecode is smaller but stack traces will not
  /// include source line numbers.
  final bool stripDebug;

  /// Whether to print the IR instruction dump to stderr.
  final bool dumpIr;

  /// Whether to run the analyzer pass (type inference for locals).
  final bool enableAnalyzer;

  /// Whether to run the [ConstantFoldingPass] before IR emission.
  final bool enableConstantFolding;

  /// Whether to run constant propagation (single-assignment locals).
  final bool enableConstPropagation;

  /// Whether to narrow types through `type()` equality checks.
  final bool enableTypeNarrowing;

  /// Whether to fold table operations with known metatables.
  final bool enableMetatableFolding;

  /// Whether to run peephole optimization on IR bytecode.
  final bool enablePeephole;

  /// Whether to run SSA-based dead code elimination on the IR.
  final bool enableSsaDeadCodeElimination;

  /// Whether to run SSA Global Value Numbering on the IR.
  final bool enableSsaGlobalValueNumbering;

  /// Whether to run Sparse Conditional Constant Propagation on the IR.
  final bool enableSsaSccp;

  /// Whether to run Loop Invariant Code Motion on the IR.
  final bool enableSsaLicm;

  /// Whether to run Register Coalescing on the IR.
  final bool enableSsaCoalesce;

  /// Whether to run Escape Analysis + Scalar Replacement on the IR.
  final bool enableSsaEscape;

  /// Whether to run Function Inlining on the IR.
  final bool enableFunctionInlining;

  /// Whether to unroll constant-bounded for-loops in the IR compiler.
  final bool enableLoopUnrolling;

  /// Whether to run the bundler pass (require() resolution).
  final bool enableBundling;

  /// Search paths for the bundler when resolving `require("path")`.
  final List<String> bundleSearchPaths;

  /// Whether to tree-shake unused module exports after bundling.
  final bool enableDeadCodeElimination;

  /// Target backend for bytecode emission.
  final CompileBackend target;

  const CompilePipelineConfig({
    this.stripDebug = false,
    this.dumpIr = false,
    // All optimizations are OFF by default.  Only enabled during
    // --compile which produces a bytecode binary for distribution.
    // For interactive/script mode, startup speed matters more than
    // the marginal runtime gain from these passes.
    this.enableAnalyzer = false,
    this.enableConstantFolding = false,
    this.enableConstPropagation = false,
    this.enableTypeNarrowing = false,
    this.enableMetatableFolding = false,
    this.enablePeephole = false,
    this.enableSsaDeadCodeElimination = false,
    this.enableSsaGlobalValueNumbering = false,
    this.enableSsaSccp = false,
    this.enableSsaLicm = false,
    this.enableSsaCoalesce = false,
    this.enableSsaEscape = false,
    this.enableFunctionInlining = false,
    this.enableLoopUnrolling = false,
    this.enableBundling = false,
    this.bundleSearchPaths = const ['.'],
    this.enableDeadCodeElimination = false,
    this.target = CompileBackend.luaBytecode,
  });
}

/// Which bytecode backend to target.
enum CompileBackend {
  /// Lua 5.4 compatible bytecode.
  luaBytecode,

  /// Lualike custom IR format.
  lualikeIR,
}

/// Result of running the compilation pipeline.
///
/// The AST has already been simplified by the constant folding pass before
/// reaching the compiler backends, so callers can trust the bytecode
/// incorporates all folding optimizations.
sealed class CompileArtifact {
  /// The serialized bytecode bytes ready for distribution or loading.
  List<int> get serializedBytes;
}

/// A lualike IR chunk produced by [CompilePipeline].
final class LualikeIrArtifact extends CompileArtifact {
  /// The parsed and compiled IR chunk.
  final LualikeIrChunk chunk;

  @override
  final List<int> serializedBytes;

  /// Human-readable disassembly, if [CompilePipelineConfig.dumpIr] was set.
  final String? disassembly;

  /// Human-readable SSA dump, if [CompilePipelineConfig.dumpIr] was set.
  final String? ssaDisassembly;

  LualikeIrArtifact({
    required this.chunk,
    required this.serializedBytes,
    this.disassembly,
    this.ssaDisassembly,
  });
}

/// A Lua 5.4 binary chunk produced by [CompilePipeline].
final class LuaBytecodeArtifact extends CompileArtifact {
  /// The compiled Lua 5.4 chunk.
  final LuaBytecodeBinaryChunk chunk;

  @override
  final List<int> serializedBytes;

  /// Emitter-level facts such as register usage.
  final LuaBytecodeEmitterFacts facts;

  LuaBytecodeArtifact({
    required this.chunk,
    required this.serializedBytes,
    required this.facts,
  });
}

/// Multi-pass compilation pipeline that transforms Lua source into bytecode.
///
/// Orchestrates the compilation passes in this order:
///
/// ```
/// Source → Parser → [ConstantFoldingPass]
///                     → [LualikeIrCompiler]  (IR artifact)
///                       → [LuaBytecodeEmitter] (Lua 5.4 artifact)
/// ```
///
/// Each pass consumes the results of the previous pass. The constant folding
/// pass annotates nodes with precomputed values; the IR compiler and Lua
/// bytecode emitter then use those annotations to emit `LOADK` / `LOADI`
/// instructions instead of lowering the full expression tree.
///
/// {@category Compiler}
///
/// ## Usage
///
/// ```dart
/// final pipeline = CompilePipeline(
///   config: CompilePipelineConfig(
///     enableConstantFolding: true,
///     target: CompileBackend.lualikeIR,
///   ),
/// );
/// final artifact = pipeline.compileSource('return 2 + 3 * 4 - 1');
/// print('Instructions: '
///   '${(artifact as LualikeIrArtifact).chunk.mainPrototype.instructions.length}');
/// // → Instructions: 3  (loadK 13, return, plus vararg prep)
/// ```
final class CompilePipeline {
  /// Configuration for this pipeline instance.
  final CompilePipelineConfig config;

  CompilePipeline({CompilePipelineConfig? config})
    : config = config ?? const CompilePipelineConfig();

  /// Builds the list of compiler passes based on configuration.
  List<CompilerPass> _buildPassList() {
    return [
      // Bundle phase: resolve require() calls
      if (config.enableBundling) Bundler(searchPaths: config.bundleSearchPaths),
      // Propagation phase: forward constants and copies
      if (config.enableConstPropagation) ConstPropagationPass(),
      // Type narrowing: track types through type() checks
      if (config.enableAnalyzer) AnalyzerPass(),
      if (config.enableTypeNarrowing) TypeNarrowingPass(),
      // Metatable-aware folding
      if (config.enableMetatableFolding) MetatableFoldingPass(),
      // Inlining heuristics: configure when inlining is profitable
      if (config.enableConstantFolding) InliningHeuristicsPass(),
      // Folding phase: analyze and simplify constant expressions
      if (config.enableConstantFolding) ConstantFoldingPass(),
      if (config.enableConstantFolding) ASTSimplifier(),
      // Dead code elimination: tree-shake unused module exports
      if (config.enableDeadCodeElimination) DeadCodeEliminationPass(),
    ];
  }

  /// Compile a [Program] AST node through the full pipeline.
  ///
  /// Returns the compilation artifact for the target backend.
  CompileArtifact compile(Program program) {
    // Phase 1: Run all AST passes in sequence
    final context = CompilerContext(program);
    for (final pass in _buildPassList()) {
      context.program = pass.run(context.program, context);
    }
    final foldedProgram = context.program;

    // Phase 2: Compile simplified AST to IR
    final irCompiler = LualikeIrCompiler(
      enableLoopUnrolling: config.target == CompileBackend.luaBytecode
          ? config.enableLoopUnrolling
          : false,
    );
    var irChunk = irCompiler.compile(foldedProgram);

    // Peephole optimization on IR (post-emission)
    if (config.enablePeephole) {
      irChunk = PeepholePass().optimize(irChunk);
    }

    // SSA-based dead code elimination on IR
    if (config.enableSsaDeadCodeElimination) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: eliminateDeadCode(irChunk.mainPrototype),
      );
    }

    if (config.enableSsaGlobalValueNumbering) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: eliminateRedundantComputations(irChunk.mainPrototype),
      );
    }

    if (config.enableSsaSccp) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: runSccp(irChunk.mainPrototype),
      );
    }

    if (config.enableSsaLicm) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: hoistLoopInvariants(irChunk.mainPrototype),
      );
    }

    if (config.enableSsaCoalesce) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: coalesceRegisters(irChunk.mainPrototype),
      );
    }

    if (config.enableSsaEscape) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: replaceScalars(irChunk.mainPrototype),
      );
    }

    if (config.enableFunctionInlining) {
      irChunk = LualikeIrChunk(
        flags: irChunk.flags,
        mainPrototype: inlineFunctions(irChunk.mainPrototype),
      );
    }

    final irBytes = serializeLualikeIrChunk(irChunk);

    String? disassembly;
    String? ssaDisassembly;
    if (config.dumpIr) {
      disassembly = formatLualikeIrChunk(irChunk);
      final ssa = buildLualikeIrSsaFunction(irChunk.mainPrototype);
      ssaDisassembly = formatLualikeIrSsaFunction(ssa);
    }

    // Phase 3: Optionally lower to Lua 5.4 bytecode
    if (config.target == CompileBackend.luaBytecode) {
      var luaChunk = _lowerToLuaBytecode(foldedProgram);

      // Peephole optimization on Lua bytecode (post-emission)
      if (config.enablePeephole) {
        luaChunk = lua_bc.LuaBytecodePeepholePass().optimize(luaChunk);
      }

      final luaBytes = serializeLuaBytecodeChunk(
        luaChunk,
        stripDebug: config.stripDebug,
      );

      return LuaBytecodeArtifact(
        chunk: luaChunk,
        serializedBytes: luaBytes,
        facts: LuaBytecodeEmitterFacts(
          locals: const [],
          nextRegister: luaChunk.mainPrototype.maxStackSize,
          hasExplicitReturn: true,
        ),
      );
    }

    return LualikeIrArtifact(
      chunk: irChunk,
      serializedBytes: irBytes,
      disassembly: disassembly,
      ssaDisassembly: ssaDisassembly,
    );
  }

  /// Convenience: parse source, run the pipeline, return the artifact.
  CompileArtifact compileSource(
    String source, {
    String chunkName = '=(compile pipeline)',
  }) {
    final program = parse(source, url: chunkName);
    return compile(program);
  }

  /// Lower to Lua 5.4 bytecode using the existing Lua bytecode emitter.
  LuaBytecodeBinaryChunk _lowerToLuaBytecode(Program program) {
    const emitter = LuaBytecodeEmitter();
    final artifact = emitter.compileProgram(program);
    return artifact.chunk;
  }
}
