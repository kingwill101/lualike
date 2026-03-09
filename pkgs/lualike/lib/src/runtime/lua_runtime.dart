import 'dart:async';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/stdlib/library.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/value.dart';

/// Result of loading a chunk through the active runtime engine.
class LuaChunkLoadResult {
  const LuaChunkLoadResult.success(this.chunk) : errorMessage = null;

  const LuaChunkLoadResult.failure(this.errorMessage) : chunk = null;

  final Value? chunk;
  final String? errorMessage;

  bool get isSuccess => chunk != null;
}

/// Request for loading source or binary chunk input through the active engine.
class LuaChunkLoadRequest {
  const LuaChunkLoadRequest({
    required this.source,
    required this.chunkName,
    this.mode = 'bt',
    this.environment,
  });

  final Value source;
  final String chunkName;
  final String mode;
  final Value? environment;
}

/// Engine-neutral callable artifact marker for compiled runtime closures.
abstract interface class LuaCallableArtifact {
  LuaFunctionDebugInfo? get debugInfo;
}

/// Function metadata that debug helpers can consume without engine-specific casts.
class LuaFunctionDebugInfo {
  const LuaFunctionDebugInfo({
    required this.source,
    required this.shortSource,
    this.what = 'Lua',
    this.lineDefined = -1,
    this.lastLineDefined = -1,
    this.nups = 0,
    this.nparams = 0,
    this.isVararg = true,
  });

  final String source;
  final String shortSource;
  final String what;
  final int lineDefined;
  final int lastLineDefined;
  final int nups;
  final int nparams;
  final bool isVararg;
}

/// Shared runtime capabilities required by stdlib, lualike IR VM, and the AST interpreter.
///
/// This interface will be implemented by both execution engines, allowing shared
/// components (stdlib, values, GC helpers) to interact without depending on a
/// concrete interpreter implementation.
abstract interface class LuaRuntime {
  // Environment & globals
  Environment get globals;
  Environment getCurrentEnv();
  void setCurrentEnv(Environment env);

  // Execution & invocation
  Future<Object?> runAst(List<AstNode> program);
  Future<Object?> callFunction(
    Value function,
    List<Object?> args, {
    String? debugName,
    String debugNameWhat = '',
  });
  Future<Object?> evaluateAst(AstNode node);
  Future<LuaChunkLoadResult> loadChunk(LuaChunkLoadRequest request);
  Object? dumpFunction(Value function, {bool stripDebugInfo = false});
  LuaFunctionDebugInfo? debugInfoForFunction(Value function);
  Value constantStringValue(List<int> bytes);

  // Call stack & debugging
  CallStack get callStack;
  Stack get evalStack;
  Value get debugRegistry;
  String? get currentScriptPath;
  set currentScriptPath(String? value);

  // Coroutine lifecycle
  Coroutine? getCurrentCoroutine();
  void setCurrentCoroutine(Coroutine? coroutine);
  Coroutine getMainThread();
  void registerCoroutine(Coroutine coroutine);
  void unregisterCoroutine(Coroutine coroutine);

  // Protected calls & yieldability
  void enterProtectedCall();
  void exitProtectedCall();
  bool get isInProtectedCall;
  bool get isYieldable;
  set isYieldable(bool value);

  // Garbage collection
  GenerationalGCManager get gc;
  List<Object?> getRoots();
  bool get shouldAbandonIncrementalCycleBeforeManualCollect;

  // IO / modules
  FileManager get fileManager;
  LibraryRegistry get libraryRegistry;

  // Diagnostics
  void reportError(
    String message, {
    StackTrace? trace,
    Object? error,
    AstNode? node,
  });
}
