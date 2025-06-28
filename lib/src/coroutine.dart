import 'dart:async';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/logger.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/ast.dart';
import 'package:lualike/src/lua_error.dart';

import 'exceptions.dart';

/// Represents a coroutine status as defined in Lua
enum CoroutineStatus {
  /// The coroutine is running (it is the one that called status)
  running,

  /// The coroutine is suspended in a call to yield, or it has not started running yet
  suspended,

  /// The coroutine is active but not running (it has resumed another coroutine)
  normal,

  /// The coroutine has finished its body function, or it has stopped with an error
  dead,
}

/// Represents a Lua coroutine that participates in garbage collection
class Coroutine extends GCObject {
  /// The function that this coroutine executes (its Value wrapper)
  final Value functionValue;

  /// The AST node representing the function body
  final FunctionBody functionBody;

  /// Current status of the coroutine
  CoroutineStatus status = CoroutineStatus.suspended;

  /// The environment that was active when the coroutine was defined (closure environment).
  /// This serves as the parent for the _executionEnvironment.
  final Environment closureEnvironment;

  /// The actual environment where the function's parameters and local variables reside.
  /// This environment is preserved across yields.
  Environment _executionEnvironment;

  /// Program counter: the index of the next statement to execute in functionBody.body.
  int _programCounter = 0;

  /// Completer used to pause/resume execution
  Completer<List<Object?>>? completer;

  /// Current execution task
  Future<void>? _executionTask;

  /// Error that caused the coroutine to die, if any
  Object? _error;

  /// Whether the coroutine is being finalized
  final bool _beingFinalized = false;

  /// Constructor
  Coroutine(this.functionValue, this.functionBody, this.closureEnvironment)
    : _executionEnvironment = closureEnvironment.clone(
        interpreter: closureEnvironment.interpreter,
      ), // Clone closureEnv for execution
      super() {
    // Register with garbage collector
    GenerationalGCManager.instance.register(this);
  }

