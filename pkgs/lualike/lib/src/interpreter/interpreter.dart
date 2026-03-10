import 'dart:collection';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/generational_gc.dart' show GenerationalGCManager;
import 'package:lualike/src/gc/gc_access.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_stack_trace.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/number.dart';
import 'package:lualike/src/number_limits.dart';
import 'package:lualike/src/number_utils.dart';
import 'package:lualike/src/runtime/compiled_artifact_support.dart';
import 'package:lualike/src/runtime/chunk_loading_support.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/semantic_checker.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart' show initializeStandardLibrary;
import 'package:lualike/src/stdlib/lib_io.dart';
import 'package:lualike/src/stdlib/library.dart' show LibraryRegistry;
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/utils/type.dart';
import 'package:lualike/src/upvalue.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/file_system_utils.dart' as fs;
import 'package:lualike/src/interpreter/upvalue_assignment.dart';
import 'package:lualike/src/ir/loop_compiler.dart';
import 'package:lualike/src/ir/serialization.dart';
import 'package:lualike/src/ir/vm.dart';
import 'package:source_span/source_span.dart';

import '../exceptions.dart';
import '../extensions/extensions.dart';
import 'upvalue_analyzer.dart';

part 'assignment.dart';
part 'control_flow.dart';
part 'expression.dart';
part 'function.dart';
part 'literal.dart';
part 'table.dart';

/// Static flag to track if an error is already being reported
bool _errorReporting = false;

