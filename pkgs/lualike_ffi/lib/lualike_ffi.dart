/// FFI library for lualike (opt-in).
///
/// Consumers who need native FFI support must explicitly depend on this
/// package and call [registerFfiLibrary]:
/// ```dart
/// import 'package:lualike/lualike.dart';
/// import 'package:lualike_ffi/lualike_ffi.dart';
///
/// void main() {
///   final vm = LuaRuntime();
///   initializeStandardLibrary(vm: vm);
///   registerFfiLibrary(vm.libraryRegistry);
/// }
/// ```
library;

export 'src/lualike_ffi_library.dart' show registerFfiLibrary, FfiLibrary, FfiException, FfiType, FfiPointer;
export 'src/ffi_types.dart';