  /// Resumes the coroutine with the given arguments
  Future<Value> resume(List<Object?> args) async {
    Logger.debug(
      'Coroutine.resume: Called with status: $status, args: $args',
      category: 'Coroutine',
    );
    if (status == CoroutineStatus.dead) {
      Logger.debug(
        'Coroutine.resume: Coroutine is dead',
        category: 'Coroutine',
      );
      return Value.multi([Value(false), Value("cannot resume dead coroutine")]);
    }

    if (status == CoroutineStatus.running) {
      Logger.debug(
        'Coroutine.resume: Coroutine is running',
        category: 'Coroutine',
      );
      return Value.multi([
        Value(false),
        Value("cannot resume running coroutine"),
      ]);
    }

    // Get the interpreter from the environment
    final interpreter = closureEnvironment.interpreter;
    final previousCoroutine = interpreter?.getCurrentCoroutine();
    final previousEnv = interpreter?.getCurrentEnv();

    try {
      // Set this coroutine as the current one
      if (interpreter != null) {
        interpreter.setCurrentCoroutine(this);

        // When resuming from a yield, restore the saved execution environment
        if (_executionEnvironment != null) {
          interpreter.setCurrentEnv(
            _executionEnvironment,
          ); // Restore the saved environment
          Logger.debug(
            'Coroutine.resume: Restored saved execution environment: ${interpreter.getCurrentEnv()?.hashCode}',
            category: 'Coroutine',
          );
        } else {
          // For initial execution, use the coroutine's initial environment
          interpreter.setCurrentEnv(closureEnvironment);
          Logger.debug(
            'Coroutine.resume: Set initial environment: ${closureEnvironment.hashCode}',
            category: 'Coroutine',
          );
        }
      }

      if (status == CoroutineStatus.suspended && _executionTask == null) {
        // Initial execution
        Logger.debug(
          'Coroutine.resume: Initial execution',
          category: 'Coroutine',
        );
        status = CoroutineStatus.running;

        // Start the coroutine function with initial arguments
        _executionTask = _executeCoroutine(args);

        completer = Completer<List<Object?>>();
        Logger.debug(
          'Coroutine.resume: Waiting for _executionTask completion (initial)',
          category: 'Coroutine',
        );
        final result = await completer!.future;
        Logger.debug(
          'Coroutine.resume: _executionTask completed (initial)',
          category: 'Coroutine',
        );
        return Value.multi([Value(true), ...result]);
      } else if (status == CoroutineStatus.suspended) {
        // Resuming from a yield point
        Logger.debug(
          'Coroutine.resume: Resuming from yield',
          category: 'Coroutine',
        );
        status = CoroutineStatus.running;

        // Resume execution by completing the completer
        final currentCompleter = completer;
        completer = Completer<List<Object?>>();

        // Process arguments for consistency
        final processedArgs = _normalizeValues(args);

        Logger.debug(
          'Coroutine.resume: Completing previous completer with: $processedArgs',
          category: 'Coroutine',
        );
        currentCompleter?.complete(processedArgs);

        // Wait for the next yield or completion
        Logger.debug(
          'Coroutine.resume: Waiting for next yield or completion',
          category: 'Coroutine',
        );
        final result = await completer!.future;
        Logger.debug(
          'Coroutine.resume: Next yield or completion received',
          category: 'Coroutine',
        );
        return Value.multi([Value(true), ...result]);
      } else {
        // This shouldn't happen, but just in case
        Logger.debug(
          'Coroutine.resume: Unexpected state: $status',
          category: 'Coroutine',
        );
        return Value.multi([Value(false), Value("unexpected coroutine state")]);
      }
    } on YieldException catch (e) {
      Logger.debug(
        'Coroutine.resume: Caught YieldException',
        category: 'Coroutine',
      );
      // The coroutine has yielded, it's now suspended. Return the yielded values.
      status = CoroutineStatus.suspended;
      return Value.multi([Value(true), ...e.values]);
    } on ReturnException catch (e) {
      Logger.debug(
        'Coroutine.resume: Caught ReturnException',
        category: 'Coroutine',
      );
      // Normal return from the coroutine function
      status = CoroutineStatus.dead;
      return _handleReturnValue(e.value);
    } catch (e) {
      Logger.error(
        'Coroutine.resume: Caught unexpected error: $e',
        category: 'Coroutine',
      );
      // Unexpected error
      _error = e;
      status = CoroutineStatus.dead;
      return Value.multi([Value(false), Value(e.toString())]);
    } finally {
      Logger.debug(
        'Coroutine.resume: Finally block executed',
        category: 'Coroutine',
      );
      // Restore the previous coroutine and environment
      if (interpreter != null) {
        interpreter.setCurrentCoroutine(previousCoroutine);
        if (previousEnv != null) {
          interpreter.setCurrentEnv(previousEnv);
        }

        // If the previous coroutine exists, update its status
        if (previousCoroutine != null && previousCoroutine != this) {
          if (previousCoroutine.status == CoroutineStatus.normal) {
            previousCoroutine.status = CoroutineStatus.running;
          }
        }
      }
    }
  }

  /// Helper method to handle return values from coroutine
  Value _handleReturnValue(Object? value) {
    if (value == null) {
      return Value.multi([Value(true), Value(null)]);
    } else if (value is Value) {
      if (value.isMulti) {
        // Extract multiple return values
        final values = value.raw as List<Object?>;
        return Value.multi([Value(true), ...values]);
      } else {
        // Single return value
        return Value.multi([Value(true), value]);
      }
    } else {
      // Wrap raw value
      return Value.multi([Value(true), Value(value)]);
    }
  }

