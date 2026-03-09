import 'dart:collection';

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'metatables.dart' show MetaTable;

/// Abstract base class for organizing standard library functions.
///
/// Each library (string, table, math, etc.) should extend this class
/// and define their functions in a structured way.
abstract class Library {
  /// The name of this library (e.g., "string", "table", "math")
  String get name;

  /// The runtime instance associated with this library
  LuaRuntime? interpreter;

  /// Optional: metamethods for this library's values
  Map<String, Function>? getMetamethods(LuaRuntime interpreter) => null;

  /// Register all functions for this library.
  ///
  /// This method is called during interpreter initialization and should
  /// define all builtin functions for this library.
  void registerFunctions(LibraryRegistrationContext context);
}

/// Context provided to libraries during registration
class LibraryContext {
  final Environment environment;
  final LuaRuntime? interpreter;

  LibraryContext({required this.environment, this.interpreter});

  /// Get the appropriate interpreter instance
  LuaRuntime? get vm => interpreter;
}

/// Helper class for building builtin functions with proper interpreter context
class BuiltinFunctionBuilder {
  final LibraryContext _context;

  BuiltinFunctionBuilder(this._context);

  /// Create a builtin function with interpreter context
  BuiltinFunction create(Object? Function(List<Object?> args) implementation) {
    final interpreter = _context.vm;
    if (interpreter == null) {
      throw StateError('No interpreter available in context');
    }
    return _BuiltinFunctionImpl(interpreter, implementation);
  }

  /// Create a simple function that doesn't need interpreter context
  /// (for backwards compatibility with existing functions)
  Value createSimple(Object? Function(List<Object?> args) implementation) {
    return Value(implementation);
  }
}

/// Internal implementation of BuiltinFunction that wraps a function
class _BuiltinFunctionImpl extends BuiltinFunction {
  final Object? Function(List<Object?> args) _implementation;

  _BuiltinFunctionImpl(LuaRuntime interpreter, this._implementation);

  @override
  Object? call(List<Object?> args) {
    return _implementation(args);
  }
}

/// Registry for managing all standard libraries
class LibraryRegistry {
  final List<Library> _libraries = [];
  final Map<String, Library> _librariesByName = {};
  final Set<Library> _initialized = {};
  final LuaRuntime _interpreter;

  LibraryRegistry(this._interpreter);

  /// Access the registered libraries
  List<Library> get libraries => List.unmodifiable(_libraries);

  /// Register a library
  void register(Library library) {
    _libraries.add(library);
    if (library.name.isNotEmpty) {
      _librariesByName[library.name] = library;
    }
  }

  /// Initialize all registered libraries
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

/// Extended context for library registration that allows defining functions
class LibraryRegistrationContext extends LibraryContext {
  final Map<String, dynamic> _functionMap;

  LibraryRegistrationContext._internal(LibraryContext base, this._functionMap)
    : super(environment: base.environment, interpreter: base.interpreter);

  /// Define a function in this library
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
