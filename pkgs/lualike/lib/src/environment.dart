import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart' show GCObject;
import 'package:lualike/src/gc/gc_weights.dart';
// Per-interpreter GC available via Environment.interpreter.gc
import 'package:lualike/src/gc/gc_access.dart';
import 'package:lualike/src/gc/memory_credits.dart';

/// A generic box class that wraps a single value of type T.
/// Used to create mutable references to values in the environment.
class Box<T> extends GCObject {
  /// The wrapped value.
  T _value;

  T get value => _value;
  set value(T newValue) {
    _value = newValue;
    final gc = interpreter?.gc ?? GCAccess.defaultManager;
    gc?.noteReferenceWrite(this, newValue);
  }

  /// Whether this binding represents a local variable.
  final bool isLocal;

  /// Whether this Box should be excluded from memory credit tracking.
  /// Transient boxes (function parameters, local variables in executing functions)
  /// are not counted to match Lua's behavior where the C stack isn't counted.
  final bool isTransient;

  /// Runtime owner used for GC registration and incremental write barriers.
  LuaRuntime? interpreter;

  /// Optional debug helper storing the symbol name backing this box.
  String? debugName;

  /// Count of upvalues that currently reference this box.
  ///
  /// Boxes with active upvalues cannot be cleared when exiting a scope
  /// because closures still depend on their stored values.
  int _upvalueRefCount = 0;

  /// Creates a new Box containing [value].
  Box(
    T value, {
    this.isLocal = false,
    this.isTransient = false,
    this.interpreter,
  }) : _value = value {
    // Register with GC, but don't count allocation for transient boxes
    final gc = interpreter?.gc ?? GCAccess.fromEnv(null);
    gc?.register(this, countAllocation: !isTransient);
  }

  @override
  int get estimatedSize => GcWeights.gcObjectHeader + GcWeights.boxBase;

  @override
  List<GCObject> getReferences() {
    // Skip nil values to allow weak table collection
    if (value == null) return [];
    if (value is Value && value.isNil) return [];
    return value is GCObject ? [value as GCObject] : [];
  }

  /// Marks this box as being referenced by an upvalue.
  void retainUpvalue() {
    _upvalueRefCount++;
  }

  /// Releases an upvalue reference from this box.
  void releaseUpvalue() {
    if (_upvalueRefCount > 0) {
      _upvalueRefCount--;
    }
  }

  /// Whether this box still has live upvalues referencing it.
  bool get hasUpvalueReferences => _upvalueRefCount > 0;

  @override
  String toString() {
    final namePart = debugName != null ? '$debugName=' : '';
    return 'Box($namePart$value)';
  }
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
  static int totalCreated = 0;
  static int totalFreed = 0;
  static int maxActive = 0;

  /// Storage for variable bindings in this scope.
  final Map<String, Box<dynamic>> values = {};

  /// Names explicitly declared as globals in this lexical scope.
  ///
  /// These shadow outer locals for name resolution while still targeting the
  /// root global binding.
  final Map<String, Box<dynamic>> declaredGlobals = {};

  /// Tracks the order in which to-be-closed variables were declared
  final List<String> toBeClosedVars = [];

  /// Tracks pending implicit to-be-closed resources that are active for this
  /// scope but are not represented as normal local bindings.
  int pendingImplicitToBeClosed = 0;

