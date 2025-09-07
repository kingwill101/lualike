import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/generational_gc.dart' show GenerationalGCManager;
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_stack_trace.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart' show initializeStandardLibrary;
import 'package:lualike/src/utils/platform_utils.dart' as platform;
import 'package:lualike/src/utils/type.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';
import 'package:lualike/src/utils/file_system_utils.dart' as fs;

import '../exceptions.dart';
import '../extensions/extensions.dart';

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
        InterpreterTableMixin {
  /// Currently active coroutine
  Coroutine? _currentCoroutine;

  /// Main thread coroutine
  Coroutine? _mainThread;

  /// Set of all active coroutines
  final Set<Coroutine> _activeCoroutines = {};

  /// File manager for handling source code loading.
  final FileManager fileManager;

  /// Current environment for variable scope.
  Environment _currentEnv;

  /// Current script path being executed
  String? currentScriptPath;

  /// Garbage collector for memory management.
  ///
  /// This is an implementation of Lua's generational garbage collector
  /// as described in section 2.5.2 of the Lua 5.4 reference manual.
  GenerationalGCManager get gc => GenerationalGCManager.instance;

  /// Global environment for variable storage.
  @override
  Environment get globals {
    Logger.debug(
      "globals getter called, returning environment ${_currentEnv.hashCode} with isLoadIsolated=${_currentEnv.isLoadIsolated}",
      category: 'Interpreter',
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
  static const int maxCallDepth = 128;

  /// Gets the currently running coroutine
  @override
  Coroutine? getCurrentCoroutine() {
    Logger.info(
      '>>> Interpreter.getCurrentCoroutine() called, current: ${_currentCoroutine?.hashCode}',
      category: 'Interpreter',
    );
    return _currentCoroutine;
  }

  /// Sets the current coroutine
  @override
  void setCurrentCoroutine(Coroutine? coroutine) {
    final oldCoroutine = _currentCoroutine;
    // Read status explicitly BEFORE logging
    final oldStatus = oldCoroutine?.status;
    final newStatus = coroutine?.status;

    Logger.info(
      '>>> Interpreter.setCurrentCoroutine() called, changing from: ${oldCoroutine?.hashCode} (PRE-READ status: $oldStatus) to: ${coroutine?.hashCode} (PRE-READ status: $newStatus)',
      category: 'Interpreter',
    );
    _currentCoroutine = coroutine;
    Logger.info(
      '>>> Interpreter.setCurrentCoroutine() finished. Old: ${oldCoroutine?.hashCode} (POST status: ${oldCoroutine?.status}). New: ${_currentCoroutine?.hashCode} (POST status: ${_currentCoroutine?.status})',
      category: 'Interpreter',
    );
  }

  /// Gets the main thread coroutine
  @override
  Coroutine getMainThread() {
    Logger.info(
      '>>> Interpreter.getMainThread() called, main thread: ${_mainThread.hashCode}',
      category: 'Interpreter',
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
      Logger.info(
        'Interpreter: Main thread coroutine created: ${_mainThread.hashCode}',
        category: 'Interpreter',
      );
      _mainThread!.status = CoroutineStatus.running;
      _activeCoroutines.add(_mainThread!);
    }
    return _mainThread!;
  }

  /// Register a coroutine with the interpreter
  @override
  void registerCoroutine(Coroutine coroutine) {
    Logger.info(
      '>>> Interpreter.registerCoroutine() called, registering: ${coroutine.hashCode}',
      category: 'Interpreter',
    );
    _activeCoroutines.add(coroutine);
  }

  /// Initialize the coroutine system
  void initializeCoroutines() {
    _currentCoroutine = getMainThread();
    Logger.info('Initialized coroutine system', category: 'Coroutine');
  }

  // Fixed size for call frames for better performance and prevent overflow
  static const int _maxTraceFrames = 20;

  // Circular buffer to store recent CallFrames.
  final List<CallFrame> _traceBuffer = List.generate(
    _maxTraceFrames,
    (index) => CallFrame("unknown"),
  );
  int _traceIndex = 0;

  bool isYieldable = true;

  /// Stack of active protected call contexts
  final List<bool> _protectedCallStack = [];

  /// Check if we're currently in a protected call context
  bool get isInProtectedCall =>
      _protectedCallStack.isNotEmpty && _protectedCallStack.last;

  /// Enter a protected call context
  void enterProtectedCall() {
    _protectedCallStack.add(true);
  }

  /// Exit a protected call context
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
  List<Object?> getRoots() {
    return [
      _currentEnv, // Current environment (includes globals)
      callStack, // Active call stack
      evalStack, // Evaluation stack
      _traceBuffer, // The circular buffer
      _currentCoroutine, // Currently executing coroutine
      _mainThread, // Main thread coroutine
      _activeCoroutines, // Set of all active coroutines
    ];
  }

  /// Sets the current environment.
  ///
  /// Required by the function mixin to update the current environment
  /// during function calls.
  @override
  void setCurrentEnv(Environment env) {
    Logger.info(
      '>>> Interpreter.setCurrentEnv() called, changing from: ${_currentEnv.hashCode} to: ${env.hashCode}',
      category: 'Interpreter',
    );
    _currentEnv = env;
    Environment.current = env;
  }

  /// Creates a new interpreter instance.
  ///
  /// [fileManager] - Optional file manager for I/O operations
  /// [environment] - Optional environment for variable scope
  Interpreter({FileManager? fileManager, Environment? environment})
    : fileManager = fileManager ?? FileManager(),
      _currentEnv = environment ?? Environment() {
    Logger.info('Interpreter created', category: 'Interpreter');

    // Set the interpreter reference in the file manager
    this.fileManager.setInterpreter(this);

    GenerationalGCManager.initialize(this);
    GenerationalGCManager.instance.register(
      _currentEnv,
    ); // Register the initial environment

    // Initialize coroutines before the standard library
    initializeCoroutines();

    initializeStandardLibrary(env: _currentEnv, astVm: this);

    // Attach this interpreter to the root environment for later lookups
    _currentEnv.interpreter = this;

    // Ensure the static current environment is set so that utility
    // methods like Value.callMetamethod can access the interpreter
    // during script execution.
    Environment.current = _currentEnv;
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
    // Only handle specific control flow exceptions
    // Do not try to handle other types of exceptions
    if (exception is GotoException) {
      Logger.info(
        'GotoException caught: ${exception.label}',
        category: 'Interpreter',
        node: node,
      );
      return true;
    } else if (exception is ReturnException) {
      Logger.info(
        'ReturnException caught with value: ${exception.value}',
        category: 'Interpreter',
        node: node,
      );
      return true;
    } else if (exception is BreakException) {
      Logger.info('BreakException caught', category: 'Interpreter', node: node);
      return true;
    }
    // For all other exceptions, return false to let them be handled normally
    return false;
  }

  /// Reports an error with debug information
  ///
  /// This method should only be used for actual errors, not control flow mechanisms
  /// like GotoException or ReturnException which are part of normal program execution.
  void reportError(
    String message, {
    StackTrace? trace,
    Object? error,
    AstNode? node,
  }) {
    // If we're already reporting an error, don't report it again
    if (_errorReporting) {
      return;
    }

    // Set the flag to indicate we're reporting an error
    _errorReporting = true;

    try {
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
        Logger.info("Error details: $message", category: 'Error', node: node);
        if (trace != null) {
          Logger.info("Stack trace: $trace", category: 'Error');
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
      'Running program with ${program.length} statements',
      category: 'Interpreter',
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
      Logger.info('evalStack.pop()', category: 'Interpreter');
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
      // Handle top-level return statements - this is valid in Lua
      Logger.debug(
        'Top-level return with value: ${e.value}',
        category: 'Interpreter',
      );
      // Push the return value to eval stack so it can be retrieved
      if (e.value != null) {
        evalStack.push(e.value);
      }
    } on TailCallException catch (t) {
      // Handle top-level tail return: execute callee and use its result
      Logger.debug(
        'Top-level tail return detected; invoking callee with ${t.args.length} args',
        category: 'Interpreter',
      );
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
      // Report undefined label with helpful message
      Logger.warning('Undefined label: ${e.label}', category: 'Interpreter');
      throw GotoException('Undefined label: ${e.label}');
    } finally {
      // Restore the original environment
      _currentEnv = savedEnv;
    }

    Logger.info('Program finished', category: 'Interpreter');

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
    Logger.info('Label map: $labelMap', category: 'Interpreter');

    Object? result;
    var index = 0;
    while (index < statements.length) {
      final node = statements[index];
      Logger.debug(
        'Visiting node ${node.runtimeType} at index $index',
        category: 'Interpreter',
      );
      recordTrace(node);
      try {
        result = await node.accept(this);
        index++;
      } on GotoException catch (e) {
        if (!labelMap.containsKey(e.label)) {
          // Propagate to outer scope for resolution
          throw GotoException(e.label);
        }
        index = labelMap[e.label]!;
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
  Environment getCurrentEnv() {
    Logger.info(
      '>>> Interpreter.getCurrentEnv() called, current: ${_currentEnv.hashCode}',
      category: 'Interpreter',
    );
    return _currentEnv;
  }

  /// Explicitly call a function with the given arguments
  Future<Object?> callFunction(Value function, List<Object?> args) async {
    return await _callFunction(function, args);
  }
}
