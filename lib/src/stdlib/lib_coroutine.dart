import 'package:lualike/src/coroutine.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/logger.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';
import 'package:lualike/src/lua_error.dart';

/// Initialize the coroutine library and add it to the global environment
void initializeCoroutineLibrary(Interpreter interpreter) {
  Logger.debug('Initializing coroutine library', category: 'Coroutine');

  // Create coroutine table
  final coroutineLib = ValueClass.table();

  // coroutine.create(f)
  coroutineLib[Value("create")] = Value((List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("coroutine.create expects a function argument");
    }

    final func = args[0];
    if (func is! Value || !func.isCallable()) {
      throw LuaError.typeError("coroutine.create expects a function argument");
    }

    // Ensure that the raw value of the function is a FunctionBody AST node
    if (func.functionBody == null) {
      throw LuaError.typeError(
        "coroutine.create expects a Lua function (FunctionBody AST node)",
      );
    }

    // Create a new coroutine with the current environment and interpreter reference
    final co = Coroutine(
      func,
      func.functionBody!,
      interpreter.globals.clone(interpreter: interpreter),
    );
    Logger.debug('Created new coroutine', category: 'Coroutine');

    // Register with interpreter
    interpreter.registerCoroutine(co);

    // Return the coroutine wrapped in a Value
    return Value(co);
  });

  // coroutine.resume(co [, val1, ...])
  coroutineLib[Value("resume")] = Value((List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("coroutine.resume expects a coroutine argument");
    }

    final value = args[0];
    final co = value is Value ? value.raw : value;

    if (co is! Coroutine) {
      throw LuaError.typeError("coroutine.resume expects a coroutine argument");
    }

    Logger.debug('Calling resume on coroutine', category: 'Coroutine');

    // Save current coroutine and environment state
    final previousCoroutine = interpreter.getCurrentCoroutine();
    final previousEnv = interpreter.getCurrentEnv();
    if (previousCoroutine != null && previousCoroutine != co) {
      previousCoroutine.status = CoroutineStatus.normal;
    }

    // Set the new coroutine as current
    interpreter.setCurrentCoroutine(co);

    try {
      // Resume the coroutine with the remaining arguments
      final resumeArgs = args.length > 1 ? args.sublist(1) : [];
      final result = await co.resume(resumeArgs);

      // Check if the result is a multi-value and flatten it if it is
      final multiResult = Value.multi(
        result.raw is List ? result.raw as List<Object?> : [result.raw],
      );

      // Log for debugging
      Logger.debug(
        'Coroutine.resume result: \\$multiResult',
        category: 'CoroutineLib',
      );

      // Return the result as-is
      return multiResult;
    } finally {
      // Restore the previous coroutine
      interpreter.setCurrentCoroutine(previousCoroutine);
      if (previousCoroutine != null) {
        previousCoroutine.status = CoroutineStatus.running;
      }
      // Restore the previous environment
      interpreter.setCurrentEnv(previousEnv);
    }
  });

  // coroutine.yield([val1, ...])
  coroutineLib[Value("yield")] = Value((List<Object?> args) async {
    if (!interpreter.isYieldable) {
      throw LuaError.typeError("attempt to yield across a C boundary");
    }

    Logger.debug(
      '>>> coroutine.yield called with args: $args',
      category: 'Coroutine',
    );

    final currentCoroutine = interpreter.getCurrentCoroutine();
    final mainThread = interpreter.getMainThread();

    Logger.debug(
      '>>> Current coroutine: ${currentCoroutine?.hashCode}, main thread: ${interpreter.getMainThread().hashCode}',
      category: 'Coroutine',
    );
    // The issue is that we're checking if currentCoroutine == interpreter.getMainThread()
    // But when using the same environment, this check might not work correctly
    // Instead, we should check the coroutine's status
    if (currentCoroutine == null || currentCoroutine == mainThread) {
      throw LuaError.typeError("attempt to yield from main thread");
    }

    if (currentCoroutine.status != CoroutineStatus.running) {
      Logger.debug(
        '>>> Attempt to yield from non-running coroutine (status: ${currentCoroutine.status})',
        category: 'Coroutine',
      );
      throw LuaError.typeError("attempt to yield from non-running coroutine");
    }

    // Save the current environment
    final currentEnv = interpreter.getCurrentEnv();
    Logger.debug(
      '>>> Current environment before yield: ${currentEnv.hashCode}',
      category: 'Coroutine',
    );

    try {
      // Yield the values
      Logger.debug(
        '>>> About to call yield_ on coroutine: ${currentCoroutine.hashCode}',
        category: 'Coroutine',
      );

      final result = await currentCoroutine.yield_(args);

      Logger.debug(
        '>>> coroutine.yield received resume values: $result',
        category: 'Coroutine',
      );

      // Handle the return values
      if (result.isEmpty) {
        Logger.debug(
          '>>> coroutine.yield returning nil',
          category: 'Coroutine',
        );
        return Value(null);
      } else if (result.length == 1) {
        Logger.debug(
          '>>> coroutine.yield returning single value: ${result[0]}',
          category: 'Coroutine',
        );
        return result[0];
      } else {
        Logger.debug(
          '>>> coroutine.yield returning multiple values: $result',
          category: 'Coroutine',
        );
        return Value.multi(result);
      }
    } finally {
      // The interpreter environment will be restored by Coroutine.resume
      // after the yield completes.
    }
  });

  // coroutine.status(co)
  coroutineLib[Value("status")] = Value((List<Object?> args) async {
    if (args.isEmpty ||
        args[0] is! Value ||
        (args[0] as Value).raw is! Coroutine) {
      throw LuaError.typeError("coroutine.status expects a coroutine argument");
    }

    final co = (args[0] as Value).raw as Coroutine;
    final currentCoroutine = interpreter.getCurrentCoroutine();

    // Debugging: Log current coroutine and status
    Logger.debug(
      'coroutine.status: Querying co: ${co.hashCode} (status: ${co.status}), currentCoroutine: ${currentCoroutine?.hashCode}',
      category: 'Coroutine',
    );

    // Special case: if this coroutine is the one calling status, and its internal status
    // is suspended, it means it's currently running (resumed).
    if (co == currentCoroutine && co.status == CoroutineStatus.suspended) {
      Logger.debug(
        'coroutine.status: co is current and suspended, reporting running',
        category: 'Coroutine',
      );
      return Value("running");
    }

    // Return status based on enum
    switch (co.status) {
      case CoroutineStatus.suspended:
        return Value("suspended");
      case CoroutineStatus.running:
        return Value("running");
      case CoroutineStatus.normal:
        return Value("normal");
      case CoroutineStatus.dead:
        return Value("dead");
    }
  });

  // coroutine.wrap(f)
  coroutineLib[Value("wrap")] = Value((List<Object?> args) async {
    if (args.isEmpty) {
      throw LuaError.typeError("coroutine.wrap expects a function argument");
    }

    final func = args[0];
    if (func is! Value || !func.isCallable()) {
      throw LuaError.typeError("coroutine.wrap expects a function argument");
    }

    Logger.debug('>>> Creating wrapped coroutine', category: 'Coroutine');

    Logger.debug(
      '>>> Current environment: ${interpreter.getCurrentEnv().hashCode}',
      category: 'Coroutine',
    );

    Logger.debug(
      '>>> Main thread: ${interpreter.getMainThread().hashCode}',
      category: 'Coroutine',
    );

    Logger.debug(
      '>>> Current coroutine: ${interpreter.getCurrentCoroutine()?.hashCode}',
      category: 'Coroutine',
    );

    // Create a new environment for the coroutine that inherits from the current environment
    // This ensures proper behavior for tail calls and global access
    final env = interpreter.getCurrentEnv().clone(interpreter: interpreter);

    Logger.debug(
      '>>> Created cloned environment: ${env.hashCode}',
      category: 'Coroutine',
    );

    final coroutine = Coroutine(func, func.functionBody!, env);
    Logger.debug(
      '>>> Created coroutine: ${coroutine.hashCode}',
      category: 'Coroutine',
    );

    interpreter.registerCoroutine(coroutine);
    Logger.debug(
      '>>> Registered coroutine with interpreter',
      category: 'Coroutine',
    );

    // Return a function that resumes the coroutine
    return Value((List<Object?> resumeArgs) async {
      Logger.debug(
        '>>> Wrapped coroutine function called with args: $resumeArgs',
        category: 'Coroutine',
      );

      Logger.debug(
        '>>> Current environment: ${interpreter.getCurrentEnv().hashCode}',
        category: 'Coroutine',
      );

      Logger.debug(
        '>>> Current coroutine: ${interpreter.getCurrentCoroutine()?.hashCode}',
        category: 'Coroutine',
      );

      Logger.debug(
        '>>> Coroutine status: ${coroutine.status}',
        category: 'Coroutine',
      );

      // Save the current coroutine and environment
      final previousCoroutine = interpreter.getCurrentCoroutine();
      final previousEnv = interpreter.getCurrentEnv();

      // Set the coroutine as the current one
      interpreter.setCurrentCoroutine(coroutine);

      // Set the coroutine's environment as the current one
      interpreter.setCurrentEnv(env);

      Logger.debug(
        '>>> Set current coroutine to: ${coroutine.hashCode} with status: ${coroutine.status}',
        category: 'Coroutine',
      );

      Logger.debug(
        '>>> Set current environment to: ${env.hashCode}',
        category: 'Coroutine',
      );

      try {
        // Resume the coroutine with the arguments
        Logger.debug(
          '>>> About to resume coroutine: ${coroutine.hashCode}',
          category: 'Coroutine',
        );

        final result = await coroutine.resume(resumeArgs);
        Logger.debug(
          '>>> Wrapped coroutine resume result: $result',
          category: 'Coroutine',
        );
        Logger.debug(
          '>>> Wrapped Coroutine status after resume: ${coroutine.status}',
          category: 'Coroutine',
        );

        // Check for errors (first value is false)
        if ((result.raw as List<Object?>)[0] is Value &&
            ((result.raw as List<Object?>)[0] as Value).raw == false) {
          // Propagate the error, closing the coroutine
          Logger.debug(
            '>>> Error detected in coroutine result, closing coroutine',
            category: 'Coroutine',
          );

          await coroutine.close();
          throw LuaError.typeError((result.raw as List<Object?>)[1].toString());
        }

        // Return all values except the first (success indicator)
        if ((result.raw as List<Object?>).length == 2) {
          Logger.debug(
            '>>> Wrapped coroutine returning single value: \\${(result.raw as List<Object?>)[1]}',
            category: 'Coroutine',
          );
          print(
            '[LUALIKE] Wrapped coroutine returning single value: \\${(result.raw as List<Object?>)[1]}',
          );

          return (result.raw as List<Object?>)[1]
              as Value; // Return single value directly
        } else if ((result.raw as List<Object?>).length > 2) {
          // Access the raw list before calling sublist
          final rawResult = result.raw as List<Object?>;
          Logger.debug(
            '>>> Wrapped coroutine returning multiple values: \\${rawResult.sublist(1)}',
            category: 'CoroutineLib',
          );
          return Value.multi(rawResult.sublist(1)); // Return multiple values
        }

        Logger.debug(
          '>>> Wrapped coroutine returning nil',
          category: 'Coroutine',
        );
        print('[LUALIKE] Wrapped coroutine returning nil');

        return Value(null); // Return nil if no values
      } finally {
        // Restore the previous coroutine and environment
        interpreter.setCurrentCoroutine(previousCoroutine);
        interpreter.setCurrentEnv(previousEnv);

        Logger.debug(
          '>>> Restored previous coroutine: ${previousCoroutine?.hashCode}',
          category: 'Coroutine',
        );
      }
    });
  });

  // coroutine.running()
  coroutineLib[Value("running")] = Value((List<Object?> args) async {
    final currentCoroutine = interpreter.getCurrentCoroutine();
    final mainThread = interpreter.getMainThread();

    if (currentCoroutine == null) {
      // Should not happen, but just in case
      return Value.multi([Value(mainThread), Value(true)]);
    }

    // Return the running coroutine and whether it's the main thread
    return Value.multi([
      Value(currentCoroutine),
      Value(currentCoroutine == mainThread),
    ]);
  });

  // coroutine.isyieldable([co])
  coroutineLib[Value("isyieldable")] = Value((List<Object?> args) async {
    Coroutine coroutine;

    if (args.isEmpty) {
      // Use the current coroutine by default
      coroutine =
          interpreter.getCurrentCoroutine() ?? interpreter.getMainThread();
    } else if (args[0] is Value && (args[0] as Value).raw is Coroutine) {
      coroutine = (args[0] as Value).raw as Coroutine;
    } else {
      throw LuaError.typeError(
        "coroutine.isyieldable expects a coroutine argument",
      );
    }

    final mainThread = interpreter.getMainThread();
    return Value(coroutine.isYieldable(mainThread));
  });

  // coroutine.close(co)
  coroutineLib[Value("close")] = Value((List<Object?> args) async {
    if (args.isEmpty ||
        args[0] is! Value ||
        (args[0] as Value).raw is! Coroutine) {
      throw LuaError.typeError("coroutine.close expects a coroutine argument");
    }

    final co = (args[0] as Value).raw as Coroutine;

    if (co.status == CoroutineStatus.running) {
      throw LuaError.typeError("Cannot close running coroutine");
    }

    final result = await co.close();
    return Value.multi(result);
  });

  // Add to global environment
  interpreter.globals.define("coroutine", coroutineLib);
}