  /// Stores implicit to-be-closed resources that must stay GC-reachable even
  /// when they are not ordinary local bindings.
  final List<Value> implicitToBeClosedValues = <Value>[];

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
  LuaRuntime? interpreter;

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
    final gc = GCAccess.fromEnv(this);
    gc?.register(this, countAllocation: false);
    Logger.debugLazy(
      () => "Environment($hashCode) created. Parent: ${parent?.hashCode}",
      category: 'Env',
    );
  }

  void _updateCredits() {
    final gc = GCAccess.fromEnv(this);
    if (gc != null) {
      MemoryCredits.instance.recalculate(this);
    }
  }

  void _noteChildReference(Object? child) {
    final gc = interpreter?.gc ?? GCAccess.defaultManager;
    gc?.noteReferenceWrite(this, child);
  }

  int _countedBindingEntries(Iterable<Box<dynamic>> boxes) {
    var count = 0;
    for (final box in boxes) {
      if (!box.isTransient || box.hasUpvalueReferences) {
        count++;
      }
    }
    return count;
  }

  void _syncGlobalTableEntry(String name, dynamic value) {
    final rootEnv = root;
    final gBox = rootEnv.values['_G'];
    if (gBox == null) {
      return;
    }
    final gValue = gBox.value;
    if (gValue is! Value || gValue.raw is! Map) {
      return;
    }

    final map = gValue.raw as Map;
    final manager = rootEnv.interpreter?.gc ?? GCAccess.defaultManager;
    if (value is Value ? value.raw == null : value == null) {
      map.remove(name);
    } else {
      final wrappedValue = value is Value ? value : Value(value);
      if (wrappedValue.interpreter == null && rootEnv.interpreter != null) {
        wrappedValue.interpreter = rootEnv.interpreter;
      }
      manager?.ensureTracked(wrappedValue);
      map[name] = wrappedValue;
      manager?.noteReferenceWrite(gValue, name);
      manager?.noteReferenceWrite(gValue, wrappedValue);
    }
    gValue.markTableModified();
  }

  @override
  int get estimatedSize =>
      GcWeights.gcObjectHeader +
      GcWeights.environmentBase +
      (_countedBindingEntries(values.values) +
              _countedBindingEntries(declaredGlobals.values)) *
          GcWeights.environmentEntry;

  @override
  List<GCObject> getReferences() {
    final refs = <GCObject>[];
    if (parent != null) {
      refs.add(parent!);
    }
    for (final entry in values.entries) {
      final box = entry.value;
      final boxedValue = box.value;

      // Skip nil values - they don't need GC protection and shouldn't keep
      // weak table entries alive. This allows proper weak table collection
      // when variables are nil'ed.
      if (boxedValue == null) continue;
      if (boxedValue is Value && boxedValue.isNil) continue;

      // Return the Box and any GCObject value it holds as references.
      // Do not auto-enroll raw values directly; discovery proceeds via Box.
      refs.add(box);
    }
    for (final box in declaredGlobals.values) {
      refs.add(box);
    }
    refs.addAll(implicitToBeClosedValues);
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
    Logger.debugLazy(
      () => "Checking if '$name' exists in env ($hashCode)",
      category: 'Env',
    );

    // Check current environment
    if (values.containsKey(name)) {
      Logger.debugLazy(
        () => "Variable '$name' found in current env ($hashCode)",
        category: 'Env',
      );
      return true;
    }

    if (declaredGlobals.containsKey(name)) {
      Logger.debugLazy(
        () => "Declared global '$name' found in current env ($hashCode)",
        category: 'Env',
      );
      return true;
    }

    // Check parent environments
    if (parent != null) {
      Logger.debugLazy(
        () =>
            "Variable '$name' not found in current env, checking parent env (${parent!.hashCode})",
        category: 'Env',
      );
      return parent!.contains(name);
    }

    Logger.debugLazy(
      () =>
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
    if (Logger.enabled) {
      Logger.debugLazy(
        () => "Looking for '$name' in env ($hashCode)}",
        category: 'Env',
      );
      Logger.debugLazy(
        () => "Environment chain: ${_getEnvironmentChain()}",
        category: 'Env',
      );
    }

    if (values.containsKey(name)) {
      final val = values[name]!.value;
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              "Found '$name' = $val (type: ${val is Value ? val.raw.runtimeType : val.runtimeType}) in env ($hashCode)",
          category: 'Env',
        );
      }
      return val;
    }

    if (declaredGlobals.containsKey(name)) {
      final val = declaredGlobals[name]!.value;
      if (Logger.enabled) {
        Logger.debugLazy(
          () => "Found declared global '$name' = $val in env ($hashCode)",
          category: 'Env',
        );
      }
      return val;
    }

    if (parent != null) {
      if (Logger.enabled) {
        Logger.debugLazy(
          () =>
              "'$name' not found in current env, checking parent env (${parent!.hashCode})",
          category: 'Env',
        );
      }
      return parent!.get(name);
    }

    if (Logger.enabled) {
      Logger.debugLazy(
        () =>
            "'$name' not found in any environment in chain: ${_getEnvironmentChain()}",
        category: 'Env',
      );
    }
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
    Logger.debugLazy(
      () =>
          "Defining/updating '$name' = $value "
          "(type: ${value.runtimeType}) in env ($hashCode)",
      category: 'Env',
    );

    // First check current scope if this is a closure
    if (isClosure && values.containsKey(name)) {
      final currentValue = values[name]!.value;
      Logger.debugLazy(
        () =>
            "Found existing value in closure scope: '$name' = "
            '$currentValue',
        category: 'Env',
      );
      if (currentValue is Value &&
          (currentValue.isConst || currentValue.isToBeClose)) {
        Logger.debugLazy(
          () => "Attempt to modify const variable '$name'",
          category: 'Env',
        );
        throw LuaError("attempt to assign to const variable '$name'");
      }
      if (!_tryFastReplaceBoxValue(values[name]!, value)) {
        values[name]!.value = value;
      }
      Logger.debugLazy(
        () => "Updated closure variable '$name' to $value",
        category: 'Env',
      );
      return;
    }

    if (declaredGlobals.containsKey(name)) {
      final box = declaredGlobals[name]!;
      final currentValue = box.value;
      if (currentValue is Value &&
          (currentValue.isConst || currentValue.isToBeClose)) {
        Logger.debugLazy(
          () => "Attempt to modify const declared global '$name'",
          category: 'Env',
        );
        throw LuaError("attempt to assign to const variable '$name'");
      }
      if (!_tryFastReplaceBoxValue(box, value)) {
        box.value = value;
      }
      root._syncGlobalTableEntry(name, box.value);
      return;
    }

    // Search up the chain for existing binding
    Environment? current = this;
    while (current != null) {
      if (current.values.containsKey(name)) {
        final currentValue = current.values[name]!.value;
        Logger.debugLazy(
          () =>
              "Found existing value in env (${current.hashCode}): "
              "'$name' = $currentValue",
          category: 'Env',
        );
        if (currentValue is Value &&
            (currentValue.isConst || currentValue.isToBeClose)) {
          Logger.debugLazy(
            () => "Attempt to modify const variable '$name'",
            category: 'Env',
          );
          throw LuaError("attempt to assign to const variable '$name'");
        }
        if (!_tryFastReplaceBoxValue(current.values[name]!, value)) {
          current.values[name]!.value = value;
        }
        Logger.debugLazy(
          () =>
              "Updated variable '$name' to $value in env "
              '(${current.hashCode})',
          category: 'Env',
        );
        if (current.parent == null) {
          _syncGlobalTableEntry(name, current.values[name]!.value);
        }
        return;
      }
      current = current.parent;
    }

    // If not found anywhere, create new binding in root environment
    // This ensures that global assignments from loaded code persist
    final rootEnv = root;
    // Mark as transient to match Lua behavior - variable bindings on the
    // stack aren't counted toward memory usage
    final box = Box(value, isTransient: true, interpreter: rootEnv.interpreter);
    rootEnv.values[name] = box;
    rootEnv._noteChildReference(box);
    rootEnv._updateCredits();
    Logger.debugLazy(
      () =>
          "Created new binding for '$name' = $value in root env "
          '(${rootEnv.hashCode})',
      category: 'Env',
    );

    _syncGlobalTableEntry(name, value);

    // Track to-be-closed variables
    if (value is Value && value.isToBeClose) {
      rootEnv.toBeClosedVars.add(name);
      Logger.debugLazy(
        () => "Added '$name' to to-be-closed variables list in root env",
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
  void declare(String name, dynamic value, {bool trackToBeClosed = false}) {
    Logger.debugLazy(
      () =>
          "Declaring new '$name' = $value "
          "(type: ${value.runtimeType}) in env ($hashCode)",
      category: 'Env',
    );

    // Create a fresh Box that shadows any previous binding
    // Mark as transient since function-local variables aren't counted in Lua's memory
    final box = Box(
      value,
      isLocal: true,
      isTransient: true,
      interpreter: interpreter,
    );
    values[name] = box;
    _noteChildReference(box);
    _updateCredits();

    // Track to-be-closed variables
    if (trackToBeClosed && value is Value && value.isToBeClose) {
      toBeClosedVars.add(name);
      Logger.debugLazy(
        () => "Added '$name' to to-be-closed variables list",
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
    Logger.debugLazy(
      () => "Attempting to update local variable '$name' = $value",
      category: 'Env',
    );

    Environment? current = this;
    while (current != null) {
      if (current.values.containsKey(name) && current.values[name]!.isLocal) {
        final currentValue = current.values[name]!.value;
        Logger.debugLazy(
          () => "Found local variable '$name' in env (${current.hashCode})",
          category: 'Env',
        );

        if (currentValue is Value &&
            (currentValue.isConst || currentValue.isToBeClose)) {
          Logger.debugLazy(
            () => "Attempt to modify const variable '$name'",
            category: 'Env',
          );
          throw LuaError("attempt to assign to const variable '$name'");
        }

        current.values[name]!.value = value;
        Logger.debugLazy(
          () =>
              "Updated local variable '$name' to $value in env "
              '(${current.hashCode})',
          category: 'Env',
        );
        return true;
      }
      current = current.parent;
    }

    Logger.debugLazy(
      () => "No local variable '$name' found in environment chain",
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
    Logger.debugLazy(
      () => "Defining global variable '$name' = $value",
      category: 'Env',
    );

    final rootEnv = root;

    // Check if global variable already exists
    if (rootEnv.values.containsKey(name)) {
      final box = rootEnv.values[name]!;
      final currentValue = box.value;
      if (currentValue is Value && currentValue.isConst) {
        Logger.debugLazy(
          () => "Attempt to modify const global variable '$name'",
          category: 'Env',
        );
        throw LuaError("attempt to assign to const variable '$name'");
      }
      if (!_tryFastReplaceBoxValue(box, value)) {
        box.value = value;
      }
      Logger.debugLazy(
        () =>
            "Updated global variable '$name' to $value in root env "
            '(${rootEnv.hashCode})',
        category: 'Env',
      );
    } else {
      // Create new global variable
      Logger.debugLazy(
        () =>
            "Creating new global variable '$name' with value type "
            '${value.runtimeType} (is GCObject: ${value is GCObject})',
        category: 'Env',
      );
      final box = Box(value, interpreter: rootEnv.interpreter);
      rootEnv.values[name] = box;
      rootEnv._noteChildReference(box);
      Logger.debugLazy(
        () =>
            "Created new global variable '$name' = $value in root env "
            '(${rootEnv.hashCode})',
        category: 'Env',
      );
    }

    rootEnv._updateCredits();

    // Keep the underlying _G table in sync so reads via _G[k] see updates
    _syncGlobalTableEntry(name, rootEnv.values[name]!.value);

    // Track to-be-closed variables in root environment
    if (value is Value && value.isToBeClose) {
      rootEnv.toBeClosedVars.add(name);
      Logger.debugLazy(
        () => "Added '$name' to to-be-closed variables list in root env",
        category: 'Env',
      );
    }
  }

  /// Removes the root global binding for [name] and keeps the backing `_G`
  /// table in sync.
  ///
  /// Explicit global declarations can redeclare a name with fewer initializer
  /// results than names. In that case the missing slots should resolve through
  /// `_ENV` as `nil`, not remain as stale root bindings carrying previous
  /// values or const attributes.
  void clearGlobal(String name) {
    final rootEnv = root;
    rootEnv.values.remove(name);
    rootEnv.toBeClosedVars.remove(name);
    rootEnv._updateCredits();
    rootEnv._syncGlobalTableEntry(name, null);
  }

  /// Declares [name] as an explicit global in this lexical scope.
  ///
  /// Subsequent lookups in this scope and nested scopes resolve through the
  /// active `_ENV` binding, even when an outer local with the same name exists.
  void declareGlobalBinding(String name) {
    Box<dynamic>? box;
    Environment? current = this;
    while (current != null) {
      final declared = current.declaredGlobals[name];
      if (declared != null) {
        box = declared;
        break;
      }
      current = current.parent;
    }

    // Explicit global declarations are lexical resolution markers, not shared
    // storage. Reads and writes should still flow through the active `_ENV`.
    box ??= Box<dynamic>(null, isTransient: true, interpreter: interpreter);
    box.debugName ??= name;
    declaredGlobals[name] = box;
    _noteChildReference(box);
    _updateCredits();
  }

  /// Finds the nearest explicit-global binding for [name] in this lexical chain.
  Box<dynamic>? findDeclaredGlobalBox(String name) {
    Environment? current = this;
    while (current != null) {
      final box = current.declaredGlobals[name];
      if (box != null) {
        return box;
      }
      current = current.parent;
    }
    return null;
  }

  /// Reads the root global binding for [name], ignoring local variables.
  dynamic readRootGlobal(String name) {
    final rootEnv = root;
    final box = rootEnv.values[name];
    if (box != null && !box.isLocal) {
      return box.value;
    }

    final gValue = rootEnv.values['_G']?.value;
    if (gValue is Value && gValue.raw is Map) {
      return (gValue.raw as Map)[name];
    }
    return null;
  }

  /// Defines multiple variables in the current environment.
  ///
  /// Takes a map of variable names to values and defines each in this environment
  /// using the `define()` method. This is a convenience method for bulk operations.
  ///
  /// **Usage**: Bulk variable initialization, typically during environment setup.
  void defineAll(Map<String, dynamic> values) {
    Logger.debugLazy(
      () =>
          "Defining multiple values in env ($hashCode): ${values.keys.join(', ')}",
      category: 'Env',
    );
    values.forEach((name, value) {
      define(name, value);
    });
  }

  /// Finds the [Box] associated with [name] in this environment chain.
  /// Returns null if no binding exists.
  Box<dynamic>? findBox(String name) {
    Environment? current = this;
    while (current != null) {
      final box = current.values[name];
      if (box != null) {
        return box;
      }
      final declaredGlobal = current.declaredGlobals[name];
      if (declaredGlobal != null) {
        return declaredGlobal;
      }
      current = current.parent;
    }
    return null;
  }

  /// Returns whether [name] resolves through an explicit global declaration
  /// before any local binding when walking the lexical scope chain.
  bool resolvesThroughDeclaredGlobal(String name) {
    Environment? current = this;
    while (current != null) {
      if (current.values.containsKey(name)) {
        return false;
      }
      if (current.declaredGlobals.containsKey(name)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  /// Closes all to-be-closed variables in this environment in reverse order of declaration.
  ///
  /// [error] - Optional error that caused the scope to exit.
  Future<void> closeVariables([dynamic error]) async {
    Logger.debugLazy(
      () =>
          "Closing variables in env ($hashCode). To be closed: ${toBeClosedVars.join(', ')}",
      category: 'Env',
    );

    dynamic normalizeCloseError(dynamic error) {
      if (error case final LuaError luaError) {
        if (luaError.cause != null && luaError.cause is! LuaError) {
          return luaError.cause;
        }
        return luaError.message;
      }
      if (error case final Value value when value.raw is LuaError) {
        final luaError = value.raw as LuaError;
        if (luaError.cause != null && luaError.cause is! LuaError) {
          return luaError.cause;
        }
        return luaError.message;
      }
      return error;
    }

    var currentError = normalizeCloseError(error);
    var closeErrorSeen = false;

    // Close variables in reverse order of declaration. Remove the variable
    // before invoking its close handler so reentrant safe points do not try
    // to close it twice while still preserving the remaining variables if a
    // close handler yields.
    while (toBeClosedVars.isNotEmpty) {
      final name = toBeClosedVars.removeLast();
      final value = values[name]?.value;

      Logger.debugLazy(
        () => "Attempting to close variable '$name' = $value",
        category: 'Env',
      );

      if (value is Value) {
        try {
          await value.close(currentError);
          Logger.debugLazy(
            () => "Successfully closed variable '$name'",
            category: 'Env',
          );
        } on YieldException {
          rethrow;
        } catch (e) {
          Logger.debugLazy(
            () => "Error closing variable '$name': $e",
            category: 'Env',
          );
          currentError = normalizeCloseError(e);
          closeErrorSeen = true;
        }
      }
    }

    final gc = GCAccess.fromEnv(this);
    if (gc != null) {
      Logger.debugLazy(
        () =>
            'Environment safe point debt check: debt=${gc.allocationDebt} threshold=${gc.autoTriggerDebtThreshold}',
        category: 'Env',
      );
      if (gc.allocationDebt >= gc.autoTriggerDebtThreshold) {
        gc.runPendingAutoTrigger();
      }
    }

    if (closeErrorSeen) {
      throw currentError!;
    }
  }

  /// Creates a new module environment.
  ///
  /// This creates an environment suitable for module execution, where
  /// local variables are scoped to the module but globals are inherited.
  static Environment createModuleEnvironment(Environment globalEnv) {
    final rootEnv = globalEnv.root;
    Logger.debugLazy(
      () =>
          "Creating new module environment with global env (${rootEnv.hashCode})",
      category: 'Env',
    );

    final moduleEnv = Environment(parent: rootEnv, interpreter: null);

    final envTable = <dynamic, dynamic>{};
    final envValue = Value(envTable, interpreter: rootEnv.interpreter);
    final inheritedEnvValue = switch (globalEnv.get('_ENV')) {
      final Value value => value,
      final Object? value? => Value(value),
      _ => null,
    };

    final proxyHandler = <String, Function>{
      '__index': (List<Object?> args) {
        final key = args[1] as Value;
        final keyStr = key.raw.toString();
        Logger.debugLazy(
          () => "Module env __index: looking up '$keyStr'",
          category: 'Env',
        );
        if (envTable.containsKey(keyStr)) {
          return envTable[keyStr];
        }
        if (inheritedEnvValue != null && inheritedEnvValue.raw is Map) {
          final inheritedTable = inheritedEnvValue.raw as Map;
          if (inheritedTable.containsKey(keyStr)) {
            return inheritedTable[keyStr];
          }
        }
        return rootEnv.get(keyStr);
      },
      '__newindex': (List<Object?> args) {
        final key = args[1] as Value;
        final value = args[2] as Value;
        final keyStr = key.raw.toString();
        final gc = rootEnv.interpreter?.gc ?? GCAccess.defaultManager;
        Logger.debugLazy(
          () => "Module env __newindex: setting '$keyStr' to $value",
          category: 'Env',
        );
        envTable[keyStr] = value;
        gc?.ensureTracked(value);
        gc?.noteReferenceWrite(envValue, keyStr);
        gc?.noteReferenceWrite(envValue, value);
        envValue.markTableModified();
        if (inheritedEnvValue != null && inheritedEnvValue.raw is Map) {
          final inheritedTable = inheritedEnvValue.raw as Map;
          inheritedTable[keyStr] = value;
          gc?.noteReferenceWrite(inheritedEnvValue, keyStr);
          gc?.noteReferenceWrite(inheritedEnvValue, value);
          inheritedEnvValue.markTableModified();
        } else {
          rootEnv.defineGlobal(keyStr, value);
        }
        return Value(null);
      },
    };

    envValue.setMetatable(proxyHandler);
    moduleEnv.declare("_ENV", envValue);

    Logger.debugLazy(
      () => "Module environment created with id (${moduleEnv.hashCode})",
      category: 'Env',
    );
    return moduleEnv;
  }

  /// Creates a clone of this environment
  Environment clone({LuaRuntime? interpreter}) {
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

    cloned._updateCredits();

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
}

bool _tryFastReplaceBoxValue(Box<dynamic> box, dynamic incoming) {
  bool isFastReplacePayload(Object? raw) =>
      raw == null ||
      raw is num ||
      raw is bool ||
      raw is String ||
      raw is LuaString;

  if (incoming is! Value) {
    return false;
  }
  final existing = box.value;
  if (existing is! Value) {
    return false;
  }
  if (existing.isConst || existing.isToBeClose) {
    return false;
  }
  if (incoming.isMulti || incoming.isToBeClose) {
    return false;
  }
  if (existing.metatable != null || incoming.metatable != null) {
    return false;
  }
  if (incoming.upvalues != null || existing.upvalues != null) {
    return false;
  }
  if (!isFastReplacePayload(existing.raw)) {
    return false;
  }
  final raw = incoming.raw;
  if (!isFastReplacePayload(raw)) {
    return false;
  }

  existing.raw = raw;
  existing.isMulti = false;
  existing.isTempKey = incoming.isTempKey;
  existing.isNilReturningClosure = incoming.isNilReturningClosure;
  existing.isLessComparator = incoming.isLessComparator;
  existing.isLessComparatorReversed = incoming.isLessComparatorReversed;
  existing.isCountedLessComparator = incoming.isCountedLessComparator;
  existing.isCountedLessComparatorReversed =
      incoming.isCountedLessComparatorReversed;
  existing.comparatorCounterBox = incoming.comparatorCounterBox;
  existing.interpreter ??= incoming.interpreter;
  existing.functionName = incoming.functionName;
  existing.closureEnvironment = incoming.closureEnvironment;
  existing.upvalues = incoming.upvalues;
  existing.functionBody = incoming.functionBody;
  existing.metatableRef = null;
  return true;
}
