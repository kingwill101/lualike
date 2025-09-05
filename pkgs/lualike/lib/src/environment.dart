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
///
/// ## Variable Management Methods Overview
///
/// This class provides four main methods for variable operations, each serving
/// specific use cases to correctly implement Lua's variable scoping semantics:
///
/// ### 1. `get(name)` - Variable Lookup
/// - **Purpose**: Read variable values
/// - **Behavior**: Searches environment chain from current to root
/// - **Usage**: `x` in expressions like `print(x)` or `y = x + 1`
///
/// ### 2. `declare(name, value)` - Local Variable Declaration
/// - **Purpose**: Create new local variables (`local x = value`)
/// - **Behavior**: Always creates new binding with `isLocal: true`, shadows existing variables
/// - **Usage**: Local variable declarations in Lua code
///
/// ### 3. `updateLocal(name, value)` - Local Variable Assignment
/// - **Purpose**: Update existing local variables only
/// - **Behavior**: Searches for `isLocal: true` variables, updates first match
/// - **Returns**: `true` if local found and updated, `false` otherwise
/// - **Usage**: Assignments when local variable should take precedence
/// - **Why needed**: Prevents accidental global creation when local exists
///
/// ### 4. `defineGlobal(name, value)` - Global Variable Assignment
/// - **Purpose**: Create/update global variables specifically
/// - **Behavior**: Always operates on root environment, ignores local variables
/// - **Usage**: When assignment should target global environment
/// - **Why needed**: Ensures globals can be created even when locals exist
///
/// ### 5. `define(name, value)` - Legacy General Assignment
/// - **Purpose**: Original assignment method (has scoping issues)
/// - **Behavior**: Searches chain, updates first match, creates in root if none found
/// - **Status**: Still used but being phased out in favor of precise methods
///
/// ## Design Rationale
///
/// The multiple methods exist because Lua has complex variable scoping rules:
/// - Local variables shadow globals with the same name
/// - Assignments to existing locals should update the local, not create globals
/// - Assignments when no local exists should create/update globals
/// - Environment isolation (like `load()` with custom env) needs special handling
///
/// The original `define()` method couldn't distinguish these cases correctly,
/// leading to bugs where local variables in main scripts affected globals.
/// The newer methods provide precise control over each scenario.
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

  /// Whether this environment was created by load() with a custom environment.
  ///
  /// When true, assignments should not access local variables in parent scopes,
  /// but still allow access to global built-ins through the parent chain.
  bool isLoadIsolated;

  /// The interpreter associated with this environment.
  Interpreter? interpreter;

  /// Creates a new Environment.
  ///
  /// If [parent] is provided, this environment will be chained to it.
  /// If [isClosure] is true, this environment will be treated as a closure scope.
  /// If [isLoadIsolated] is true, this environment is isolated from parent scope locals.
  Environment({
    this.parent,
    this.interpreter,
    this.isClosure = false,
    this.isLoadIsolated = false,
  }) {
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
  /// Searches through the environment chain starting from this environment
  /// and moving up to parent environments until the variable is found.
  /// This method is used for variable access (reading variables).
  ///
  /// Returns the value if found, null if the variable doesn't exist anywhere
  /// in the environment chain.
  ///
  /// **Usage**: Variable lookups in expressions like `print(x)` or `y = x + 1`.
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
  /// This method implements Lua's assignment semantics by searching the
  /// environment chain for existing variables and updating them, or creating
  /// new global variables if none exist.
  ///
  /// **Behavior**:
  /// - For closures: checks current scope first before searching parents
  /// - Searches up the environment chain for existing bindings
  /// - Updates the first matching variable found (respects local variable precedence)
  /// - If no existing variable found, creates new binding in root environment
  /// - Handles const variables and to-be-closed tracking
  ///
  /// **Usage**: General variable assignments in regular environments.
  /// **Note**: This is the original method that had scoping issues. New methods
  /// `updateLocal()` and `defineGlobal()` provide more precise control.
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
      if (currentValue is Value &&
          (currentValue.isConst) | currentValue.isToBeClose) {
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
        if (currentValue is Value &&
            (currentValue.isConst | currentValue.isToBeClose)) {
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

    // If not found anywhere, create new binding in root environment
    // This ensures that global assignments from loaded code persist
    final rootEnv = root;
    rootEnv.values[name] = Box(value);
    Logger.debug(
      "Created new binding for '$name' = $value in root env (${rootEnv.hashCode})",
      category: 'Env',
    );

    // Track to-be-closed variables
    if (value is Value && value.isToBeClose) {
      rootEnv.toBeClosedVars.add(name);
      Logger.debug(
        "Added '$name' to to-be-closed variables list in root env",
        category: 'Env',
      );
    }
  }

  /// Declares a new local variable in the current environment.
  ///
  /// Always creates a fresh binding even if a variable with the same [name]
  /// already exists in this or parent environments. This implements Lua's
  /// `local` declaration semantics where local variables shadow any previous
  /// variables of the same name.
  ///
  /// **Key Properties**:
  /// - Creates new binding with `isLocal: true`
  /// - Shadows any existing variables (local or global) with same name
  /// - Existing bindings remain valid for closures that captured them
  /// - New binding exists only in current environment scope
  ///
  /// **Usage**: `local x = value` statements in Lua code.
  ///
  /// **Example**:
  /// ```lua
  /// x = "global"     -- Creates global variable
  /// local x = "local" -- Shadows global, creates local variable
  /// print(x)         -- Prints "local"
  /// ```
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

  /// Updates only local variables in the current scope chain.
  ///
  /// This method provides precise control for local variable assignments by
  /// searching only for variables marked with `isLocal: true` and updating
  /// the first one found in the environment chain.
  ///
  /// **Behavior**:
  /// - Searches from current environment up to parent environments
  /// - Only considers variables where `isLocal == true`
  /// - Updates the first matching local variable found
  /// - Does NOT create new variables
  /// - Does NOT update global variables
  /// - Respects const variable restrictions
  ///
  /// **Returns**: `true` if a local variable was found and updated, `false` otherwise.
  ///
  /// **Usage**: Local variable assignments when we need to ensure we're not
  /// accidentally creating globals or updating globals when a local exists.
  ///
  /// **Why needed**: The original `define()` method would find ANY variable
  /// (local or global) and update it, which caused scoping issues. This method
  /// ensures we only update local variables.
  ///
  /// **Example scenario**:
  /// ```lua
  /// local x = 1    -- declare() creates local variable
  /// x = 2          -- updateLocal() should update the local, not create global
  /// ```
  bool updateLocal(String name, dynamic value) {
    Logger.debug(
      "Attempting to update local variable '$name' = $value",
      category: 'Env',
    );

    Environment? current = this;
    while (current != null) {
      if (current.values.containsKey(name) && current.values[name]!.isLocal) {
        final currentValue = current.values[name]!.value;
        Logger.debug(
          "Found local variable '$name' in env (${current.hashCode})",
          category: 'Env',
        );

        if (currentValue is Value && currentValue.isConst) {
          Logger.debug(
            "Attempt to modify const local variable '$name'",
            category: 'Env',
          );
          throw UnsupportedError("attempt to assign to const variable '$name'");
        }

        current.values[name]!.value = value;
        Logger.debug(
          "Updated local variable '$name' to $value in env (${current.hashCode})",
          category: 'Env',
        );
        return true;
      }
      current = current.parent;
    }

    Logger.debug(
      "No local variable '$name' found in environment chain",
      category: 'Env',
    );
    return false;
  }

  /// Defines or updates a global variable in the root environment.
  ///
  /// This method provides precise control for global variable assignments by
  /// always operating on the root (global) environment, completely ignoring
  /// any local variables with the same name in the current scope chain.
  ///
  /// **Behavior**:
  /// - Always operates on the root environment (`root`)
  /// - Updates existing global variable if it exists
  /// - Creates new global variable if it doesn't exist
  /// - Completely ignores local variables with same name
  /// - Respects const variable restrictions for globals
  /// - Handles to-be-closed variable tracking in root environment
  ///
  /// **Usage**: When we specifically want to create or update a global variable,
  /// regardless of whether local variables with the same name exist.
  ///
  /// **Why needed**: The original `define()` method would find local variables
  /// first and update them instead of creating/updating globals. This method
  /// ensures we can always target the global environment specifically.
  ///
  /// **Example scenario**:
  /// ```lua
  /// local x = 1      -- Local variable exists
  /// _G.x = 2         -- defineGlobal() should update global, not local
  /// ```
  ///
  /// **Note**: This is used when assignment logic determines that a global
  /// assignment is intended (e.g., no local variable exists to update).
  void defineGlobal(String name, dynamic value) {
    Logger.debug("Defining global variable '$name' = $value", category: 'Env');

    final rootEnv = root;

    // Check if global variable already exists
    if (rootEnv.values.containsKey(name)) {
      final currentValue = rootEnv.values[name]!.value;
      if (currentValue is Value && currentValue.isConst) {
        Logger.debug(
          "Attempt to modify const global variable '$name'",
          category: 'Env',
        );
        throw UnsupportedError("attempt to assign to const variable '$name'");
      }
      rootEnv.values[name]!.value = value;
      Logger.debug(
        "Updated global variable '$name' to $value in root env (${rootEnv.hashCode})",
        category: 'Env',
      );
    } else {
      // Create new global variable
      rootEnv.values[name] = Box(value);
      Logger.debug(
        "Created new global variable '$name' = $value in root env (${rootEnv.hashCode})",
        category: 'Env',
      );
    }

    // Track to-be-closed variables in root environment
    if (value is Value && value.isToBeClose) {
      rootEnv.toBeClosedVars.add(name);
      Logger.debug(
        "Added '$name' to to-be-closed variables list in root env",
        category: 'Env',
      );
    }
  }

  /// Defines multiple variables in the current environment.
  ///
  /// Takes a map of variable names to values and defines each in this environment
  /// using the `define()` method. This is a convenience method for bulk operations.
  ///
  /// **Usage**: Bulk variable initialization, typically during environment setup.
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
  Future<void> closeVariables([dynamic error]) async {
    Logger.debug(
      "Closing variables in env ($hashCode). To be closed: ${toBeClosedVars.join(', ')}",
      category: 'Env',
    );

    // Close variables in reverse order of declaration
    for (var i = toBeClosedVars.length - 1; i >= 0; i--) {
      final name = toBeClosedVars[i];
      final value = values[name]?.value;

      Logger.debug(
        "Attempting to close variable '$name' = $value",
        category: 'Env',
      );

      if (value is Value) {
        try {
          await value.close(error);
          Logger.debug("Successfully closed variable '$name'", category: 'Env');
        } catch (e) {
          Logger.debug("Error closing variable '$name': $e", category: 'Env');
          error ??= e;
        }
      }
    }
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

  /// Gets the root environment (the one with no parent).
  Environment get root {
    Environment current = this;
    while (current.parent != null) {
      current = current.parent!;
    }
    return current;
  }

  static Environment? current;
}
