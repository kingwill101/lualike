/// Primitive native types supported by the first FFI ABI.
enum FfiType {
  void_(0, 'void'),
  boolean(1, 'bool'),
  i8(2, 'i8'),
  u8(3, 'u8'),
  i16(4, 'i16'),
  u16(5, 'u16'),
  i32(6, 'i32'),
  u32(7, 'u32'),
  i64(8, 'i64'),
  u64(9, 'u64'),
  f32(10, 'f32'),
  f64(11, 'f64'),
  pointer(12, 'pointer'),
  string(13, 'string');

  const FfiType(this.abiCode, this.name);

  /// Stable integer passed across the native bridge ABI.
  final int abiCode;

  /// Name used in runtime declarations.
  final String name;

  /// Parses the declaration [name] used by the Lua-facing API.
  ///
  /// Throws a [FormatException] when [name] is not part of the supported ABI.
  static FfiType parse(String name) {
    for (final type in values) {
      if (type.name == name) {
        return type;
      }
    }
    throw FormatException('unsupported FFI type: $name');
  }
}

/// Failure while loading, binding, or calling native code.
final class FfiException implements Exception {
  /// Creates an FFI failure with a human-readable [message].
  const FfiException(this.message);

  /// Description of the failed load, bind, or native call operation.
  final String message;

  @override
  String toString() => 'FfiException: $message';
}

/// Opaque address returned from or supplied to native code.
final class FfiPointer {
  /// Creates an opaque pointer wrapper for [address].
  const FfiPointer(this.address);

  /// Process address represented by this pointer.
  final int address;

  /// Whether this pointer represents the native null pointer.
  bool get isNull => address == 0;

  @override
  String toString() => 'ffi.pointer(0x${address.toRadixString(16)})';
}

/// A dynamically loaded shared library.
abstract interface class FfiLibraryHandle {
  /// Path or platform library name used to open this handle.
  String get path;

  /// Whether this handle has been closed.
  bool get isClosed;

  /// Releases the dynamic library handle.
  ///
  /// Calling this method more than once has no effect. Functions previously
  /// bound from this handle reject subsequent calls.
  void close();
}

/// A native symbol bound to a concrete runtime signature.
abstract interface class FfiFunctionHandle {
  /// Exported symbol represented by this function.
  String get symbol;

  /// Native result type used for calls.
  FfiType get resultType;

  /// Ordered native argument types used for calls.
  List<FfiType> get argumentTypes;

  /// Invokes the native function with [arguments].
  ///
  /// Throws [FfiException] when the argument count or value types do not match
  /// the declaration, or when the owning library is closed.
  Object? call(List<Object?> arguments);
}

/// Platform capability for loading and calling shared libraries.
abstract interface class FfiHost {
  /// Whether this runtime has a supported native backend.
  bool get isAvailable;

  /// Explanation returned when [isAvailable] is false.
  String? get unavailableReason;

  /// Conventional shared-library suffix for the current platform.
  String get librarySuffix;

  /// Opens the shared library at [path].
  ///
  /// [path] may also be a platform loader name such as `libc.so.6`.
  FfiLibraryHandle open(String path);

  /// Resolves [symbol] and binds it to a runtime-declared signature.
  FfiFunctionHandle bind(
    FfiLibraryHandle library,
    String symbol,
    FfiType resultType,
    List<FfiType> argumentTypes,
  );
}
