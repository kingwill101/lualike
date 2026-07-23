/// Native FFI host layer for lualike (opt-in).
///
/// Consumers can open shared libraries with [NativeFfiHost] and describe
/// function signatures with [FfiType].
library;

export 'src/ffi_host.dart';
export 'src/ffi_types.dart';
