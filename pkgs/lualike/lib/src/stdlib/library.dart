import 'dart:collection';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'metatables.dart' show MetaTable;

/// Abstract base class for organizing standard library functions.
///
/// Extend this class to register a reusable namespaced or global library with a
/// [LuaRuntime]. LuaLike's built-in `string`, `table`, `math`, and `debug`
/// libraries all implement this interface.
///
/// A library with a non-empty [name] is installed as a table and can be loaded
/// lazily through [LibraryRegistry]. A library with an empty [name] injects its
/// functions directly into the global environment, which is how the base
/// library is modeled.
abstract class Library {
  /// The public Lua name for this library, such as `string` or `math`.
  ///
  /// Return an empty string for libraries that should populate the global
  /// namespace instead of a namespaced table.
  String get name;

  /// The runtime currently initializing this library.
  ///
  /// LuaLike sets this field before calling [registerFunctions]. Most custom
  /// libraries can access the runtime through [LibraryContext.interpreter] and
  /// do not need to retain this field directly.
  LuaRuntime? interpreter;

  /// Optional metamethods attached to the exported library table.
  ///
  /// Override this when the library itself should behave like an object with
  /// custom indexing, call behavior, or other metatable-driven operations.
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => null;

  /// Register all functions for this library.
  ///
  /// Use [LibraryRegistrationContext.define] to add functions or constants to
  /// this library. Registration happens once per runtime.
  void registerFunctions(LibraryRegistrationContext context);
}

/// Registration context passed to [Library.registerFunctions].
///
/// This exposes the active [environment] and [interpreter] so library code can
/// look up globals, cache helpers, or create runtime-aware builtins.
class LibraryContext {
  /// The environment receiving this library's exported values.
  final Environment environment;

  /// The runtime performing registration.
  final LuaRuntime? interpreter;

  /// Creates a registration context for a specific [environment].
  LibraryContext({required this.environment, this.interpreter});

  /// The active runtime, exposed with the legacy `vm` name for older code.
  LuaRuntime? get vm => interpreter;
}

/// Builds [BuiltinFunction] instances bound to a registration context.
///
/// Use this when a native function should participate in runtime services such
/// as cached primitive values through [BuiltinFunction.primitiveValue].
class BuiltinFunctionBuilder {
  final LibraryContext _context;

  /// Creates a builder that binds new functions to [_context].
  BuiltinFunctionBuilder(this._context);

  /// Creates a [BuiltinFunction] that keeps the active runtime reference.
  ///
  /// This is the preferred path for native functions that create many scalar
  /// values and want to reuse cached wrappers where available.
  BuiltinFunction create(Object? Function(List<Object?> args) implementation) {
    final interpreter = _context.vm;
    if (interpreter == null) {
      throw StateError('No interpreter available in context');
    }
    return _BuiltinFunctionImpl(interpreter, implementation);
  }

  /// Creates a [Value]-wrapped function without attaching interpreter context.
  ///
  /// This is mainly useful for backwards compatibility with older builtins that
  /// do not need runtime-aware helpers.
  Value createSimple(Object? Function(List<Object?> args) implementation) {
    return Value(implementation);
  }
}

/// Internal [BuiltinFunction] wrapper created by [BuiltinFunctionBuilder].
class _BuiltinFunctionImpl extends BuiltinFunction {
  final Object? Function(List<Object?> args) _implementation;

  _BuiltinFunctionImpl(LuaRuntime interpreter, this._implementation);

  @override
  Object? call(List<Object?> args) {
    return _implementation(args);
  }
}

/// Registry for all standard and user-defined libraries in a runtime.
///
/// A [LuaRuntime] owns a single registry. Register a [Library] instance and
/// then call [initializeLibrary], [initializeLibraryByName], or
/// [initializeAll] to expose it to scripts.
class LibraryRegistry {
  final List<Library> _libraries = [];
  final Map<String, Library> _librariesByName = {};
  final Set<Library> _initialized = {};
  final LuaRuntime _interpreter;

  LibraryRegistry(this._interpreter);

  /// The libraries registered with this runtime in registration order.
  List<Library> get libraries => List.unmodifiable(_libraries);

  /// Registers [library] with this runtime.
  ///
  /// Registration does not expose the library immediately. Call one of the
  /// initialization methods to populate globals or library tables.
  void register(Library library) {
    _libraries.add(library);
    if (library.name.isNotEmpty) {
      _librariesByName[library.name] = library;
    }
  }

  /// Initializes every registered library.
  void initializeAll() {
    for (final library in _libraries) {
      initializeLibrary(library);
    }
  }

  /// Initialize a specific library by name (if registered).
  Value? initializeLibraryByName(String name) {
    final library = _librariesByName[name];
    if (library == null) {
      return null;
    }
    return initializeLibrary(library);
  }

  /// Initialize the provided library instance if it hasn't been already.
  ///
  /// Returns the exported library table for namespaced libraries and `null` for
  /// global libraries.
  Value? initializeLibrary(Library library) {
    if (_initialized.contains(library)) {
      if (library.name.isEmpty) {
        return null;
      }
      final existing = _interpreter.getCurrentEnv().get(library.name);
      return existing is Value ? existing : null;
    }

    final context = LibraryContext(
      environment: _interpreter.getCurrentEnv(),
      interpreter: _interpreter,
    );

    final value = _initializeLibrary(library, context);
    _initialized.add(library);
    return value;
  }

