import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart' show GCObject;
import 'package:lualike/src/gc/generational_gc.dart' show GenerationalGCManager;

/// A generic box class that wraps a single value of type T.
/// Used to create mutable references to values in the environment.
class Box<T> extends GCObject {
  /// The wrapped value.
  T value;

  /// Whether this binding represents a local variable.
  final bool isLocal;

  /// Creates a new Box containing [value].
  Box(this.value, {this.isLocal = false}) {
    GenerationalGCManager.instance.register(this);
    Logger.debug(
      'Created new Box($value) and registered with GC',
      category: 'GC',
    );
  }

  @override
  List<GCObject> getReferences() {
    return value is GCObject ? [value as GCObject] : [];
  }

  @override
  String toString() => 'Box($value)';
}

/// Represents a scope for variable bindings in the interpreter.
///
/// An Environment maintains a mapping of variable names to their values and can be
/// chained to parent environments to implement lexical scoping. It supports
/// variable definition, assignment, and lookup through the scope chain.
class Environment extends GCObject {
  /// Storage for variable bindings in this scope.
  final Map<String, Box<dynamic>> values = {};

  /// Tracks the order in which to-be-closed variables were declared
  final List<String> toBeClosedVars = [];

  /// The parent environment in the scope chain, if any.
  final Environment? parent;

  /// Whether this environment represents a closure scope.
  ///
  /// When true, variable assignments will first check this environment before
  /// traversing the parent chain.
  final bool isClosure;

  /// The interpreter associated with this environment.
  Interpreter? interpreter;

  /// Creates a new Environment.
  ///
  /// If [parent] is provided, this environment will be chained to it.
  /// If [isClosure] is true, this environment will be treated as a closure scope.
  Environment({this.parent, this.interpreter, this.isClosure = false}) {
    Logger.debug(
      "Environment($hashCode) created. Parent: ${parent?.hashCode}",
      category: 'Env',
    );
  }

  @override
  List<GCObject> getReferences() {
    final refs = <GCObject>[];
    if (parent != null) {
      refs.add(parent!);
    }
    values.forEach((key, box) {
      if (box.value is GCObject) {
        refs.add(box.value as GCObject);
      }
    });
    return refs;
  }

  /// Returns a string representation of the environment chain.
  ///
  /// The chain is represented as a series of environment hash codes connected
  /// by arrows, starting from this environment and following parent links.
  String _getEnvironmentChain() {
    var chain = "$hashCode";
    var current = parent;
    while (current != null) {
      chain += " -> ${current.hashCode}";
      current = current.parent;
    }
    return chain;
  }

  /// Checks if a variable exists in this environment or any of its ancestors.
  ///
  /// Returns true if the variable is found anywhere in the environment chain.
  bool contains(String name) {
    Logger.debug(
      "Checking if '$name' exists in env ($hashCode)",
      category: 'Env',
    );

    // Check current environment
    if (values.containsKey(name)) {
      Logger.debug(
        "Variable '$name' found in current env ($hashCode)",
        category: 'Env',
      );
      return true;
    }

    // Check parent environments
    if (parent != null) {
      Logger.debug(
        "Variable '$name' not found in current env, checking parent env (${parent!.hashCode})",
        category: 'Env',
      );
      return parent!.contains(name);
    }

    Logger.debug(
      "Variable '$name' not found in any environment in chain: ${_getEnvironmentChain()}",
      category: 'Env',
    );
    return false;
  }

  /// Looks up the value of a variable named [name] in this environment.
  ///
  /// Searches through the environment chain until the variable is found.
  /// Returns null if the variable is not found in any environment.
  dynamic get(String name) {
    Logger.debug("Looking for '$name' in env ($hashCode)}", category: 'Env');
    Logger.debug(
      "Environment chain: ${_getEnvironmentChain()}",
      category: 'Env',
    );

    if (values.containsKey(name)) {
      final val = values[name]!.value;
      Logger.debug(
        "Found '$name' = $val (type: ${val is Value ? val.raw.runtimeType : val.runtimeType}) in env ($hashCode)",
        category: 'Env',
      );
      return val;
    }

    if (parent != null) {
      Logger.debug(
        "'$name' not found in current env, checking parent env (${parent!.hashCode})",
        category: 'Env',
      );
      return parent!.get(name);
    }

    Logger.debug(
      "'$name' not found in any environment in chain: ${_getEnvironmentChain()}",
      category: 'Env',
    );
    return null;
  }