  /// Yields from the coroutine with the given values
  Future<List<Object?>> yield_(List<Object?> values) async {
    if (status != CoroutineStatus.running) {
      throw Exception("attempt to yield from outside a coroutine");
    }

    // Save the current execution environment before yielding
    final interpreter = closureEnvironment.interpreter;
    if (interpreter != null) {
      _executionEnvironment = interpreter.getCurrentEnv();
      Logger.debug(
        'Coroutine.yield_: Saved current execution environment: ${_executionEnvironment?.hashCode}',
        category: 'Coroutine',
      );
    }

    // Set status to suspended
    status = CoroutineStatus.suspended;

    // Complete the current completer with the yielded values
    final currentCompleter = completer;
    completer = Completer<List<Object?>>();

    if (currentCompleter != null && !currentCompleter.isCompleted) {
      // Normalize values before yielding
      final normalizedValues = _normalizeValues(values);
      currentCompleter.complete(normalizedValues);
    }

    // Throw YieldException to pause execution and return control
    throw YieldException(
      values.cast<Value>(), // Cast to List<Value>
      completer!.future, // The future to await on next resume
    );
  }

  /// Normalize values for consistency between yields and resumes
  List<Object?> _normalizeValues(List<Object?> values) {
    final result = <Object?>[];

    for (final value in values) {
      if (value is Value && value.isMulti) {
        // Expand multi-value into individual values
        result.addAll(
          (value.raw as List<Object?>).map((v) => v is Value ? v : Value(v)),
        );
      } else if (value is List && values.length == 1) {
        // Special case: if the only argument is a list, it might be multi-return values
        // that need to be expanded
        result.addAll(value.map((v) => v is Value ? v : Value(v)));
      } else {
        // Regular value, ensure it's wrapped
        result.add(value is Value ? value : Value(value));
      }
    }

    return result;
  }

  /// Executes the coroutine function
  Future<void> _executeCoroutine(List<Object?> initialArgs) async {
    Logger.debug(
      '_executeCoroutine: Starting execution, PC: $_programCounter',
      category: 'Coroutine',
    );
    // Create initial environment for function parameters and locals
    final interpreter = closureEnvironment.interpreter;

    // No null check for functionBody needed here, as it's now non-nullable

    // Process arguments for the function call
    final processedArgs =
        initialArgs.map((arg) {
          return arg is Value ? arg : Value(arg);
        }).toList();

    // Bind regular parameters
    final hasVarargs = functionBody.isVararg;
    int regularParamCount = functionBody.parameters?.length ?? 0;

    for (var i = 0; i < regularParamCount; i++) {
      final paramName = (functionBody.parameters![i] as Identifier).name;
      if (i < processedArgs.length) {
        _executionEnvironment.define(
          paramName,
          processedArgs[i] is Value
              ? processedArgs[i]
              : Value(processedArgs[i]),
        );
      } else {
        _executionEnvironment.define(paramName, Value(null));
      }
    }

    // Handle varargs if present
    if (hasVarargs) {
      List<Object?> varargs =
          processedArgs.length > regularParamCount
              ? processedArgs.sublist(regularParamCount)
              : [];
      _executionEnvironment.define("...", Value.multi(varargs));
    }

    try {
      // Execute statements from the current program counter
      for (; _programCounter < functionBody.body.length; _programCounter++) {
        final stmt = functionBody.body[_programCounter];

        Logger.debug(
          '_executeCoroutine: Executing statement $_programCounter: ${stmt.runtimeType}',
          category: 'Coroutine',
        );
        // Ensure the interpreter's environment is set to this coroutine's execution environment
        if (interpreter != null) {
          interpreter.setCurrentEnv(_executionEnvironment);
        }

        await stmt.accept(interpreter!); // Execute the statement
        Logger.debug(
          '_executeCoroutine: Statement $_programCounter executed. Current PC: $_programCounter',
          category: 'Coroutine',
        );
      }

      // Coroutine completed normally
      Logger.debug(
        '_executeCoroutine: Coroutine completed normally',
        category: 'Coroutine',
      );
      status = CoroutineStatus.dead;
      if (completer != null && !completer!.isCompleted) {
        // Pass empty list as result for normal completion
        completer!.complete([]);
        Logger.debug(
          '_executeCoroutine: Completer completed with empty list',
          category: 'Coroutine',
        );
      }
    } on YieldException catch (e) {
      Logger.debug(
        '_executeCoroutine: Caught YieldException',
        category: 'Coroutine',
      );
      // YieldException is thrown by yield_ to pause execution.
      // It should be re-thrown here so resume can catch it and manage state.
      rethrow;
    } on ReturnException catch (e) {
      Logger.debug(
        '_executeCoroutine: Caught ReturnException',
        category: 'Coroutine',
      );
      // Normal return from the coroutine function
      status = CoroutineStatus.dead;
      if (completer != null && !completer!.isCompleted) {
        final handledResult = _handleReturnValue(e.value);
        if (handledResult.isMulti) {
          completer!.complete(handledResult.raw as List<Object?>);
        } else {
          completer!.complete([handledResult.raw]);
        }
        Logger.debug(
          '_executeCoroutine: Completer completed with return value',
          category: 'Coroutine',
        );
      }
    } catch (e) {
      _error = e;
      Logger.error('Error in _executeCoroutine: $e', category: 'Coroutine');
      // Set status to dead on unhandled exceptions
      status = CoroutineStatus.dead;
      if (completer != null && !completer!.isCompleted) {
        completer!.complete([
          Value(false),
          Value(e.toString()),
        ]); // Return error to caller
        Logger.debug(
          '_executeCoroutine: Completer completed with error',
          category: 'Coroutine',
        );
      }
    }
  }

