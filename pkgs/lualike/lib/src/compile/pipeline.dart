import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/compile/simplify_pass.dart';
import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/serialization.dart';
import 'package:lualike/src/ir/textual_formatter.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
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

  /// Whether to run the [ConstantFoldingPass] before IR emission.
  final bool enableConstantFolding;

  /// Whether to unroll constant-bounded for-loops in the IR compiler.
  ///
  /// Unrolling increases instruction count (bad for interpreters) but produces
  /// tighter bytecode that runs faster in the bytecode VM.  Enable when
  /// producing a compiled binary; disable for IR interpreter runs.
  final bool enableLoopUnrolling;

  /// Target backend for bytecode emission.
  final CompileBackend target;

  const CompilePipelineConfig({
    this.stripDebug = false,
    this.dumpIr = false,
    this.enableConstantFolding = true,
    // Loop unrolling is off by default.  For most loops the generated code
    // bloat outweighs the saved forPrep/forLoop overhead, even on the
    // bytecode VM.  Set explicitly when a specific loop benefits.
    this.enableLoopUnrolling = false,
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

  LualikeIrArtifact({
    required this.chunk,
    required this.serializedBytes,
    this.disassembly,
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
      if (config.enableConstantFolding) ConstantFoldingPass(),
      if (config.enableConstantFolding) ASTSimplifier(),
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
    final irChunk = irCompiler.compile(foldedProgram);
    final irBytes = serializeLualikeIrChunk(irChunk);

    String? disassembly;
    if (config.dumpIr) {
      disassembly = formatLualikeIrChunk(irChunk);
    }

    // Phase 3: Optionally lower to Lua 5.4 bytecode
    if (config.target == CompileBackend.luaBytecode) {
      final luaChunk = _lowerToLuaBytecode(foldedProgram);
      final luaBytes = serializeLuaBytecodeChunk(luaChunk);

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
