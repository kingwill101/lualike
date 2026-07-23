import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'ffi_types.dart';
import 'lualike_ffi_bindings.g.dart' as native;

const _errorCapacity = 1024;

/// Linux implementation backed by a small libffi bridge.
final class NativeFfiHost implements FfiHost {
  /// Creates a host that uses the bundled native bridge when available.
  const NativeFfiHost();

  @override
  bool get isAvailable => Platform.isLinux;

  @override
  String? get unavailableReason => isAvailable
      ? null
      : 'the lualike FFI bridge currently supports Linux only';

  @override
  String get librarySuffix => Platform.isWindows
      ? '.dll'
      : Platform.isMacOS
      ? '.dylib'
      : '.so';

  void _requireAvailable() {
    if (!isAvailable) {
      throw UnsupportedError(unavailableReason!);
    }
  }

  @override
  FfiLibraryHandle open(String path) {
    _requireAvailable();
    final arena = Arena();
    try {
      final nativePath = path.toNativeUtf8(allocator: arena).cast<Char>();
      final error = arena<Char>(_errorCapacity);
      final handle = native.lualike_ffi_open(nativePath, error, _errorCapacity);
      if (handle == nullptr) {
        throw FfiException(_readError(error, 'unable to load $path'));
      }
      return _NativeLibrary(path, handle);
    } finally {
      arena.releaseAll();
    }
  }

  @override
  FfiFunctionHandle bind(
    FfiLibraryHandle library,
    String symbol,
    FfiType resultType,
    List<FfiType> argumentTypes,
  ) {
    _requireAvailable();
    if (library is! _NativeLibrary) {
      throw ArgumentError.value(library, 'library', 'foreign FFI host handle');
    }
    if (library.isClosed) {
      throw const FfiException('library is closed');
    }
    if (argumentTypes.contains(FfiType.void_)) {
      throw const FfiException('void cannot be used as an argument type');
    }

    final arena = Arena();
    try {
      final nativeName = symbol.toNativeUtf8(allocator: arena).cast<Char>();
      final error = arena<Char>(_errorCapacity);
      final address = native.lualike_ffi_symbol(
        library._handle,
        nativeName,
        error,
        _errorCapacity,
      );
      if (address == nullptr) {
        throw FfiException(_readError(error, 'symbol not found: $symbol'));
      }
      return _NativeFunction(
        library,
        symbol,
        address,
        resultType,
        List.unmodifiable(argumentTypes),
      );
    } finally {
      arena.releaseAll();
    }
  }
}

final class _NativeLibrary implements FfiLibraryHandle {
  _NativeLibrary(this.path, this._handle);

  @override
  final String path;

  Pointer<Void> _handle;

  @override
  bool get isClosed => _handle == nullptr;

  @override
  void close() {
    if (isClosed) {
      return;
    }
    native.lualike_ffi_close(_handle);
    _handle = nullptr;
  }
}

final class _NativeFunction implements FfiFunctionHandle {
  const _NativeFunction(
    this._library,
    this.symbol,
    this._address,
    this.resultType,
    this.argumentTypes,
  );

  final _NativeLibrary _library;
  final Pointer<Void> _address;

  @override
  final String symbol;

  @override
  final FfiType resultType;

  @override
  final List<FfiType> argumentTypes;

  @override
  Object? call(List<Object?> arguments) {
    if (_library.isClosed) {
      throw const FfiException('library is closed');
    }
    if (arguments.length != argumentTypes.length) {
      throw FfiException(
        '$symbol expects ${argumentTypes.length} arguments, '
        'got ${arguments.length}',
      );
    }

    final arena = Arena();
    try {
      final nativeTypes = argumentTypes.isEmpty
          ? nullptr.cast<Int32>()
          : arena<Int32>(argumentTypes.length);
      final nativeArguments = argumentTypes.isEmpty
          ? nullptr.cast<native.lualike_ffi_value>()
          : arena<native.lualike_ffi_value>(argumentTypes.length);
      for (var index = 0; index < argumentTypes.length; index++) {
        final type = argumentTypes[index];
        nativeTypes[index] = type.abiCode;
        _writeArgument(
          nativeArguments[index],
          type,
          arguments[index],
          arena,
          index,
        );
      }

      final result = arena<native.lualike_ffi_value>();
      final error = arena<Char>(_errorCapacity);
      final status = native.lualike_ffi_call(
        _address,
        resultType.abiCode,
        nativeTypes,
        argumentTypes.length,
        nativeArguments,
        result,
        error,
        _errorCapacity,
      );
      if (status != 0) {
        throw FfiException(_readError(error, 'native call failed: $symbol'));
      }
      return _readResult(result.ref, resultType);
    } finally {
      arena.releaseAll();
    }
  }
}

void _writeArgument(
  native.lualike_ffi_value target,
  FfiType type,
  Object? value,
  Arena arena,
  int index,
) {
  Never invalid(String expected) => throw FfiException(
    'argument ${index + 1} must be $expected for ${type.name}',
  );

  switch (type) {
    case FfiType.void_:
      invalid('non-void');
    case FfiType.boolean:
      if (value is! bool) invalid('a boolean');
      target.u8 = value ? 1 : 0;
    case FfiType.i8:
      target.i8 = _integer(value, invalid);
    case FfiType.u8:
      target.u8 = _integer(value, invalid);
    case FfiType.i16:
      target.i16 = _integer(value, invalid);
    case FfiType.u16:
      target.u16 = _integer(value, invalid);
    case FfiType.i32:
      target.i32 = _integer(value, invalid);
    case FfiType.u32:
      target.u32 = _integer(value, invalid);
    case FfiType.i64:
      target.i64 = _integer(value, invalid);
    case FfiType.u64:
      target.u64 = _integer(value, invalid);
    case FfiType.f32:
      target.f32 = _number(value, invalid);
    case FfiType.f64:
      target.f64 = _number(value, invalid);
    case FfiType.pointer:
      if (value == null) {
        target.pointer = nullptr;
      } else if (value is FfiPointer) {
        target.pointer = Pointer<Void>.fromAddress(value.address);
      } else {
        invalid('an FfiPointer or null');
      }
    case FfiType.string:
      if (value is! String) invalid('a string');
      target.pointer = value.toNativeUtf8(allocator: arena).cast<Void>();
  }
}

int _integer(Object? value, Never Function(String) invalid) {
  if (value is! int) invalid('an integer');
  return value;
}

double _number(Object? value, Never Function(String) invalid) {
  if (value is! num) invalid('a number');
  return value.toDouble();
}

Object? _readResult(native.lualike_ffi_value result, FfiType type) {
  return switch (type) {
    FfiType.void_ => null,
    FfiType.boolean => result.u8 != 0,
    FfiType.i8 => result.i8,
    FfiType.u8 => result.u8,
    FfiType.i16 => result.i16,
    FfiType.u16 => result.u16,
    FfiType.i32 => result.i32,
    FfiType.u32 => result.u32,
    FfiType.i64 => result.i64,
    FfiType.u64 => result.u64,
    FfiType.f32 => result.f32,
    FfiType.f64 => result.f64,
    FfiType.pointer => FfiPointer(result.pointer.address),
    FfiType.string =>
      result.pointer == nullptr
          ? null
          : result.pointer.cast<Utf8>().toDartString(),
  };
}

String _readError(Pointer<Char> error, String fallback) {
  if (error.cast<Uint8>().value == 0) {
    return fallback;
  }
  return error.cast<Utf8>().toDartString();
}
