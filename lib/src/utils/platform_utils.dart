/// Detect if we're running in product mode (compiled executable)
///
/// When a Dart program is compiled with `dart compile exe`, the resulting binary
/// is built in product mode, and this constant will be true.
/// When running via `dart run` (JIT mode), this will be false.
const bool isProductMode = bool.fromEnvironment(
  'dart.vm.product',
  defaultValue: false,
);
