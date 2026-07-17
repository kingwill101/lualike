import 'ffi_types.dart';

/// FFI backend used where native FFI is unavailable.
final class NativeFfiHost implements FfiHost {
  /// Creates an unavailable host for runtimes without `dart:ffi`.
  const NativeFfiHost();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'native FFI is unavailable on this platform';

  @override
  String get librarySuffix => '';

  Never _unsupported() => throw UnsupportedError(unavailableReason);

  @override
  FfiLibraryHandle open(String path) => _unsupported();

  @override
  FfiFunctionHandle bind(
    FfiLibraryHandle library,
    String symbol,
    FfiType resultType,
    List<FfiType> argumentTypes,
  ) => _unsupported();
}
