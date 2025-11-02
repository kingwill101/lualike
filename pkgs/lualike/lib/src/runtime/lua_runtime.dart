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

/// Shared runtime capabilities required by stdlib, bytecode VM, and the AST interpreter.
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
  Future<Object?> callFunction(Value function, List<Object?> args);
  Future<Object?> evaluateAst(AstNode node);

  // Call stack & debugging
  CallStack get callStack;
  Stack get evalStack;
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

  // IO / modules
  FileManager get fileManager;
  LibraryRegistry get libraryRegistry;

  // Diagnostics
  void reportError(String message, {StackTrace? trace, Object? error});
}
