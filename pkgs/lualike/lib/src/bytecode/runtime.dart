import 'package:lualike/src/ast.dart';
import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/disassembler.dart';
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/library.dart';
import 'package:lualike/src/value.dart';

/// Runtime wrapper that executes code via the bytecode VM while satisfying
/// the [LuaRuntime] contract expected by higher-level tooling.
class BytecodeRuntime implements LuaRuntime {
  BytecodeRuntime({FileManager? fileManager})
    : _interpreter = Interpreter(fileManager: fileManager) {
    _ensureEnvironmentBinding(_interpreter.globals);
    _interpreter.fileManager.setInterpreter(this);
  }

  final Interpreter _interpreter;

  Environment get _globals => _interpreter.globals;

  @override
  Environment get globals {
    final env = _globals;
    _ensureEnvironmentBinding(env);
    return env;
  }

  @override
  Environment getCurrentEnv() {
    final env = _interpreter.getCurrentEnv();
    _ensureEnvironmentBinding(env);
    return env;
  }

  @override
  void setCurrentEnv(Environment env) {
    _ensureEnvironmentBinding(env);
    _interpreter.setCurrentEnv(env);
  }

  @override
  Future<Object?> runAst(List<AstNode> program) async {
    final chunk = BytecodeCompiler().compile(Program(program));
    if (LuaLikeConfig().dumpBytecode) {
      final disassembly = disassembleChunk(chunk);
      if (disassembly.isNotEmpty) {
        // Use print so output is visible even when logging is disabled.
        print('--- Bytecode Disassembly ---');
        print(disassembly);
        print('--- End Disassembly ---');
      }
    }
    final env = _interpreter.getCurrentEnv();
    _ensureEnvironmentBinding(env);
    final vm = BytecodeVm(environment: env, runtime: this);
    return vm.execute(chunk);
  }

  @override
  Future<Object?> evaluateAst(AstNode node) {
    final returnStatement = node is ReturnStatement
        ? node
        : ReturnStatement([node]);
    return runAst([returnStatement]);
  }

  @override
  Future<Object?> callFunction(Value function, List<Object?> args) async {
    final callee = _resolveCallable(function);
    _ensureValueInterpreter(callee);
    _attachInterpreterToArgs(args);

    final raw = callee.raw;
    if (raw is BytecodeClosure) {
      final env = _interpreter.getCurrentEnv();
      _ensureEnvironmentBinding(env);
      final vm = BytecodeVm(environment: env, runtime: this);
      return vm.invokeClosure(raw, args);
    }

    return callee.call(args);
  }

  @override
  CallStack get callStack => _interpreter.callStack;

  @override
  Stack get evalStack => _interpreter.evalStack;

  @override
  String? get currentScriptPath => _interpreter.currentScriptPath;

  @override
  set currentScriptPath(String? value) {
    _interpreter.currentScriptPath = value;
  }

  @override
  Coroutine? getCurrentCoroutine() => _interpreter.getCurrentCoroutine();

  @override
  void setCurrentCoroutine(Coroutine? coroutine) {
    _interpreter.setCurrentCoroutine(coroutine);
  }

  @override
  Coroutine getMainThread() => _interpreter.getMainThread();

  @override
  void registerCoroutine(Coroutine coroutine) {
    _interpreter.registerCoroutine(coroutine);
  }

  @override
  void unregisterCoroutine(Coroutine coroutine) {
    _interpreter.unregisterCoroutine(coroutine);
  }

  @override
  void enterProtectedCall() => _interpreter.enterProtectedCall();

  @override
  void exitProtectedCall() => _interpreter.exitProtectedCall();

  @override
  bool get isInProtectedCall => _interpreter.isInProtectedCall;

  @override
  bool get isYieldable => _interpreter.isYieldable;

  @override
  set isYieldable(bool value) {
    _interpreter.isYieldable = value;
  }

  @override
  GenerationalGCManager get gc => _interpreter.gc;

  @override
  List<Object?> getRoots() => _interpreter.getRoots();

  @override
  FileManager get fileManager => _interpreter.fileManager;

  @override
  LibraryRegistry get libraryRegistry => _interpreter.libraryRegistry;

  @override
  void reportError(
    String message, {
    StackTrace? trace,
    Object? error,
    AstNode? node,
  }) {
    _interpreter.reportError(message, trace: trace, error: error, node: node);
  }

  void _ensureEnvironmentBinding(Environment env) {
    final root = env.root;
    if (!identical(root.interpreter, this)) {
      root.interpreter = this;
    }
  }

  Value _resolveCallable(Value original) {
    var callee = original;
    final raw = callee.raw;
    if (raw is String) {
      final lookup = globals.get(raw);
      if (lookup != null) {
        callee = lookup is Value ? lookup : Value(lookup);
      }
    }
    return callee;
  }

  void _ensureValueInterpreter(Value value) {
    if (!identical(value.interpreter, this)) {
      value.interpreter = this;
    }
  }

  void _attachInterpreterToArgs(List<Object?> args) {
    for (var i = 0; i < args.length; i++) {
      final candidate = args[i];
      if (candidate is Value && !identical(candidate.interpreter, this)) {
        candidate.interpreter = this;
      }
    }
  }
}
