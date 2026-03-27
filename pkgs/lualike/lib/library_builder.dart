/// Public extension surface for registering LuaLike libraries from Dart.
///
/// This library exposes the same registration types that LuaLike uses for its
/// built-in libraries. Import it when you want to add reusable namespaced
/// libraries, builder-style objects with metatables, or native functions that
/// participate in runtime services such as cached primitive values and lazy
/// library loading.
///
/// A minimal library implementation extends `Library`, defines functions inside
/// `registerFunctions()`, and registers an instance through `LibraryRegistry`:
///
/// ```dart
/// import 'package:lualike/library_builder.dart';
/// import 'package:lualike/lualike.dart';
///
/// class GreetingLibrary extends Library {
///   @override
///   String get name => 'greeting';
///
///   @override
///   void registerFunctions(LibraryRegistrationContext context) {
///     final builder = BuiltinFunctionBuilder(context);
///
///     context.define('hello', builder.create((args) {
///       final who = args.isEmpty ? 'world' : Value.wrap(args.first).unwrap();
///       return Value('hello, $who');
///     }));
///   }
/// }
/// ```
library;

export 'src/builtin_function.dart' show BuiltinFunction, BuiltinFunctionGcRefs;
export 'src/environment.dart' show Environment;
export 'src/runtime/lua_runtime.dart'
    show LuaChunkLoadRequest, LuaChunkLoadResult, LuaRuntime;
export 'src/stdlib/library.dart'
    show
        BuiltinFunctionBuilder,
        Library,
        LibraryContext,
        LibraryRegistrationContext,
        LibraryRegistry;
export 'src/value.dart' show Value;
export 'src/value_class.dart' show ValueClass;
