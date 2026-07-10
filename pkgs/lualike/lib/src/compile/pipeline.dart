import 'package:lualike/src/ast.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
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

  /// Target backend for bytecode emission.
  final CompileBackend target;

  const CompilePipelineConfig({
    this.stripDebug = false,
    this.dumpIr = false,
    this.enableConstantFolding = true,
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
/// Different backends produce different artifact types, but all carry the
/// [foldingResult] so callers can inspect which expressions were folded.
sealed class CompileArtifact {
  /// The constant folding result (empty if folding was disabled).
  ConstantFoldingResult get foldingResult;

  /// The serialized bytecode bytes ready for distribution or loading.
  List<int> get serializedBytes;
}

/// A lualike IR chunk produced by [CompilePipeline].
final class LualikeIrArtifact extends CompileArtifact {
  /// The parsed and compiled IR chunk.
  final LualikeIrChunk chunk;

  @override
  final List<int> serializedBytes;

  @override
  final ConstantFoldingResult foldingResult;

  /// Human-readable disassembly, if [CompilePipelineConfig.dumpIr] was set.
  final String? disassembly;

  LualikeIrArtifact({
    required this.chunk,
    required this.serializedBytes,
    required this.foldingResult,
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

  @override
  final ConstantFoldingResult foldingResult;

  LuaBytecodeArtifact({
    required this.chunk,
    required this.serializedBytes,
    required this.facts,
    required this.foldingResult,
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
  late final ConstantFoldingResult _foldingResult;

  CompilePipeline({CompilePipelineConfig? config})
    : config = config ?? const CompilePipelineConfig();

  /// The constant folding result from the last [compile] call.
  ConstantFoldingResult get foldingResult => _foldingResult;

  /// Compile a [Program] AST node through the full pipeline.
  ///
  /// Returns the compilation artifact for the target backend.
  CompileArtifact compile(Program program) {
    // Phase 1: Constant folding (if enabled)
    _foldingResult = ConstantFoldingResult();
    if (config.enableConstantFolding) {
      final foldingPass = ConstantFoldingPass();
      foldingPass.fold(program);
      _foldingResult.merge(foldingPass.result);
    }

    // Phase 2: Compile to IR (consumes folding results)
    final irCompiler = LualikeIrCompiler(
      foldingResult: config.enableConstantFolding ? _foldingResult : null,
    );
    final irChunk = irCompiler.compile(program);
    final irBytes = serializeLualikeIrChunk(irChunk);

    String? disassembly;
    if (config.dumpIr) {
      disassembly = formatLualikeIrChunk(irChunk);
    }

    // Phase 3: Optionally lower to Lua 5.4 bytecode
    if (config.target == CompileBackend.luaBytecode) {
      final luaChunk = _lowerToLuaBytecode(program);
      final luaBytes = serializeLuaBytecodeChunk(luaChunk);

      return LuaBytecodeArtifact(
        chunk: luaChunk,
        serializedBytes: luaBytes,
        facts: LuaBytecodeEmitterFacts(
          locals: const [],
          nextRegister: luaChunk.mainPrototype.maxStackSize,
          hasExplicitReturn: true,
        ),
        foldingResult: _foldingResult,
      );
    }

    return LualikeIrArtifact(
      chunk: irChunk,
      serializedBytes: irBytes,
      foldingResult: _foldingResult,
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
    final emitter = LuaBytecodeEmitter(
      foldingResult: config.enableConstantFolding ? _foldingResult : null,
    );

    final artifact = emitter.compileProgram(program);
    return artifact.chunk;
  }
}

/// Extension to make [ConstantFoldingResult] values accessible.
extension ConstantFoldingUtils on ConstantFoldingResult {
  /// Returns `true` if this node was folded to a compile-time constant.
  bool isFolded(AstNode node) => isConstant(node);

  /// Returns the folded value for [node], or `null` if not constant.
  Object? foldedValue(AstNode node) => getValue(node);
}
