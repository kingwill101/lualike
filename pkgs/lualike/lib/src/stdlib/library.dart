import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/interpreter/interpreter.dart';
import 'package:lualike/src/value.dart';

/// Abstract base class for organizing standard library functions.
///
/// Each library (string, table, math, etc.) should extend this class
/// and define their functions in a structured way.
abstract class Library {
  /// The name of this library (e.g., "string", "table", "math")
  String get name;

  /// The interpreter instance associated with this library
  Interpreter? interpreter;

  /// Optional: metamethods for this library's values
  Map<String, Function>? getMetamethods(Interpreter interpreter) => null;

  /// Register all functions for this library.
  ///
  /// This method is called during interpreter initialization and should
  /// define all builtin functions for this library.
  void registerFunctions(LibraryRegistrationContext context);
}

/// Context provided to libraries during registration
class LibraryContext {
  final Environment environment;
  final Interpreter? interpreter;

  LibraryContext({required this.environment, this.interpreter});

  /// Get the appropriate interpreter instance
  Interpreter? get vm => interpreter;
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

  _BuiltinFunctionImpl(Interpreter interpreter, this._implementation);

  @override
  Object? call(List<Object?> args) {
    return _implementation(args);
  }
}

/// Registry for managing all standard libraries
class LibraryRegistry {
  final List<Library> _libraries = [];
  final Interpreter _interpreter;

  LibraryRegistry(this._interpreter);

  /// Access the registered libraries
  List<Library> get libraries => List.unmodifiable(_libraries);

  /// Register a library
  void register(Library library) {
    _libraries.add(library);
  }

  /// Initialize all registered libraries
  void initializeAll() {
    final context = LibraryContext(
      environment: _interpreter.getCurrentEnv(),
      interpreter: _interpreter,
    );

    for (final library in _libraries) {
      _initializeLibrary(library, context);
    }
  }

  void _initializeLibrary(Library library, LibraryContext context) {
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
    } else {
      // Namespaced library: create library table
      final metamethods = context.interpreter != null
          ? library.getMetamethods(context.interpreter!)
          : null;
      final libraryValue = metamethods != null
          ? Value(libraryTable, metatable: metamethods)
          : Value(libraryTable);

      context.environment.define(library.name, libraryValue);
    }
  }
}

/// Extended context for library registration that allows defining functions
class LibraryRegistrationContext extends LibraryContext {
  final Map<String, dynamic> _functionMap;

  LibraryRegistrationContext._internal(LibraryContext base, this._functionMap)
    : super(environment: base.environment, interpreter: base.interpreter);

  /// Define a function in this library
  void define(String name, dynamic function) {
    _functionMap[name] = function;
  }
}