  /// Called to close the coroutine
  Future<List<Object?>> close([dynamic error]) async {
    if (status == CoroutineStatus.dead) {
      Logger.debug(
        'Coroutine already dead, nothing to close',
        category: 'Coroutine',
      );
      return [Value(true)]; // Already dead, consider it successful close
    }

    Logger.debug(
      'Closing coroutine with status: $status',
      category: 'Coroutine',
    );

    // If there's an active execution task, complete its completer with an error
    // so that the awaited future in resume() will throw
    if (completer != null && !completer!.isCompleted) {
      if (error != null) {
        completer!.completeError(error);
      } else {
        // If no error, complete normally but signal termination
        completer!.complete([]); // Signal normal termination for yield future
      }
    }

    // Set status to dead
    status = CoroutineStatus.dead;

    // Propagate the error if provided
    if (error != null) {
      if (error is LuaError) {
        return [Value(false), Value(error.message)];
      } else {
        return [Value(false), Value(error.toString())];
      }
    }

    return [Value(true)]; // Successful close
  }

  /// Mark the coroutine as dead and release resources
  void markAsDead() {
    status = CoroutineStatus.dead;
    completer = null;
    _executionTask = null;
  }

  /// Check if this coroutine is yieldable
  bool isYieldable(Coroutine mainThread) {
    // A coroutine is yieldable if it's not the main thread
    return this != mainThread;
  }

  @override
  List<GCObject> getReferences() {
    final refs = <GCObject>[];
    refs.add(functionValue);
    refs.add(closureEnvironment);
    refs.add(_executionEnvironment);
    // if (_originalArgs != null) {
    //   refs.addAll(_originalArgs!);
    // }
    return refs;
  }

  @override
  void free() {
    // Clean up resources
    completer = null;
    _executionTask = null;
  }

  /// Records an error that occurred in the coroutine
  void recordError(Object error, StackTrace trace) {
    _error = error;
  }

  @override
  String toString() {
    return 'Coroutine(status: $status)';
  }

  /// Resets the coroutine to its initial state for reuse.
  void reset() {
    status = CoroutineStatus.suspended;
    completer = null;
    _executionTask = null;
    _programCounter = 0; // Reset program counter
    // _executionEnvironment should be re-initialized from closureEnvironment
    // or explicitly cleared if not reused directly.
  }
}
