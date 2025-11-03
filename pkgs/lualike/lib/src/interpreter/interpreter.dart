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
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart' show initializeStandardLibrary;
import 'package:lualike/src/stdlib/library.dart' show LibraryRegistry;
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/utils/type.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';
import 'package:lualike/src/table_storage.dart';
import 'package:lualike/src/utils/file_system_utils.dart' as fs;
import 'package:lualike/src/interpreter/upvalue_assignment.dart';
import 'package:lualike/src/bytecode/loop_compiler.dart';
import 'package:lualike/src/bytecode/vm.dart';

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

  /// File manager for handling source code loading.
  @override
  final FileManager fileManager;

  /// Library registry for this interpreter instance.
  @override
  late final LibraryRegistry libraryRegistry = LibraryRegistry(this);

  /// Current environment for variable scope.
  Environment _currentEnv;

  /// Current function being executed (for upvalue resolution)
  Value? _currentFunction;

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

  /// Gets the main thread coroutine
  @override
  Coroutine getMainThread() {
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
    Logger.info(
      'Interpreter.registerCoroutine() called, registering coroutine',
      category: 'Coroutine',
      context: {'coroutine_hash': coroutine.hashCode},
    );
    _activeCoroutines.add(WeakReference(coroutine));
  }

  /// Unregister a coroutine that has completed or been closed.
  @override
  void unregisterCoroutine(Coroutine coroutine) {
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
    return [
      _currentEnv, // Current environment (includes globals)
      callStack, // Active call stack
      evalStack, // Evaluation stack
      _traceBuffer, // The circular buffer
      _currentCoroutine, // Currently executing coroutine
      _mainThread, // Main thread coroutine
    ];
  }

  /// Sets the current environment.
  ///
  /// Required by the function mixin to update the current environment
  /// during function calls.
  @override
  void setCurrentEnv(Environment env) {
    Logger.debug(
      'Interpreter.setCurrentEnv() called, changing environment',
      category: 'Interpreter',
      context: {'from_hash': _currentEnv.hashCode, 'to_hash': env.hashCode},
    );
    _currentEnv = env;
  }

  /// Gets the current function being executed.
  Value? getCurrentFunction() {
    return _currentFunction;
  }

  /// Sets the current function being executed.
  void setCurrentFunction(Value? function) {
    Logger.debug(
      'Setting current function',
      category: 'Interpreter',
      context: {
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
    final frame = CallFrame(actualFunctionName, callNode: node);

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

      // Update the active call frame, keeping line numbers non-decreasing
      final top = callStack.top;
      if (top != null && top.currentLine < currentLine) {
        top.currentLine = currentLine;
      }
    }

    _traceBuffer[_traceIndex] = frame;
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
      Logger.info(
        'GotoException caught',
        category: 'ControlFlow',
        context: {'label': exception.label},
        node: node,
      );
      return true;
    } else if (exception is ReturnException) {
      Logger.info(
        'ReturnException caught',
        category: 'ControlFlow',
        context: {'hasValue': exception.value != null},
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

      // Build stack trace
      final luaStackTrace = callStack.toLuaStackTrace();

      // Add recent call frames
      int start = _traceIndex;
      final List<LuaStackFrame> recentTrace = [];
      for (int i = 0; i < _maxTraceFrames; i++) {
        final frame = _traceBuffer[(start + i) % _maxTraceFrames];
        if (frame.callNode != null) {
          // Only add frames that have a call node and aren't duplicates
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
    Logger.info(
      'Running program',
      category: 'Interpreter',
      context: {'statementsCount': program.length},
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
    final scriptEnv = Environment(parent: savedEnv, interpreter: this);
    // Propagate load-isolated flag so loaded chunks keep using provided _ENV
    scriptEnv.isLoadIsolated = savedEnv.isLoadIsolated;
    _currentEnv = scriptEnv;

    // Push a top-level frame to track currentline via AST spans, bound to script env
    callStack.push(currentScriptPath ?? 'chunk', env: _currentEnv);

    try {
      await _executeStatements(program);
    } on ReturnException catch (e) {
      Logger.debug(
        'Top-level return',
        category: 'Interpreter',
        context: {'hasValue': e.value != null},
      );
      // Handle top-level return statements - this is valid in Lua
      // Push the return value to eval stack so it can be retrieved
      if (e.value != null) {
        evalStack.push(e.value);
      }
    } on TailCallException catch (t) {
      Logger.debug(
        'Top-level tail return detected; invoking callee',
        category: 'Interpreter',
        context: {'argsCount': t.args.length},
      );
      // Handle top-level tail return: execute callee and use its result
      final callee = t.functionValue is Value
          ? t.functionValue as Value
          : Value(t.functionValue);
      final normalizedArgs = t.args
          .map((a) => a is Value ? a : Value(a))
          .toList();
      final callResult = await callFunction(callee, normalizedArgs);
      if (callResult != null) {
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
      Logger.debug(
        'Visiting node',
        category: 'Interpreter',
        context: {'nodeType': node.runtimeType.toString(), 'index': index},
      );
      recordTrace(node);
      var statementCompleted = false;
      Stopwatch? statementStopwatch;
      if (Logger.enabled) {
        statementStopwatch = Stopwatch()..start();
      }
      try {
        result = await node.accept(this);
        statementCompleted = true;
        index++;
      } on GotoException catch (e) {
        if (!labelMap.containsKey(e.label)) {
          // Propagate to outer scope for resolution
          throw GotoException(e.label);
        }
        index = labelMap[e.label]!;
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
          _runAutoGCAtSafePoint();
        }
      }
    }
    return result;
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
    Logger.info(
      'Interpreter.getCurrentEnv() called',
      category: 'Interpreter',
      context: {'env_hash': _currentEnv.hashCode},
    );
    return _currentEnv;
  }

  /// Explicitly call a function with the given arguments
  @override
  Future<Object?> callFunction(Value function, List<Object?> args) async {
    return await _callFunction(function, args);
  }

  @override
  Future<Object?> runAst(List<AstNode> program) => run(program);

  @override
  Future<Object?> evaluateAst(AstNode node) => node.accept(this);

  void _runAutoGCAtSafePoint() {
    final threshold = gc.autoTriggerDebtThreshold;
    final debt = gc.allocationDebt;
    if (Logger.enabled) {
      Logger.debug(
        'Safe point debt check',
        category: 'GC',
        context: {'debt': debt, 'threshold': threshold},
      );
    }
    if (debt < threshold) {
      return;
    }
    gc.runPendingAutoTrigger();
  }
}
