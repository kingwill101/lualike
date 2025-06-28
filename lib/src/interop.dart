import 'dart:async';
import 'dart:io';

import 'package:lualike/src/testing/testing.dart';
import 'package:path/path.dart' as path;
import 'package:lualike/lualike.dart';
import 'package:lualike/src/utils/platform_utils.dart';

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
        final unwrappedArgs =
            args.map((arg) {
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

    // Store the script path in the interpreter
    if (scriptPath != null) {
      // Use absolute path to ensure consistency
      String absolutePath;

      if (path.isAbsolute(scriptPath)) {
        absolutePath = scriptPath;
      } else {
        // If it's a relative path, try to make it absolute
        try {
          // In product mode (compiled executable), don't use Platform.script
          if (isProductMode) {
            absolutePath = path.absolute(scriptPath);
            Logger.debug(
              "Running as compiled executable, using absolute path: $absolutePath",
              category: 'Interpreter',
            );
          } else {
            // Try to use Platform.script in development mode
            final dartScriptDir =
                Platform.script.toFilePath() != ''
                    ? path.dirname(Platform.script.toFilePath())
                    : Directory.current.path;
            absolutePath = path.normalize(path.join(dartScriptDir, scriptPath));
            Logger.debug(
              "Resolved relative script path '$scriptPath' to absolute path '$absolutePath' using Dart script path",
              category: 'Interpreter',
            );
          }
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
        throw ArgumentError('Unsupported argument type: ${arg.runtimeType}');
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
class LuaLikeBridge {
  /// The underlying LuaLike interpreter instance.
  final Interpreter vm;

  /// Creates a new bridge with a fresh interpreter instance.
  /// If an instance already exists, returns that instance.
  factory LuaLikeBridge() => LuaLikeBridge._internal();

  /// Internal constructor
  LuaLikeBridge._internal() : vm = Interpreter() {
    Logger.setEnabled(loggingEnabled);
  }

  /// Register a Dart function to be callable from LuaLike
  void expose(String name, Function function) {
    vm.registerDartFunction(name, function);
  }

  /// Run LuaLike code
  ///
  /// [code] - The LuaLike code to run
  /// [scriptPath] - Optional path of the script being executed
  Future<Object?> runCode(String code, {String? scriptPath}) async {
    // Just pass through to the interpreter's evaluate method
    // Don't catch errors here - let them propagate up
    return vm.evaluate(code, scriptPath: scriptPath);
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

  throwError([String? message]) {
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
  final file = File(path);
  if (!await file.exists()) {
    throw Exception('File not found: $path');
  }
  final code = await file.readAsString();

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

/// Calls a Dart function with the given arguments.
Future<Object?> _callDartFunction(
  Function dartFunction,
  List<Object?> args,
) async {
  try {
    final unwrappedArgs =
        args.map((arg) {
          if (arg is Value) return arg.raw;
          return arg;
        }).toList();

    final result = Function.apply(dartFunction, unwrappedArgs);
    return result is Value ? result : Value(result);
  } catch (e) {
    throw LuaError.typeError("Failed to call Dart function: $e");
  }
}

/// Converts a Dart value to a Lua value.
Value _convertToLuaValue(dynamic value) {
  if (value == null) {
    return Value(null);
  } else if (value is Value) {
    return value;
  } else if (value is num || value is String || value is bool) {
    return Value(value);
  } else if (value is List) {
    final table = <dynamic, dynamic>{};
    for (var i = 0; i < value.length; i++) {
      table[i + 1] = _convertToLuaValue(value[i]);
    }
    return Value(table);
  } else if (value is Map) {
    final table = <dynamic, dynamic>{};
    value.forEach((key, val) {
      table[_convertToLuaValue(key)] = _convertToLuaValue(val);
    });
    return Value(table);
  } else if (value is Function) {
    return Value(value);
  } else {
    throw LuaError.typeError('Unsupported argument type: ${value.runtimeType}');
  }
}

/// Loads a Lua script from a file.
Future<Value> loadFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      throw LuaError.typeError('File not found: $path');
    }
    final content = await file.readAsString();
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