  /// Defines or updates a variable named [name] with [value].
  ///
  /// - For closures, checks current scope first
  /// - Searches up the environment chain for existing bindings
  /// - Creates a new binding in current scope if not found
  /// - Handles const variables and to-be-closed tracking
  void define(String name, dynamic value) {
    Logger.debug(
      "Defining/updating '$name' = $value (type: ${value.runtimeType}) in env ($hashCode)",
      category: 'Env',
    );

    // First check current scope if this is a closure
    if (isClosure && values.containsKey(name)) {
      final currentValue = values[name]!.value;
      Logger.debug(
        "Found existing value in closure scope: '$name' = $currentValue",
        category: 'Env',
      );
      if (currentValue is Value && currentValue.isConst) {
        Logger.debug(
          "Attempt to modify const variable '$name'",
          category: 'Env',
        );
        throw UnsupportedError("attempt to assign to const variable '$name'");
      }
      values[name]!.value = value;
      Logger.debug(
        "Updated closure variable '$name' to $value",
        category: 'Env',
      );
      return;
    }

    // Search up the chain for existing binding
    Environment? current = this;
    while (current != null) {
      if (current.values.containsKey(name)) {
        final currentValue = current.values[name]!.value;
        Logger.debug(
          "Found existing value in env (${current.hashCode}): '$name' = $currentValue",
          category: 'Env',
        );
        if (currentValue is Value && currentValue.isConst) {
          Logger.debug(
            "Attempt to modify const variable '$name'",
            category: 'Env',
          );
          throw UnsupportedError("attempt to assign to const variable '$name'");
        }
        current.values[name]!.value = value;
        Logger.debug(
          "Updated variable '$name' to $value in env (${current.hashCode})",
          category: 'Env',
        );
        return;
      }
      current = current.parent;
    }

    // If not found anywhere, create new binding in current scope
    values[name] = Box(value);
    Logger.debug(
      "Created new binding for '$name' = $value in env ($hashCode)",
      category: 'Env',
    );

    // Track to-be-closed variables
    if (value is Value && value.isToBeClose) {
      toBeClosedVars.add(name);
      Logger.debug(
        "Added '$name' to to-be-closed variables list",
        category: 'Env',
      );
    }
  }

  /// Declares a new variable in the current environment, always creating a
  /// fresh binding even if a variable with the same [name] already exists.
  ///
  /// This is used for Lua's `local` declarations which shadow any previous
  /// variable of the same name in the scope. Existing bindings remain valid for
  /// any closures that captured them.
  void declare(String name, dynamic value) {
    Logger.debug(
      "Declaring new '$name' = $value (type: ${value.runtimeType}) in env ($hashCode)",
      category: 'Env',
    );

    // Create a fresh Box that shadows any previous binding
    values[name] = Box(value, isLocal: true);

    // Track to-be-closed variables
    if (value is Value && value.isToBeClose) {
      toBeClosedVars.add(name);
      Logger.debug(
        "Added '$name' to to-be-closed variables list",
        category: 'Env',
      );
    }
  }

  /// Defines multiple variables in the current environment.
  ///
  /// Takes a map of variable names to values and defines each in this environment.
  void defineAll(Map<String, dynamic> values) {
    Logger.debug(
      "Defining multiple values in env ($hashCode): ${values.keys.join(', ')}",
      category: 'Env',
    );
    values.forEach((name, value) {
      define(name, value);
    });
  }

  /// Closes all to-be-closed variables in this environment in reverse order of declaration.
  ///
  /// [error] - Optional error that caused the scope to exit.
  Future<dynamic> closeVariables([dynamic error]) async {
    Logger.debug(
      "Closing variables in env ($hashCode). To be closed: ${toBeClosedVars.join(', ')}",
      category: 'Env',
    );

    // Close variables in reverse order of declaration
    for (var i = toBeClosedVars.length - 1; i >= 0; i--) {
      final name = toBeClosedVars[i];
      // Remove the variable from the environment before invoking __close.
      // This prevents recursive close calls from attempting to close the same
      // variable again, which can lead to deadlocks.
      final box = values.remove(name);
      final value = box?.value;
      toBeClosedVars.removeAt(i);

      Logger.debug(
        "Attempting to close variable '$name' = $value",
        category: 'Env',
      );

      if (value is Value) {
        try {
          interpreter?.enterProtectedCall();
          final result = await value.close(error);
          Logger.debug("Successfully closed variable '$name'", category: 'Env');
          if (result != null) {
            error = result;
          }
        } catch (e) {
          Logger.debug("Error closing variable '$name': $e", category: 'Env');
          error = e;
        } finally {
          interpreter?.exitProtectedCall();
        }
      }
    }
    return error;
  }

  /// Creates a new module environment.
  ///
  /// This creates an environment suitable for module execution, where
  /// local variables are scoped to the module but globals are inherited.
  static Environment createModuleEnvironment(Environment globalEnv) {
    Logger.debug(
      "Creating new module environment with global env (${globalEnv.hashCode})",
      category: 'Env',
    );

    final moduleEnv = Environment(parent: globalEnv, interpreter: null);

    final envTable = <dynamic, dynamic>{};
    final envValue = Value(envTable);

    final proxyHandler = <String, Function>{
      '__index': (List<Object?> args) {
        final key = args[1] as Value;
        final keyStr = key.raw.toString();
        Logger.debug(
          "Module env __index: looking up '$keyStr'",
          category: 'Env',
        );
        return moduleEnv.get(keyStr);
      },
      '__newindex': (List<Object?> args) {
        final key = args[1] as Value;
        final value = args[2] as Value;
        final keyStr = key.raw.toString();
        Logger.debug(
          "Module env __newindex: setting '$keyStr' to $value",
          category: 'Env',
        );
        moduleEnv.define(keyStr, value);
        return Value(null);
      },
    };

    envValue.setMetatable(proxyHandler);
    moduleEnv.define("_ENV", envValue);

    Logger.debug(
      "Module environment created with id (${moduleEnv.hashCode})",
      category: 'Env',
    );
    return moduleEnv;
  }

  /// Creates a clone of this environment
  Environment clone({Interpreter? interpreter}) {
    final cloned = Environment(
      parent: parent,
      interpreter: interpreter ?? this.interpreter,
    );

    // Copy all values
    for (final entry in values.entries) {
      cloned.values[entry.key] = entry.value;
    }

    // Copy to-be-closed variables
    cloned.toBeClosedVars.addAll(toBeClosedVars);

    return cloned;
  }

  static Environment? current;
}