  Value? _initializeLibrary(Library library, LibraryContext context) {
    // Set the interpreter on the library
    library.interpreter = context.interpreter;

    // Create a table for this library's functions
    final libraryTable = <String, dynamic>{};

    // Create a scoped environment for this library
    final libraryContext = LibraryContext(
      environment: context.environment,
      interpreter: context.interpreter,
    );

    // Temporarily store functions in a map during registration
    final functionMap = <String, dynamic>{};
    final tempContext = LibraryRegistrationContext._internal(
      libraryContext,
      functionMap,
    );

    // Register the library's functions
    library.registerFunctions(tempContext);

    // Copy functions to the library table
    libraryTable.addAll(functionMap);

    // Handle base library (global functions) vs namespaced libraries
    if (library.name.isEmpty) {
      // Base library: define functions directly in global environment
      functionMap.forEach((name, function) {
        context.environment.define(name, function);
      });
      return null;
    }

    // Namespaced library: create library table
    final metamethods = context.interpreter != null
        ? library.getMetamethods(context.interpreter!)
        : null;
    final libraryValue = metamethods != null
        ? Value(libraryTable, metatable: metamethods)
        : Value(libraryTable);

    final existing = context.environment.get(library.name);
    if (existing is Value && existing.raw is LazyLibraryMap) {
      // Reuse the existing Value so any cached references continue to work.
      final lazyMap = existing.raw as LazyLibraryMap;
      lazyMap.attach(libraryValue);
      existing.raw = libraryValue.raw;
      existing.metatable = libraryValue.metatable;
      existing.metatableRef = libraryValue.metatableRef;
      existing.functionName = libraryValue.functionName;
      context.environment.define(library.name, existing);
      _updatePackageLoaded(context.environment, library.name, existing);
      return existing;
    }

    context.environment.define(library.name, libraryValue);
    _updatePackageLoaded(context.environment, library.name, libraryValue);
    return libraryValue;
  }
}

void _updatePackageLoaded(
  Environment env,
  String libraryName,
  Value libraryValue,
) {
  if (libraryName.isEmpty) {
    return;
  }
  final packageValue = env.get('package');
  if (packageValue is! Value || packageValue.raw is! Map) {
    return;
  }
  final packageMap = packageValue.raw as Map;
  final loaded = packageMap['loaded'];
  if (loaded is! Value || loaded.raw is! Map) {
    return;
  }
  final loadedMap = loaded.raw as Map;
  loadedMap[libraryName] = libraryValue;
  if (libraryName == 'string') {
    MetaTable.refreshStringCache();
  }
}

class LazyLibraryMap extends MapBase<String, dynamic> {
  /// Creates a lazy view that initializes [libraryName] on first access.
  LazyLibraryMap({
    required this.env,
    required this.registry,
    required this.libraryName,
  });

  final Environment env;
  final LibraryRegistry registry;
  final String libraryName;

  Map<String, dynamic>? _resolved;
  bool _loading = false;

  Map<String, dynamic> _ensureResolved() {
    if (_resolved != null) {
      return _resolved!;
    }
    if (_loading) {
      return <String, dynamic>{};
    }
    _loading = true;
    final initialized = registry.initializeLibraryByName(libraryName);
    if (initialized is Value && initialized.raw is Map) {
      _resolved = initialized.raw as Map<String, dynamic>;
    }
    if (_resolved != null) {
      _loading = false;
      return _resolved!;
    }
    final value = env.get(libraryName);
    if (value is Value && value.raw is Map) {
      _resolved = value.raw as Map<String, dynamic>;
    } else {
      _resolved = <String, dynamic>{};
    }
    _loading = false;
    return _resolved!;
  }

  void attach(Value value) {
    if (value.raw is Map) {
      _resolved = value.raw as Map<String, dynamic>;
    }
  }

  @override
  Iterable<String> get keys => _ensureResolved().keys;

  @override
  bool containsKey(Object? key) {
    return _ensureResolved().containsKey(key);
  }

  @override
  dynamic operator [](Object? key) => _ensureResolved()[key];

  @override
  void operator []=(String key, dynamic value) {
    _ensureResolved()[key] = value;
  }

  @override
  void clear() => _ensureResolved().clear();

  @override
  dynamic remove(Object? key) => _ensureResolved().remove(key);
}

/// Registration context that collects the exported values for a [Library].
class LibraryRegistrationContext extends LibraryContext {
  final Map<String, dynamic> _functionMap;

  LibraryRegistrationContext._internal(LibraryContext base, this._functionMap)
    : super(environment: base.environment, interpreter: base.interpreter);

  /// Defines an exported [function] or constant under [name].
  ///
  /// Plain Dart callables and [BuiltinFunction] instances are wrapped once in a
  /// [Value] during registration so repeated global lookups do not allocate new
  /// wrappers.
  void define(String name, dynamic function) {
    // Wrap builtin functions in Value objects once during registration
    // to avoid creating new Value wrappers on every identifier access.
    // This prevents temporary Value allocations that affect collectgarbage("count").
    if ((function is BuiltinFunction || function is Function) &&
        function is! Value) {
      _functionMap[name] = Value(function, functionName: name);
    } else {
      _functionMap[name] = function;
    }
  }
}
