import 'dart:io' show Directory, Platform;

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/call_stack.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/file_manager.dart';
import 'package:lualike/src/gc/generational_gc.dart' show GenerationalGCManager;
import 'package:lualike/src/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_stack_trace.dart';
import 'package:lualike/src/stack.dart';
import 'package:lualike/src/stdlib/init.dart' show initializeStandardLibrary;
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';

import '../coroutine.dart';
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
  Environment get globals => _currentEnv;

  /// Evaluation stack for expression evaluation.
  @override
  final Stack evalStack = Stack();

  /// Call stack for function calls.
  @override
  final CallStack callStack = CallStack();

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
  }

  /// Records trace information for the current execution point.
  ///
  /// This is used for error reporting and debugging.
  void recordTrace(AstNode node, [String functionName = 'unknown']) {
    // Skip recording trace for certain node types
    if (node is StringLiteral ||
        node is NumberLiteral ||
        node is BooleanLiteral) {
      return;
    }

    // Try to get a better function name if possible
    String actualFunctionName = functionName;

    // Check if this is the main chunk
    final isMainChunk = globals.get('_MAIN_CHUNK') != null;

    if (isMainChunk) {
      actualFunctionName = '_MAIN_CHUNK';
    } else if (functionName == 'unknown') {
      // Try to determine a better function name based on the node type
      if (node is FunctionCall) {
        if (node.name is Identifier) {
          actualFunctionName = (node.name as Identifier).name;
        } else if (node.name is TableAccessExpr) {
          final tableAccess = node.name as TableAccessExpr;
          if (tableAccess.index is Identifier) {
            actualFunctionName = (tableAccess.index as Identifier).name;
          } else {
            actualFunctionName = 'method';
          }
        }
      } else if (node is FunctionDef) {
        actualFunctionName = node.name.first.name;
      } else if (node is LocalFunctionDef) {
        actualFunctionName = node.name.name;
      } else if (node is MethodCall) {
        if (node.methodName is Identifier) {
          actualFunctionName = (node.methodName as Identifier).name;
        } else {
          actualFunctionName = 'method';
        }
      } else if (node is FunctionLiteral) {
        actualFunctionName = 'function';
      }
    }

    // Add the frame to the call stack
    callStack.push(actualFunctionName, callNode: node);

    // Also add to the trace buffer for error reporting
    final frame = CallFrame(actualFunctionName, callNode: node);
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
            // Get the script path from the call stack
            final scriptPath = callStack.scriptPath;
            recentTrace.add(
              LuaStackFrame.fromNode(
                frame.callNode!,
                frame.functionName,
                scriptPath: scriptPath,
              ),
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
            final currentDir = Directory.current.path;
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
          final currentDir = Directory.current.path;
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
      String executableName = "lualike";
      try {
        executableName = Platform.executable.split('/').last;
      } catch (e) {
        // If we can't get the executable name, use a default
      }

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

    try {
      await _executeStatements(program);
    } on GotoException catch (e) {
      // Report undefined label with helpful message
      throw GotoException('Undefined label: ${e.label}');
    }

    Logger.info('Program finished', category: 'Interpreter');
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
        Logger.warning('Undefined label: ${e.label}', category: 'Interpreter');
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
