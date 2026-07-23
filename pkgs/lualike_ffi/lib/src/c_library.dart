import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Native bridge compiled by this package's build hook.
final lualikeFfiBridge = CBuilder.library(
  name: 'lualike_ffi_bridge',
  assetName: 'src/lualike_ffi_bindings.g.dart',
  sources: const ['native/lualike_ffi.c'],
  includes: const ['native'],
  libraries: const ['ffi', 'dl'],
  std: 'c11',
);
