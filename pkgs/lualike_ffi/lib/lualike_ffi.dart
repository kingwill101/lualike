/// Runtime-declared calls into native shared libraries.
///
/// This package contains no lualike runtime dependency. The interpreter adapts
/// this API into its `ffi` library, while other embedders can use the backend
/// directly.
library;

export 'src/ffi_host.dart' show NativeFfiHost;
export 'src/ffi_types.dart';
