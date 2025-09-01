import 'dart:async';
import 'dart:convert';

import 'package:lualike/src/ast.dart';
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/const_checker.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/stdlib/lib_debug.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/utils/file_system_utils.dart' as fs;
import 'package:path/path.dart' as path;

/// Wrapper for Dart functions to make them callable from LuaLike.
///
/// Provides a bridge between Dart functions and the LuaLike runtime,
/// handling argument conversion and function calling conventions.
class DartFunction implements BuiltinFunction {
  /// The wrapped Dart function.
  final Function dartFunction;

  /// Creates a new DartFunction wrapping the given Dart function.
  DartFunction(this.dartFunction);

  @override
  Object? call(List<Object?> args) {
    try {
      // First try calling directly with the args list
      final result = dartFunction(args);
      return result is Value ? result : Value(result);
    } catch (_) {
      try {
        // If that fails, try calling with spread arguments
        final unwrappedArgs = args.map((arg) {
          if (arg is Value) return arg.raw;
          return arg;
        }).toList();

        final result = Function.apply(dartFunction, unwrappedArgs);
        return result is Value ? result : Value(result);
      } catch (e) {
        throw Exception("Failed to call Dart function: $e");
      }
    }
  }
}

/// Extension methods for the VM to add Dart interop capabilities
extension VMInterop on Interpreter {
  /// Registers a Dart function to be callable from LuaLike.
  ///
  /// The function should either:
  /// 1. Accept a `List<Object?>` as its only parameter, or
  /// 2. Accept individual parameters that will be spread from the args list
  ///
  /// [name] - The name to register the function under
  /// [function] - The Dart function to expose
  void expose(String name, Function function) {
    globals.define(name, DartFunction(function));
  }

  /// Register a Dart function to be callable from LuaLike
  void registerDartFunction(String name, Function function) {
    globals.define(name, DartFunction(function));
  }

  /// Evaluates a LuaLike expression from Dart.
  ///
  /// [code] - The LuaLike code to evaluate
  /// [scriptPath] - Optional path of the script being executed
  /// Returns the result of the evaluation
  Future<Object?> evaluate(String code, {String? scriptPath}) async {
    final ast = parse(code, url: scriptPath); // Assuming parse() is available

    // Check for const variable assignment errors
    final constChecker = ConstChecker();
    final constError = constChecker.checkConstViolations(ast);
    if (constError != null) {
      throw Exception(constError);
    }

    // Store the script path in the interpreter
    if (scriptPath != null) {
      // Use absolute path to ensure consistency
      String absolutePath;

      if (path.isAbsolute(scriptPath)) {
        absolutePath = scriptPath;
      } else {
        // Resolve relative paths against the current working directory
        try {
          final currentDir = fs.getCurrentDirectory();
          if (currentDir != null) {
            absolutePath = path.normalize(path.join(currentDir, scriptPath));
          } else {
            absolutePath = path.absolute(scriptPath);
          }
          Logger.debug(
            "Resolved relative script path '$scriptPath' to absolute path '$absolutePath' using current directory",
            category: 'Interpreter',
          );
        } catch (e) {
          // Fallback to simple absolute path
          absolutePath = path.absolute(scriptPath);
          Logger.debug(
            "Error resolving script path: $e, using $absolutePath",
            category: 'Interpreter',
          );
        }
      }

      currentScriptPath = absolutePath;

      // Also store it in the global environment as _SCRIPT_PATH and _SCRIPT_DIR
      globals.define('_SCRIPT_PATH', Value(absolutePath));

      // Get the directory part of the script path
      final scriptDir = path.dirname(absolutePath);
      globals.define('_SCRIPT_DIR', Value(scriptDir));

      Logger.debug(
        "Set script path globals: _SCRIPT_PATH=$absolutePath, _SCRIPT_DIR=$scriptDir",
        category: 'Interpreter',
      );

      // Ensure the script directory is in the file manager's search paths
      // Add it at the beginning to prioritize it
      fileManager.addSearchPath(scriptDir);
    }

    // Just call run() directly and let any errors propagate up
    return run(ast.statements);
  }

  /// Calls a LuaLike function from Dart.
  ///
  /// [functionName] - The name of the function to call
  /// [args] - The arguments to pass to the function
  /// Returns the result of the function call
  Future<Object?> callFunction(String functionName, List<Object?> args) async {
    // Create function call AST node
    final call = FunctionCall(
      Identifier(functionName),
      args.map((arg) {
        // Convert Dart values to LuaLike AST nodes
        if (arg is num) return NumberLiteral(arg);
        if (arg is String) return StringLiteral(arg);
        if (arg is bool) return BooleanLiteral(arg);
        if (arg == null) return NilValue();
        throw LuaError('Unsupported argument type: ${arg.runtimeType}');
      }).toList(),
    );

    // Execute the function call
    return await call.accept(this);
  }
}

/// Bridge class to manage Dart-LuaLike interop.
///
/// Provides a high-level interface for interacting with LuaLike code from Dart,
/// including function registration, code execution, and value exchange.
class LuaLike {
  /// The underlying LuaLike interpreter instance.
  final Interpreter vm;

  /// Creates a new bridge with a fresh interpreter instance.
  /// If an instance already exists, returns that instance.
  factory LuaLike() => LuaLike._internal();

  /// Internal constructor
  LuaLike._internal() : vm = Interpreter();