/// Virtual Machine for the LuaLike interpreter.
///
/// Implements the AstVisitor interface to execute the AST nodes by traversing
/// the syntax tree. Handles all runtime operations including variable management,
/// function calls, and control flow.
class Interpreter extends AstVisitor<Object?>
    with
        InterpreterFunctionMixin,
        InterpreterAssignmentMixin,
        InterpreterControlFlowMixin,
        InterpreterExpressionMixin,
        InterpreterLiteralMixin,
        InterpreterTableMixin
    implements LuaRuntime {
  /// Currently active coroutine
  Coroutine? _currentCoroutine;

  /// Main thread coroutine
  Coroutine? _mainThread;

  /// Weak set of active coroutines for bookkeeping (not used as GC roots).
  final Set<WeakReference<Coroutine>> _activeCoroutines = {};

  void _pruneDeadCoroutineRefs() {
    _activeCoroutines.removeWhere((ref) => ref.target == null);
  }

  /// File manager for handling source code loading.
  @override
  final FileManager fileManager;

  /// Library registry for this interpreter instance.
  @override
  late final LibraryRegistry libraryRegistry = LibraryRegistry(this);

  @override
  Value constantStringValue(List<int> bytes) {
    final key = bytes.join(',');
    final cached = literalValueCache[key];
    if (cached != null) {
      cached.interpreter ??= this;
      return cached;
    }

    final luaString = literalStringInternPool[key] ??= LuaString.fromBytes(
      bytes,
    );
    final value = Value(luaString)..interpreter = this;
    literalValueCache[key] = value;
    return value;
  }

  /// Current environment for variable scope.
  Environment _currentEnv;

  /// Current function being executed (for upvalue resolution)
  Value? _currentFunction;

  /// Installed debug hook callback and configuration.
  Value? debugHookFunction;
  String debugHookMask = '';
  int debugHookCount = 0;
  int debugHookCountRemaining = 0;
  @override
  late final Value debugRegistry = _createDebugRegistry();
  bool _runningDebugHook = false;
  bool _nextCallIsDebugHook = false;
  final Map<String?, int> _lastDebugHookLineBySource = <String?, int>{};
  final Set<AstNode> _skipPostExecutionHooks = HashSet<AstNode>.identity();

  /// Fast path cache for local variable boxes in the current function.
  Map<String, Box<dynamic>>? _currentFastLocals;

  /// Current script path being executed
  @override
  String? currentScriptPath;

  /// Garbage collector for memory management (per-interpreter).
  ///
  /// This is an implementation of Lua's generational garbage collector
  /// as described in section 2.5.2 of the Lua 5.4 reference manual.
  @override
  late final GenerationalGCManager gc;

  /// Per-interpreter intern pool for string literals.
  /// Ensures identical literal strings in the same chunk share identity.
  @override
  final Map<String, LuaString> literalStringInternPool = <String, LuaString>{};

  /// Per-interpreter cache of Value wrappers for string literals.
  /// Avoids creating new Value objects on every literal reference.
  @override
  final Map<String, Value> literalValueCache = <String, Value>{};

  Future<void> fireDebugHook(String event, {int? line}) async {
    if (_runningDebugHook) {
      return;
    }
    final hook = debugHookFunction;
    final eventKey = switch (event) {
      'line' => 'l',
      'call' => 'c',
      'tail call' => 'c',
      'return' || 'tail return' => 'r',
      'count' => '',
      _ => event.isEmpty ? '' : event.substring(0, 1),
    };
    final enabled =
        hook != null &&
        ((event == 'count' && debugHookCount > 0) ||
            (eventKey.isNotEmpty && debugHookMask.contains(eventKey)));
    if (!enabled) {
      return;
    }

    _runningDebugHook = true;
    _nextCallIsDebugHook = true;
    try {
      if (line != null) {
        final frame =
            getVisibleFrameAtLevel(1, skipDebugHooks: true) ?? callStack.top;
        if (frame != null) {
          frame.currentLine = line;
        }
      }
      final hookArgs = <Object?>[Value(event)];
      if (line != null) {
        hookArgs.add(Value(line));
      }
      await _callFunction(hook, hookArgs, callerFunctionName: 'hook');
    } finally {
      _runningDebugHook = false;
    }
  }

  void resetDebugHookCounter() {
    debugHookCountRemaining = debugHookCount;
  }

  Value _createDebugRegistry() {
    final hookKey = Value(
      {},
      interpreter: this,
      metatable: <String, dynamic>{'__mode': Value('k')},
    );
    return Value(<String, dynamic>{'_HOOKKEY': hookKey}, interpreter: this);
  }

  void rememberDebugHookLine(int line, {String? source}) {
    if (line < 0) {
      if (source == null) {
        _lastDebugHookLineBySource.clear();
      } else {
        _lastDebugHookLineBySource.remove(source);
      }
      return;
    }
    _lastDebugHookLineBySource[source] = line;
  }

  Future<void> maybeFireLineDebugHook(
    int oneBasedLine, {
    bool force = false,
  }) async {
    if (_runningDebugHook || debugHookFunction == null) {
      return;
    }
    if (!debugHookMask.contains('l')) {
      return;
    }

    final top = callStack.top;
    if (top == null || top.isDebugHook) {
      return;
    }
    if (top.callable?.strippedDebugInfo == true) {
      return;
    }

    final source = top.scriptPath ?? currentScriptPath;
    if (!force) {
      if (top.lastDebugHookLine == oneBasedLine) {
        return;
      }
      if (_lastDebugHookLineBySource[source] == oneBasedLine) {
        return;
      }
    }

    top.lastDebugHookLine = oneBasedLine;
    rememberDebugHookLine(oneBasedLine, source: source);
    await fireDebugHook('line', line: oneBasedLine);
  }

  void suppressPostExecutionHook(AstNode node) {
    _skipPostExecutionHooks.add(node);
  }

  bool consumeSuppressedPostExecutionHook(AstNode node) {
    return _skipPostExecutionHooks.remove(node);
  }

  bool shouldFireStatementHookAfterExecution(AstNode node) {
    return _fireStatementHookAfterExecution(node);
  }

  Future<void> maybeFireStatementDebugHooks(AstNode node) async {
    if (_runningDebugHook || debugHookFunction == null) {
      return;
    }

    await maybeFireCountDebugHook();

    if (!debugHookMask.contains('l')) {
      return;
    }

    final line = _debugHookLineForNode(node);
    if (line == null) {
      return;
    }

    final top = callStack.top;
    if (top == null || top.isDebugHook) {
      return;
    }
    if (top.callable?.strippedDebugInfo == true) {
      return;
    }

    final oneBasedLine = line + 1;
    await maybeFireLineDebugHook(oneBasedLine);
  }

  Future<void> maybeFireCountDebugHook() async {
    if (_runningDebugHook || debugHookFunction == null || debugHookCount <= 0) {
      return;
    }

    debugHookCountRemaining -= 1;
    if (debugHookCountRemaining <= 0) {
      resetDebugHookCounter();
      await fireDebugHook('count');
    }
  }

  int? _debugHookLineForNode(AstNode node) {
    int lastMeaningfulSpanLine(SourceSpan span) {
      var endLine = span.end.line;
      if (span.end.column == 0 && endLine > span.start.line) {
        return endLine - 1;
      }
      if (endLine > span.start.line &&
          RegExp(r'\n[ \t]*$').hasMatch(span.text)) {
        return endLine - 1;
      }
      return endLine;
    }

    if (node case Assignment(exprs: final exprs) when exprs.length == 1) {
      final expr = exprs.first;
      if (expr is BinaryExpression &&
          expr.operatorLine != null &&
          expr.right.span != null &&
          expr.left.span != null &&
          expr.left.span!.start.line != expr.right.span!.start.line) {
        return expr.operatorLine;
      }
    }

    final span = node.span;
    if (span == null) {
      return null;
    }

    var endLine = span.end.line;
    if (span.end.column == 0 && endLine > span.start.line) {
      endLine -= 1;
    }

    return switch (node) {
      LocalDeclaration(exprs: final exprs, span: final SourceSpan span)
          when exprs.any((expr) => expr is FunctionLiteral) =>
        lastMeaningfulSpanLine(span),
      DoBlock() => null,
      IfStatement() ||
      ElseIfClause() ||
      WhileStatement() ||
      RepeatUntilLoop() ||
      ForLoop() ||
      ForInLoop() ||
      FunctionDef() ||
      LocalFunctionDef() => endLine,
      _ => span.start.line,
    };
  }

  bool _fireStatementHookAfterExecution(AstNode node) {
    return switch (node) {
      IfStatement() ||
      ElseIfClause() ||
      WhileStatement() ||
      RepeatUntilLoop() ||
      ForLoop() ||
      ForInLoop() ||
      FunctionDef() ||
      LocalFunctionDef() => true,
      _ => false,
    };
  }

  /// Global environment for variable storage.
  @override
  Environment get globals {
    Logger.debugLazy(
      () => "globals getter called",
      category: 'Interpreter',
      contextBuilder: () => {
        'env_hash': _currentEnv.hashCode,
        'is_load_isolated': _currentEnv.isLoadIsolated,
      },
    );
    return _currentEnv;
  }

  /// Evaluation stack for expression evaluation.
  @override
  final Stack evalStack = Stack();

  /// Call stack for function calls.
  @override
  final CallStack callStack = CallStack();

  /// Frames whose environments are unwinding via deferred close handlers
  /// should be hidden from debug.getinfo level lookups.
  final Set<Environment> _hiddenDebugFrameEnvs = <Environment>{};

  /// Maximum call depth for non-tail calls to simulate Lua's C stack limits.
  /// Tail calls do not grow the stack thanks to tail-call optimization.
  ///
  /// Lowered to 512 to avoid long-running overflow tests (e.g., xpcall/pcall
  /// recursion) hitting the default test timeout while still allowing
  /// realistic recursion depth for regular programs.
  static const int maxCallDepth = 512;

  /// Tracks nested function-body execution depth.
  /// Used to gate GC auto-trigger safe points that are known to interfere
  /// with tail-call rebinding in deep recursion.
  int _functionBodyDepth = 0;

  /// Gets the currently running coroutine
  @override
  Coroutine? getCurrentCoroutine() {
    Logger.infoLazy(
      () => 'getCurrentCoroutine() called',
      category: 'Coroutine',
      contextBuilder: () => {
        'coroutine_hash': _currentCoroutine?.hashCode,
        'coroutine_status': _currentCoroutine?.status.toString(),
      },
    );
    return _currentCoroutine;
  }

  /// Sets the current coroutine
  @override
  void setCurrentCoroutine(Coroutine? coroutine) {
    final oldCoroutine = _currentCoroutine;
    final oldStatus = oldCoroutine?.status;
    final newStatus = coroutine?.status;

    Logger.infoLazy(
      () => 'setCurrentCoroutine() called',
      categories: {'Interpreter', 'Coroutine'},
      contextBuilder: () => {
        'old_hash': oldCoroutine?.hashCode,
        'old_status': oldStatus?.toString() ?? 'null',
        'new_hash': coroutine?.hashCode,
        'new_status': newStatus?.toString() ?? 'null',
      },
    );
    _currentCoroutine = coroutine;
    Logger.infoLazy(
      () => 'setCurrentCoroutine() finished',
      categories: {'Interpreter', 'Coroutine'},
      contextBuilder: () => {
        'current_hash': _currentCoroutine?.hashCode,
        'current_status': _currentCoroutine?.status.toString(),
      },
    );
  }

  void hideDebugFrameEnv(Environment env) {
    _hiddenDebugFrameEnvs.add(env);
  }

  void unhideDebugFrameEnv(Environment env) {
    _hiddenDebugFrameEnvs.remove(env);
  }

  CallFrame? getVisibleFrameAtLevel(
    int level, {
    bool skipDebugHooks = false,
    bool hideEnclosingDebugHooks = false,
  }) {
    if (level <= 0) {
      return null;
    }

    var visibleLevel = 0;
    var keptCurrentHookFrame = false;
    for (final frame in callStack.frames.toList().reversed) {
      final isHookFrame = frame.isDebugHook || frame.debugNameWhat == 'hook';
      if (skipDebugHooks && isHookFrame) {
        continue;
      }
      if (hideEnclosingDebugHooks && isHookFrame) {
        if (keptCurrentHookFrame) {
          continue;
        }
        keptCurrentHookFrame = true;
      }
      final env = frame.env;
      if (env != null && _hiddenDebugFrameEnvs.contains(env)) {
        continue;
      }
      visibleLevel++;
      if (visibleLevel == level) {
        return frame;
      }
    }
    return null;
  }

  CallFrame? findFrameForCallable(Value? callable) {
    if (callable == null) {
      return null;
    }
    for (final frame in callStack.frames.toList().reversed) {
      if (identical(frame.callable, callable)) {
        return frame;
      }
    }
    return null;
  }

  CallFrame? get lastRecordedTraceFrame {
    final index = (_traceIndex - 1 + _maxTraceFrames) % _maxTraceFrames;
    final frame = _traceBuffer[index];
    return frame.callNode != null ? frame : null;
  }

  /// Gets the main thread coroutine
  @override
  Coroutine getMainThread() {
    _pruneDeadCoroutineRefs();
    Logger.infoLazy(
      () => 'getMainThread() called',
      categories: {'Interpreter', 'Coroutine'},
      contextBuilder: () => {
        'main_thread_hash': _mainThread?.hashCode,
        'exists': _mainThread != null,
      },
    );
    if (_mainThread == null) {
      // Create a main thread if it doesn't exist
      // For the main thread, we create a dummy FunctionBody since it doesn't correspond
      // to a user-defined Lua function in the AST.
      final mainThreadFunctionBody = FunctionBody([], [], false);
      _mainThread = Coroutine(
        Value(mainThreadFunctionBody), // functionValue
        mainThreadFunctionBody, // functionBody
        _currentEnv, // closureEnvironment
      );
      Logger.infoLazy(
        () => 'Main thread coroutine created',
        categories: {'Interpreter', 'Coroutine'},
        contextBuilder: () => {'main_thread_hash': _mainThread.hashCode},
      );
      _mainThread!.status = CoroutineStatus.running;
      _activeCoroutines.add(WeakReference(_mainThread!));
    }
    return _mainThread!;
  }

  /// Register a coroutine with the interpreter
  @override
  void registerCoroutine(Coroutine coroutine) {
    _pruneDeadCoroutineRefs();
    Logger.infoLazy(
      () => 'Interpreter.registerCoroutine() called, registering coroutine',
      category: 'Coroutine',
      contextBuilder: () => {'coroutine_hash': coroutine.hashCode},
    );
    _activeCoroutines.add(WeakReference(coroutine));
  }

  /// Unregister a coroutine that has completed or been closed.
  @override
  void unregisterCoroutine(Coroutine coroutine) {
    _pruneDeadCoroutineRefs();
    _activeCoroutines.removeWhere((ref) {
      final target = ref.target;
      return target == null || identical(target, coroutine);
    });
  }

  /// Initialize the coroutine system
  void initializeCoroutines() {
    _currentCoroutine = getMainThread();
    Logger.infoLazy(
      () => 'Initialized coroutine system',
      category: 'Coroutine',
      contextBuilder: () => {},
    );
  }

  // Fixed size for call frames for better performance and prevent overflow
  static const int _maxTraceFrames = 20;

  // Circular buffer to store recent CallFrames.
  final List<CallFrame> _traceBuffer = List.generate(
    _maxTraceFrames,
    (index) => CallFrame("unknown"),
  );
  int _traceIndex = 0;

  @override
  bool isYieldable = true;

  /// Stack of active protected call contexts
  final List<bool> _protectedCallStack = [];
  final List<Iterable<Object?> Function()> _externalGcRootProviders = [];

  /// Check if we're currently in a protected call context
  @override
  bool get isInProtectedCall =>
      _protectedCallStack.isNotEmpty && _protectedCallStack.last;

  /// Enter a protected call context
  @override
  void enterProtectedCall() {
    _protectedCallStack.add(true);
  }

  /// Exit a protected call context
  @override
  void exitProtectedCall() {
    if (_protectedCallStack.isNotEmpty) {
      _protectedCallStack.removeLast();
    }
  }

  /// Handle errors in protected call context
  Object? handleProtectedError(Object error) {
    if (isInProtectedCall) {
      // Convert error to appropriate format for pcall
      final errorMessage = error is LuaError ? error.message : error.toString();
      return Value.multi([false, errorMessage]);
    }
    // Re-throw if not in protected context
    throw error;
  }

  /// Gets root objects for garbage collection.
  ///
  /// These are the starting points for the mark phase of the garbage collector.
  /// All objects reachable from these roots are considered live and will not be collected.
  ///
  /// This follows the principle described in section 2.5 of the Lua reference manual:
  /// "An object is considered dead as soon as the collector can be sure the object
  /// will not be accessed again in the normal execution of the program."
  @override
  List<Object?> getRoots() {
    _pruneDeadCoroutineRefs();
    final activeFunction = _currentFunction;
    return [
      _currentEnv, // Current environment (includes globals)
      callStack, // Active call stack
      // Active closure/function value when executing AST code. This root is
      // intentionally strong because the active function owns live upvalue
      // boxes, but it means coroutine resume/yield paths must restore it
      // precisely. A stale activeFunction can keep self-referential suspended
      // threads alive through one captured box even after lexical scope ends.
      activeFunction,
      evalStack, // Evaluation stack
      _traceBuffer, // The circular buffer
      _currentCoroutine, // Currently executing coroutine
      _mainThread, // Main thread coroutine
      debugRegistry, // Persistent debug registry
      ...IOLib.gcRoots, // Current/default I/O handles live outside environments
      if (activeFunction != null) activeFunction.closureEnvironment,
      if (activeFunction != null && activeFunction.upvalues != null) ...[
        ...activeFunction.upvalues!,
        for (final upvalue in activeFunction.upvalues!) upvalue.valueBox,
      ],
      for (final frame in callStack.frames) frame.env,
      for (final frame in callStack.frames) frame.callable,
      for (final frame in callStack.frames)
        if (frame.callable case final Value callable?) ...[
          callable.closureEnvironment,
          if (callable.upvalues != null) ...[
            ...callable.upvalues!,
            for (final upvalue in callable.upvalues!) upvalue.valueBox,
          ],
        ],
      // Some call sites register temporary GC roots for the duration of an
      // active call. Suspended coroutines must detach these interpreter-global
      // providers and keep only a snapshot of the concrete objects they need;
      // otherwise the global provider list would pin paused coroutine stacks
      // and defeat weak-table / self-cycle collection tests.
      for (final provider in _externalGcRootProviders) ...provider(),
    ];
  }

  @override
  void pushExternalGcRoots(Iterable<Object?> Function() provider) {
    _externalGcRootProviders.add(provider);
  }

  @override
  void popExternalGcRoots(Iterable<Object?> Function() provider) {
    _externalGcRootProviders.remove(provider);
  }

  @override
  void runAutoGcAtSafePoint() {
    if (gc.isStopped || !gc.autoTriggerEnabled) {
      return;
    }
    final threshold = gc.autoTriggerDebtThreshold;
    final debt = gc.allocationDebt;
    if (debt < threshold) {
      return;
    }
    gc.runPendingAutoTrigger();
  }

  @override
  Future<void> runLoopGcAtSafePoint(int loopCounter) async {
    if (gc.isStopped || !gc.autoTriggerEnabled) {
      return;
    }
    final debt = gc.allocationDebt;
    if (debt <= 0) {
      return;
    }
    runAutoGcAtSafePoint();
  }

  int get externalGcRootProviderCount => _externalGcRootProviders.length;

  List<Iterable<Object?> Function()> snapshotExternalGcRootProvidersFrom(
    int baseCount,
  ) {
    if (baseCount >= _externalGcRootProviders.length) {
      return const <Iterable<Object?> Function()>[];
    }
    return List<Iterable<Object?> Function()>.from(
      _externalGcRootProviders.getRange(
        baseCount,
        _externalGcRootProviders.length,
      ),
      growable: false,
    );
  }

  void appendExternalGcRootProviders(
    Iterable<Iterable<Object?> Function()> providers,
  ) {
    _externalGcRootProviders.addAll(providers);
  }

  void trimExternalGcRootProviders(int baseCount) {
    final normalizedBase = baseCount.clamp(0, _externalGcRootProviders.length);
    if (normalizedBase < _externalGcRootProviders.length) {
      _externalGcRootProviders.removeRange(
        normalizedBase,
        _externalGcRootProviders.length,
      );
    }
  }

  @override
  bool get shouldAbandonIncrementalCycleBeforeManualCollect => false;

  /// Sets the current environment.
  ///
  /// Required by the function mixin to update the current environment
  /// during function calls.
  @override
  void setCurrentEnv(Environment env) {
    Logger.debugLazy(
      () => 'Interpreter.setCurrentEnv() called, changing environment',
      category: 'Interpreter',
      contextBuilder: () => {
        'from_hash': _currentEnv.hashCode,
        'to_hash': env.hashCode,
      },
    );
    _currentEnv = env;
    if (callStack.top case final CallFrame frame?) {
      frame.env = env;
    }
  }

  /// Restores the interpreter's ambient environment without rebinding the
  /// currently executing frame's local environment snapshot.
  ///
  /// Function-body cleanup uses this when unwinding back to a caller so debug
  /// hooks can still inspect the callee frame's locals before it is popped.
  void restoreCurrentEnv(Environment env) {
    Logger.debugLazy(
      () => 'Interpreter.restoreCurrentEnv() called, restoring environment',
      category: 'Interpreter',
      contextBuilder: () => {
        'from_hash': _currentEnv.hashCode,
        'to_hash': env.hashCode,
      },
    );
    _currentEnv = env;
  }

  /// Gets the current function being executed.
  Value? getCurrentFunction() {
    return _currentFunction;
  }

  /// Sets the current function being executed.
  void setCurrentFunction(Value? function) {
    Logger.debugLazy(
      () => 'Setting current function',
      category: 'Interpreter',
      contextBuilder: () => {
        'from_hash': _currentFunction?.hashCode,
        'to_hash': function?.hashCode,
      },
    );
    _currentFunction = function;
  }

  /// Gets the cached local boxes for the current function, if any.
  Map<String, Box<dynamic>>? getCurrentFastLocals() => _currentFastLocals;

  /// Sets the cached local boxes for the current function.
  void setCurrentFastLocals(Map<String, Box<dynamic>>? locals) {
    _currentFastLocals = locals;
  }

  /// Gets the metamethods for a specific library
  ///
  /// This is used by the Library system to get metamethods for library tables and objects
  /// [libraryName] - The name of the library to get metamethods for (e.g., "io", "string")
  Map<String, Function>? getLibraryMetamethods(String libraryName) {
    try {
      // Get all libraries from the interpreter's registry
      final library = libraryRegistry.libraries.firstWhere(
        (lib) => lib.name == libraryName,
      );
      return library.getMetamethods(this);
    } catch (e) {
      Logger.warning(
        'Library not found for metamethod access',
        category: 'Interpreter',
        context: {'libraryName': libraryName},
      );
      return null;
    }
  }

  /// Creates a new interpreter instance.
  ///
  /// [fileManager] - Optional file manager for I/O operations
  /// [environment] - Optional environment for variable scope
  Interpreter({FileManager? fileManager, Environment? environment})
    : fileManager = fileManager ?? FileManager(),
      _currentEnv = environment ?? Environment() {
    Logger.infoLazy(
      () => 'Interpreter created',
      category: 'Interpreter',
      contextBuilder: () => {},
    );

    // Set the interpreter reference in the file manager
    this.fileManager.setInterpreter(this);

    gc = GenerationalGCManager(this);
    // Enable automatic GC triggers by default so long-running Lua loops
    // eventually collect unreachable objects without requiring explicit
    // collectgarbage() calls (matching stock Lua behaviour).
    gc.autoTriggerEnabled = true;
    gc.register(_currentEnv); // Register the initial environment

    // Initialize coroutines before the standard library
    // Initialize coroutines before the standard library
    initializeCoroutines();

    // Initialize standard libraries
    initializeStandardLibrary(vm: this);

    // Attach this interpreter to the root environment for later lookups
    _currentEnv.interpreter = this;

    // Expose this GC manager as a default for objects created outside
    // an interpreter context (e.g., unit tests constructing Upvalues
    // directly). This allows immediate registration of GCObjects that
    // don't have an interpreter reference at creation time.
    GCAccess.defaultManager = gc;

    // Ensure the static current environment is set so that utility
    // methods like Value.callMetamethod can access the interpreter
    // during script execution.
  }

  /// Records a trace frame for the specified AST node.
  ///
  /// Used for debug output, error reporting, and the trace buffer.
  /// Does not affect the actual call stack.
  ///
  /// [node] - The AST node to record
  /// [functionName] - Optional function name to use instead of node's function name
  void recordTrace(AstNode node, {String? functionName}) {
    final actualFunctionName =
        functionName ??
        (node is FunctionCall
            ? node.name.toString()
            : node.runtimeType.toString());

    // Don't add to call stack - only add to the trace buffer for error reporting
    // The call stack should only contain actual function calls, not every AST node
    final frame = _traceBuffer[_traceIndex]
      ..functionName = actualFunctionName
      ..callNode = node
      ..scriptPath = currentScriptPath
      ..env = null;

    // Capture the current line number from the node's span.
    // Use the start line for return statements (to avoid off-by-one when a
    // trailing newline moves the end position to the next line), otherwise
    // use the end line as before.
    int? currentLine;
    if (node.span != null) {
      final useStartLine = node is ReturnStatement;
      currentLine =
          (useStartLine ? node.span!.start.line : node.span!.end.line) + 1;
      frame.currentLine = currentLine;

      // Update the active call frame to the line of the node currently being
      // evaluated. Using a monotonic max drifts `debug.getinfo(..., "l")`
      // forward to later statements inside the same function.
      final top = callStack.top;
      if (top != null) {
        top.currentLine = currentLine;
      }
    } else {
      frame.currentLine = -1;
    }

    _traceIndex = (_traceIndex + 1) % _maxTraceFrames;
  }

  /// Handles control flow exceptions
  ///
  /// This method is used to handle control flow mechanisms like GotoException
  /// and ReturnException which are part of normal program execution, not errors.
  ///
  /// Returns true if the exception was handled, false otherwise.
  bool handleControlFlow(Object exception, {AstNode? node}) {
    if (exception is GotoException) {
      Logger.infoLazy(
        () => 'GotoException caught',
        category: 'ControlFlow',
        contextBuilder: () => {'label': exception.label},
        node: node,
      );
      return true;
    } else if (exception is ReturnException) {
      Logger.infoLazy(
        () => 'ReturnException caught',
        category: 'ControlFlow',
        contextBuilder: () => {'hasValue': exception.value != null},
        node: node,
      );
      return true;
    } else if (exception is BreakException) {
      Logger.infoLazy(
        () => 'BreakException caught',
        category: 'ControlFlow',
        contextBuilder: () => {},
        node: node,
      );
      return true;
    }
    return false;
  }

  /// Reports an error with debug information
  ///
  /// This method should only be used for actual errors, not control flow mechanisms
  /// like GotoException or ReturnException which are part of normal program execution.
  @override
  void reportError(
    String message, {
    StackTrace? trace,
    Object? error,
    AstNode? node,
  }) {
    final luaError = error is LuaError ? error : null;

    if (luaError != null && luaError.hasBeenReported) {
      return;
    }

    // If we're already reporting an error, don't report it again
    if (_errorReporting) {
      return;
    }

    // Set the flag to indicate we're reporting an error
    _errorReporting = true;

    try {
      luaError?.hasBeenReported = true;

      // Build stack trace. For active coroutines, preserve only the
      // coroutine-owned portion of the explicit call stack before unwinding.
      final activeCoroutine = getCurrentCoroutine();
      activeCoroutine?.captureCurrentCallStack();
      final luaStackTrace = activeCoroutine != null
          ? callStack.toLuaStackTraceFromDepth(
              activeCoroutine.callStackBaseDepth,
            )
          : callStack.toLuaStackTrace();
      if (luaError != null && luaError.luaStackTrace == null) {
        luaError.luaStackTrace = luaStackTrace;
      }

      // Add recent call frames for non-coroutine errors only. Coroutine
      // tracebacks need to stay scoped to the coroutine-owned stack slice.
      if (activeCoroutine == null) {
        int start = _traceIndex;
        final List<LuaStackFrame> recentTrace = [];
        for (int i = 0; i < _maxTraceFrames; i++) {
          final frame = _traceBuffer[(start + i) % _maxTraceFrames];
          if (frame.callNode != null) {
            bool isDuplicate = false;
            for (final existingFrame in luaStackTrace.frames) {
              if (frame.callNode == existingFrame.node) {
                isDuplicate = true;
                break;
              }
            }

            if (!isDuplicate) {
              recentTrace.add(
                LuaStackFrame.fromNode(frame.callNode!, frame.functionName),
              );
            }
          }
        }
        luaStackTrace.frames.addAll(recentTrace);
      }

      // Format error message like Lua CLI
      String errorMsg = message;
      String filename = "unknown";
      int line = 0;

      // Try to get the script path from the environment
      final scriptPathValue = globals.get('_SCRIPT_PATH');
      String? scriptPath;
      if (scriptPathValue is Value && scriptPathValue.raw != null) {
        scriptPath = scriptPathValue.raw.toString();
      } else {
        scriptPath = currentScriptPath;
      }

      if (node != null && node.span != null) {
        final span = node.span!;
        // Use the relative path if possible
        if (span.sourceUrl != null) {
          String filepath = span.sourceUrl.toString();
          // Remove 'file://' prefix if present
          if (filepath.startsWith('file://')) {
            filepath = filepath.substring(7);
          }

          // Try to make the path relative to the current directory
          try {
            final currentDir = fs.getCurrentDirectory() ?? "";
            if (filepath.startsWith(currentDir)) {
              filepath = filepath.substring(currentDir.length);
              // Remove leading slash if present
              if (filepath.startsWith('/')) {
                filepath = filepath.substring(1);
              }
            }
          } catch (e) {
            // If we can't make it relative, use the full path
          }

          filename = filepath;
        } else if (scriptPath != null) {
          // If the span doesn't have a source URL but we have a script path, use that
          filename = scriptPath.split('/').last;
        }
        line = span.start.line + 1; // Convert to 1-indexed line number
        errorMsg = "$filename:$line: $message";
      } else if (scriptPath != null) {
        // Try to make the script path relative
        String filepath = scriptPath;
        try {
          final currentDir = fs.getCurrentDirectory() ?? "";
          if (filepath.startsWith(currentDir)) {
            filepath = filepath.substring(currentDir.length);
            // Remove leading slash if present
            if (filepath.startsWith('/')) {
              filepath = filepath.substring(1);
            }
          }
        } catch (e) {
          // If we can't make it relative, use the full path
        }

        // Extract just the filename for display
        filename = filepath.split('/').last;

        errorMsg = "$filename: $message";
      }

      // Get the executable name (lualike or lua)
      String executableName = platform.executableName;

      // Print error in Lua style with executable name prefix
      print("$executableName: $errorMsg");
      print(luaStackTrace.format());

      // Only log the error details for debugging if debug mode is enabled
      // This avoids duplicate error messages
      if (Logger.enabled) {
        Logger.infoLazy(
          () => "Error details",
          category: 'Error',
          contextBuilder: () => {'message': message},
          node: node,
        );
        if (trace != null) {
          Logger.infoLazy(
            () => "Stack trace",
            category: 'Error',
            contextBuilder: () => {'trace': trace.toString()},
          );
        }
      }
    } finally {
      // Reset the flag
      _errorReporting = false;
    }
  }

  /// Runs the given AST program and returns the result.
  ///
  /// Executes a list of statements sequentially, maintaining a map of labels
  /// to support goto statements. Handles control flow through exceptions for:
  /// - break statements (BreakException)
  /// - return statements (ReturnException)
  /// - goto statements (GotoException)
  ///
  /// [program] - List of AST nodes representing the program to execute
  /// Returns the result of the last executed statement, or null.
  Future<Object?> run(List<AstNode> program) async {
    Logger.infoLazy(
      () => 'Running program',
      category: 'Interpreter',
      contextBuilder: () => {'statementsCount': program.length},
    );

    // Set the script path in the call stack if available
    final prevScriptPath = callStack.scriptPath;
    final scriptPathValue = globals.get('_SCRIPT_PATH');
    if (scriptPathValue is Value && scriptPathValue.raw != null) {
      String scriptPath = scriptPathValue.raw.toString();
      callStack.setScriptPath(scriptPath);
      currentScriptPath = scriptPath;
    }

    // Clear evaluation stack at start.
    while (!evalStack.isEmpty) {
      evalStack.pop();
      Logger.infoLazy(
        () => 'evalStack.pop()',
        category: 'Interpreter',
        contextBuilder: () => {},
      );
    }

    // Create a script environment for main script execution
    // This ensures local variables in the main script don't affect globals
    final savedEnv = _currentEnv;
    final savedFunction = _currentFunction;
    final savedFastLocals = _currentFastLocals;
    final savedExternalRootCount = _externalGcRootProviders.length;
    final scriptEnv = Environment(parent: savedEnv, interpreter: this);
    // Propagate load-isolated flag so loaded chunks keep using provided _ENV
    scriptEnv.isLoadIsolated = savedEnv.isLoadIsolated;
    _currentEnv = scriptEnv;

    // Push a top-level frame to track currentline via AST spans, bound to script env
    callStack.push(currentScriptPath ?? 'chunk', env: _currentEnv);

    void pushTopLevelResult(Object? callResult) {
      if (callResult == null) {
        return;
      }
      if (callResult is Value) {
        evalStack.push(callResult);
      } else if (callResult is List) {
        if (callResult.isEmpty) {
          evalStack.push(Value(null));
        } else if (callResult.length == 1) {
          final v = callResult[0];
          evalStack.push(v is Value ? v : Value(v));
        } else {
          evalStack.push(Value.multi(callResult));
        }
      } else {
        evalStack.push(Value(callResult));
      }
    }

    try {
      final executionResult = await _executeStatements(program);
      if (executionResult is TailCallSignal) {
        Logger.debugLazy(
          () => 'Top-level tail return detected; invoking callee',
          category: 'Interpreter',
          contextBuilder: () => {'argsCount': executionResult.args.length},
        );
        final callee = executionResult.functionValue is Value
            ? executionResult.functionValue as Value
            : Value(executionResult.functionValue);
        final normalizedArgs = executionResult.args
            .map((a) => a is Value ? a : Value(a))
            .toList();
        pushTopLevelResult(await callFunction(callee, normalizedArgs));
      }
    } on ReturnException catch (e) {
      Logger.debugLazy(
        () => 'Top-level return',
        category: 'Interpreter',
        contextBuilder: () => {'hasValue': e.value != null},
      );
      // Handle top-level return statements - this is valid in Lua
      // Push the return value to eval stack so it can be retrieved
      pushTopLevelResult(e.value);
    } on TailCallException catch (t) {
      Logger.debugLazy(
        () => 'Top-level tail return detected; invoking callee',
        category: 'Interpreter',
        contextBuilder: () => {'argsCount': t.args.length},
      );
      // Handle top-level tail return: execute callee and use its result
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      pushTopLevelResult(await callFunction(callee, normalizedArgs));
    } on GotoException catch (e) {
      Logger.warningLazy(
        () => 'Undefined label',
        category: 'ControlFlow',
        contextBuilder: () => {'label': e.label},
      );
      throw GotoException('Undefined label: ${e.label}');
    } finally {
      // Restore the original environment
      _currentEnv = savedEnv;
      _currentFunction = savedFunction;
      _currentFastLocals = savedFastLocals;
      if (_externalGcRootProviders.length > savedExternalRootCount) {
        _externalGcRootProviders.removeRange(
          savedExternalRootCount,
          _externalGcRootProviders.length,
        );
      }
    }

    Logger.infoLazy(
      () => 'Program finished',
      category: 'Interpreter',
      contextBuilder: () => {},
    );

    // Restore previous script path
    callStack.setScriptPath(prevScriptPath);
    currentScriptPath = prevScriptPath;

    // Pop the top-level frame
    callStack.pop();

    return evalStack.isEmpty ? null : evalStack.peek();
  }

  Future<Object?> _executeStatements(List<AstNode> statements) async {
    final labelMap = <String, int>{};
    for (var i = 0; i < statements.length; i++) {
      final node = statements[i];
      if (node is Label) {
        labelMap[node.label.name] = i;
      }
    }
    Logger.infoLazy(
      () => 'Label map',
      category: 'Interpreter',
      contextBuilder: () => {'labels': labelMap.keys.toList()},
    );

    Object? result;
    var index = 0;
    while (index < statements.length) {
      final node = statements[index];
      final currentIndex = index;
      Logger.debugLazy(
        () => 'Visiting node',
        category: 'Interpreter',
        contextBuilder: () => {
          'nodeType': node.runtimeType.toString(),
          'index': index,
        },
      );
      recordTrace(node);
      final hookAfterExecution = _fireStatementHookAfterExecution(node);
      if (!hookAfterExecution) {
        await maybeFireStatementDebugHooks(node);
      }
      var statementCompleted = false;
      Stopwatch? statementStopwatch;
      if (Logger.enabled) {
        statementStopwatch = Stopwatch()..start();
      }
      try {
        result = await node.accept(this);
        if (hookAfterExecution && !consumeSuppressedPostExecutionHook(node)) {
          await maybeFireStatementDebugHooks(node);
        }
        statementCompleted = true;
      } on GotoException catch (e) {
        if (!labelMap.containsKey(e.label)) {
          // Propagate to outer scope for resolution
          throw GotoException(e.label);
        }
        final targetIndex = labelMap[e.label]!;
        await _rewindLocalsForGoto(
          statements,
          targetIndex: targetIndex,
          currentIndex: currentIndex,
        );
        index = targetIndex;
      } finally {
        if (statementStopwatch != null) {
          statementStopwatch.stop();
          final elapsedMs = statementStopwatch.elapsedMilliseconds;
          if (elapsedMs >= 200) {
            String location = '';
            final span = node.span;
            if (span != null) {
              final line = span.start.line + 1;
              final column = span.start.column + 1;
              final sourcePath = span.sourceUrl?.path;
              if (sourcePath != null) {
                location = ' @ $sourcePath:$line:$column';
              } else {
                location = ' @ $line:$column';
              }
            }
            final debt = gc.allocationDebt;
            final script =
                callStack.scriptPath ?? currentScriptPath ?? '<chunk>';
            final currentFunction = callStack.top?.functionName ?? '<global>';
            Logger.debug(
              'Statement execution time',
              category: 'Performance',
              context: {
                'nodeType': node.runtimeType.toString(),
                'index': currentIndex,
                'elapsedMs': elapsedMs,
                'allocationDebt': debt,
                'script': script,
                'function': currentFunction,
                'location': location,
              },
            );
          }
        }
        if (statementCompleted) {
          // Discard temporary expression results between statements so they
          // do not persist on the eval stack as unintended GC roots.
          // Only clear after expression statements to preserve top-level
          // returns/tail-call results used by callers (e.g., REPL).
          if (node is ExpressionStatement) {
            while (!evalStack.isEmpty) {
              evalStack.pop();
            }
          }
          await _runAutoGCAtSafePoint();
        }
      }

      if (result is TailCallSignal) {
        return result;
      }

      if (statementCompleted) {
        index++;
      }
    }
    return result;
  }

  Future<void> _rewindLocalsForGoto(
    List<AstNode> statements, {
    required int targetIndex,
    required int currentIndex,
  }) async {
    if (targetIndex >= currentIndex) {
      return;
    }

    final namesToDiscard = <String>{};
    for (var i = targetIndex + 1; i <= currentIndex; i++) {
      final statement = statements[i];
      switch (statement) {
        case LocalDeclaration(:final names):
          for (final name in names) {
            namesToDiscard.add(name.name);
          }
        case LocalFunctionDef(:final name):
          namesToDiscard.add(name.name);
        default:
          break;
      }
    }

    for (final name in namesToDiscard) {
      final box = _currentEnv.values[name];
      if (box == null || !box.isLocal) {
        continue;
      }

      if (_currentEnv.toBeClosedVars.remove(name)) {
        final value = box.value;
        if (value is Value) {
          await value.close();
        }
      }

      if (!box.hasUpvalueReferences) {
        box.value = null;
      }
      _currentEnv.values.remove(name);
    }
  }

  /// Evaluates a program.
  ///
  /// Executes a sequence of statements that make up a program.
  /// Returns the result of the last statement executed.
  ///
  /// [program] - The program node containing statements
  /// Returns the result of the last statement executed.
  @override
  Future<Object?> visitProgram(Program program) async {
    Object? result;
    for (final stmt in program.statements) {
      // Don't call recordTrace here since run() already does it
      result = await stmt.accept(this);
    }
    return result;
  }

  @override
  noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  /// Add this method to the Interpreter class
  @override
  Environment getCurrentEnv() {
    Logger.infoLazy(
      () => 'Interpreter.getCurrentEnv() called',
      category: 'Interpreter',
      contextBuilder: () => {'env_hash': _currentEnv.hashCode},
    );
    return _currentEnv;
  }

  /// Explicitly call a function with the given arguments
  @override
  Future<Object?> callFunction(
    Value function,
    List<Object?> args, {
    String? debugName,
    String debugNameWhat = '',
  }) async {
    return await _callFunction(
      function,
      args,
      debugNameOverride: debugName,
      debugNameWhatOverride: debugNameWhat,
    );
  }

  @override
  Future<Object?> runAst(List<AstNode> program) {
    final semanticError = validateProgramSemantics(Program(program));
    if (semanticError != null) {
      throw Exception(semanticError);
    }
    return run(program);
  }

  @override
  Future<Object?> evaluateAst(AstNode node) => node.accept(this);

  @override
  Future<LuaChunkLoadResult> loadChunk(LuaChunkLoadRequest request) async {
    final normalized = await normalizeChunkLoadRequest(this, request);
    if (normalized.failure case final failure?) {
      return failure;
    }

    final normalizedRequest = normalized.request;
    final binarySource = compiledArtifactSourceBytes(normalizedRequest.source);
    if (binarySource != null && looksLikeLualikeIrBytes(binarySource)) {
      return const LuaChunkLoadResult.failure(
        'lualike_ir artifacts require the IR runtime',
      );
    }

    final luaBytecodeResult = tryLoadLuaBytecodeArtifact(
      this,
      normalizedRequest,
    );
    if (luaBytecodeResult != null) {
      return luaBytecodeResult;
    }

    return loadChunkWithLegacyAstSupport(this, normalizedRequest);
  }

  @override
  Object? dumpFunction(Value function, {bool stripDebugInfo = false}) {
    return dumpFunctionWithLegacyAstTransport(
      function,
      stripDebugInfo: stripDebugInfo,
    );
  }

  @override
  LuaFunctionDebugInfo? debugInfoForFunction(Value function) {
    return defaultDebugInfoForFunction(this, function);
  }

  Future<void> _runAutoGCAtSafePoint() async {
    final threshold = gc.autoTriggerDebtThreshold;
    final debt = gc.allocationDebt;
    if (Logger.enabled) {
      Logger.debug(
        'Safe point debt check',
        category: 'GC',
        context: {'debt': debt, 'threshold': threshold},
      );
    }
    if (debt < threshold && !gc.hasPendingAsyncFinalizers) {
      return;
    }
    if (debt >= threshold) {
      gc.runPendingAutoTrigger();
    }
    if (gc.hasPendingAsyncFinalizers) {
      await gc.drainPendingAsyncFinalizers();
    }
  }
}