  /// Register a Dart function to be callable from LuaLike
  void expose(String name, Function function) {
    vm.registerDartFunction(name, function);
  }

  /// Run LuaLike code
  ///
  /// [code] - The LuaLike code to run
  /// [scriptPath] - Optional path of the script being executed
  /// This method ensures proper line tracking by setting the script path
  /// and ensuring the debug library has access to the interpreter
  Future<Object?> execute(String code, {String? scriptPath}) async {
    try {
      // Set the interpreter reference in the environment
      // This ensures debug.getinfo can access the interpreter for line info
      vm.globals.interpreter = vm;
      
      // Ensure the debug library has a reference to the interpreter
      final debugLib = vm.globals.get('debug');
      if (debugLib != null && debugLib.isTable) {
        // Reinitialize debug library with the interpreter reference
        defineDebugLibrary(env: vm.globals, astVm: vm);
        Logger.debug(
          'Updated debug library with interpreter reference',
          category: 'LineTracking'
        );
      }
      
      // Use our evaluate method to handle line tracking correctly
      final result = await evaluate(code, scriptPath: scriptPath);

      // If a multi-value was returned, unwrap it into a Dart List so callers
      // receive a simple List<Value> like the top-level runCode helper.
      if (result is Value && result.isMulti && result.raw is List) {
        return (result.raw as List)
            .map((e) => e is Value ? e : Value(e))
            .toList();
      }

      return result;
    } catch (e) {
      // Log the error and rethrow
      Logger.error("Error executing code: $e");
      rethrow;
    }
  }

  /// Evaluate LuaLike code and handle line information correctly
  ///
  /// This method is used internally by execute to parse and evaluate the code
  /// while ensuring line information is correctly set
  Future<Object?> evaluate(String code, {String? scriptPath}) async {
    try {
      // Parse the code to generate AST with line information
      final program = parse(code, url: scriptPath);
      
      // Set script path in environment if provided
      if (scriptPath != null) {
        vm.globals.define('_SCRIPT_PATH', Value(scriptPath));
        vm.callStack.setScriptPath(scriptPath);
      }
      
      // Run the program statements with line tracking
      return await vm.run(program.statements);
    } catch (e) {
      Logger.error("Error evaluating code: $e");
      rethrow;
    }
  }

  /// Get a value from LuaLike global environment
  /// Returns the raw Value object (not unwrapped)
  Object? getGlobal(String name) {
    final value = vm.globals.get(name);
    // Already a Value or null
    return value;
  }

  /// Set a value in LuaLike global environment
  void setGlobal(String name, Object? value) {
    vm.globals.define(name, value is Value ? value : Value(value));
  }

  /// Call a LuaLike function from Dart
  Future<Object?> call(String functionName, List<Object?> args) {
    return vm.callFunction(Value(functionName), args);
  }

  void throwError([String? message]) {
    vm.reportError(
      message ?? "thrown",
      trace: StackTrace.current,
      error: Exception(message),
      node: null,
    );
  }
}

/// Runs a Lua file with the given path.
Future<List<Value>> runFile(String path, {Map<String, dynamic>? env}) async {
  if (!await fs.fileExists(path)) {
    throw Exception('File not found: $path');
  }
  final bytes = await fs.readFileAsBytes(path);
  if (bytes == null) {
    throw Exception('Could not read file: $path');
  }
  final code = utf8.decode(bytes);

  // Create a new environment if one wasn't provided
  env ??= {};

  // Set the script path in the environment
  env['_SCRIPT_PATH'] = path;

  // Mark this as the main chunk
  env['_MAIN_CHUNK'] = true;

  return runCode(code, filePath: path, env: env);
}

/// Runs Lua code with the given environment.
Future<List<Value>> runCode(
  String code, {
  String? filePath,
  Map<String, dynamic>? env,
}) async {
  final interpreter = Interpreter();

  // Create a new environment if one wasn't provided
  env ??= {};

  // Set the script path in the environment if provided
  if (filePath != null) {
    env['_SCRIPT_PATH'] = filePath;
  }

  // Mark this as the main chunk if it's being run directly
  env['_MAIN_CHUNK'] = true;

  // Initialize the environment by setting globals
  for (final entry in env.entries) {
    interpreter.globals.define(entry.key, Value(entry.value));
  }

  // Parse and evaluate the code
  final result = await interpreter.evaluate(code, scriptPath: filePath);

  // Convert the result to a List<Value>
  if (result is List) {
    return result.map((item) => item is Value ? item : Value(item)).toList();
  } else if (result != null) {
    return [result is Value ? result : Value(result)];
  } else {
    return [];
  }
}

/// Loads a Lua script from a file.
Future<Value> loadFile(String path) async {
  try {
    if (!await fs.fileExists(path)) {
      throw LuaError.typeError('File not found: $path');
    }
    final bytes = await fs.readFileAsBytes(path);
    if (bytes == null) {
      throw LuaError.typeError('Could not read file: $path');
    }
    final content = utf8.decode(bytes);
    // runCode returns a list, loadFile should return the first result or nil
    final results = await runCode(content, filePath: path);
    return results.isNotEmpty ? results[0] : Value(null);
  } catch (e) {
    if (e is LuaError) {
      rethrow;
    }
    throw LuaError.typeError('Error loading file: $e');
  }
}
