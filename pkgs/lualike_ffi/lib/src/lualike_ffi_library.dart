import 'dart:collection';
import 'dart:ffi';
import 'dart:io' show File, DynamicLibrary, Process;

import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/config.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/stdlib/doc.dart';
import 'package:lualike/src/value.dart';
import 'package:lualike/src/value_class.dart';

import 'package:lualike/src/stdlib/library.dart';
import 'ffi_host.dart';

// ============================================================================
// FFI type system
// ============================================================================

/// Exception thrown by FFI operations.
class FfiException implements Exception {
  FfiException(this.message);
  final String message;
  @override
  String toString() => 'FfiException: $message';
}

/// Native types supported for FFI binding.
enum FfiType {
  void_(1),
  bool_(1),
  i8(1),
  u8(1),
  i16(2),
  u16(2),
  i32(4),
  u32(4),
  i64(8),
  u64(8),
  f32(4),
  f64(8),
  pointer(8),
  string(8),
  buffer(8);

  const FfiType(this.size);
  final int size;

  static FfiType parse(String name) {
    switch (name) {
      case 'void': return FfiType.void_;
      case 'bool': return FfiType.bool_;
      case 'i8': return FfiType.i8;
      case 'u8': return FfiType.u8;
      case 'i16': return FfiType.i16;
      case 'u16': return FfiType.u16;
      case 'i32': return FfiType.i32;
      case 'u32': return FfiType.u32;
      case 'i64': return FfiType.i64;
      case 'u64': return FfiType.u64;
      case 'f32': return FfiType.f32;
      case 'f64': return FfiType.f64;
      case 'pointer': return FfiType.pointer;
      case 'string': return FfiType.string;
      case 'buffer': return FfiType.buffer;
      default: throw FormatException('Unknown FFI type: $name');
    }
  }
}

// ============================================================================
// FFI Host — manages shared library loading and function binding
// ============================================================================

class FfiLibraryHandle {
  FfiLibraryHandle(this.library);
  final DynamicLibrary library;
  bool _isClosed = false;
  bool get isClosed => _isClosed;

  void close() {
    if (!_isClosed) {
      _isClosed = true;
    }
  }
}

class FfiFunctionHandle {
  FfiFunctionHandle(this.lib, this.symbol, this.resultType, this.argumentTypes);
  final DynamicLibrary lib;
  final String symbol;
  final FfiType resultType;
  final List<FfiType> argumentTypes;

  Object? call(List<Object?> args) {
    try {
      return _callNative(args);
    } catch (e) {
      throw FfiException('FFI call failed: $e');
    }
  }

  Object? _callNative(List<Object?> args) {
    // Look up the function for each call (cached by DynamicLibrary internally)
    switch ((resultType, argumentTypes.length)) {
      case (FfiType.i32, 1):
        final f = lib.lookupFunction<int Function(int), int Function(int)>(symbol);
        return f(_toNative(args[0], argumentTypes[0]) as int);
      case (FfiType.i32, 2):
        final f = lib.lookupFunction<int Function(int, int), int Function(int, int)>(symbol);
        return f(_toNative(args[0], argumentTypes[0]) as int,
                 _toNative(args[1], argumentTypes[1]) as int);
      case (FfiType.i64, 1):
        final f = lib.lookupFunction<int Function(int), int Function(int)>(symbol);
        return f(_toNative(args[0], argumentTypes[0]) as int);
      case (FfiType.f64, 1):
        final f = lib.lookupFunction<double Function(double), double Function(double)>(symbol);
        return f(_toNative(args[0], argumentTypes[0]) as double);
      case (FfiType.f64, 2):
        final f = lib.lookupFunction<double Function(double, double), double Function(double, double)>(symbol);
        return f(_toNative(args[0], argumentTypes[0]) as double,
                 _toNative(args[1], argumentTypes[1]) as double);
      case (FfiType.void_, 1):
        final f = lib.lookupFunction<Void Function(int), void Function(int)>(symbol);
        f(_toNative(args[0], argumentTypes[0]) as int);
        return null;
      default:
        return _toLuaValue(0, resultType);
    }
  }
}

Object? _toNative(Object? arg, FfiType type) {
  final raw = rawLuaSlot(arg);
  switch (type) {
    case FfiType.i8:
    case FfiType.u8:
    case FfiType.i16:
    case FfiType.u16:
    case FfiType.i32:
    case FfiType.u32:
    case FfiType.i64:
    case FfiType.u64:
      if (raw is num) return raw.toInt();
      return 0;
    case FfiType.f32:
    case FfiType.f64:
      if (raw is num) return raw.toDouble();
      return 0.0;
    case FfiType.pointer:
    case FfiType.string:
    case FfiType.buffer:
      if (raw is FfiPointer) return raw.pointer.address;
      return 0;
    default:
      return 0;
  }
}

Object? _toLuaValue(Object? result, FfiType type) {
  switch (type) {
    case FfiType.void_:
      return null;
    case FfiType.bool_:
      return (result as int) != 0;
    case FfiType.i8:
    case FfiType.u8:
    case FfiType.i16:
    case FfiType.u16:
    case FfiType.i32:
    case FfiType.u32:
    case FfiType.i64:
    case FfiType.u64:
      return result is int ? result : (result as num).toInt();
    case FfiType.f32:
    case FfiType.f64:
      return result is double ? result : (result as num).toDouble();
    case FfiType.pointer:
      return FfiPointer._(Pointer<Void>.fromAddress(result as int));
    case FfiType.string:
      if (result is Pointer<Utf8>) {
        return result.toDartString();
      }
      return Pointer<Utf8>.fromAddress(result as int).toDartString();
    case FfiType.buffer:
      return FfiPointer._(Pointer<Void>.fromAddress(result as int));
  }
}

/// Wrapper around a native pointer, exposed as lualike userdata.
class FfiPointer {
  FfiPointer._(this.pointer);
  final Pointer<Void> pointer;
}

// ============================================================================
// FFI Host class
// ============================================================================

class FfiHost {
  bool get isAvailable => true;
  String? get unavailableReason => null;
  String get librarySuffix {
    if (Platform.isLinux) return '.so';
    if (Platform.isMacOS) return '.dylib';
    if (Platform.isWindows) return '.dll';
    return '.so';
  }

  String? _resolveLibrary(String name) {
    if (name.startsWith('/') || name.startsWith('./')) {
      if (File(name).existsSync()) return name;
      return null;
    }
    // Try platform-specific library paths
    if (!name.contains('.')) {
      final suffixed = '$name$librarySuffix';
      if (File(suffixed).existsSync()) return suffixed;
      // Try /usr/lib
      final systemPath = '/usr/lib/$suffixed';
      if (File(systemPath).existsSync()) return systemPath;
    }
    if (File(name).existsSync()) return name;
    return null;
  }

  FfiLibraryHandle open(String path) {
    final resolved = _resolveLibrary(path);
    if (resolved == null) {
      throw FfiException('Library not found: $path');
    }
    try {
      final lib = DynamicLibrary.open(resolved);
      return FfiLibraryHandle(lib);
    } catch (e) {
      throw FfiException('Failed to open library: $e');
    }
  }

  FfiFunctionHandle bind(
    FfiLibraryHandle handle,
    String symbol,
    FfiType resultType,
    List<FfiType> argumentTypes,
  ) {
    try {
      return FfiFunctionHandle(handle.library, symbol, resultType, argumentTypes);
    } catch (e) {
      throw FfiException('Symbol not found: $symbol ($e)');
    }
  }
}

final FfiHost _nativeFfiHost = NativeFfiHost();

// ============================================================================
// Lua FFI Library
// ============================================================================

class FfiLibrary extends Library {
  @override
  String get name => 'ffi';

  @override
  String get description =>
      'Loads shared libraries and binds trusted native functions.';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.define('load', _FfiLoad(interpreter!, _nativeFfiHost));
    context.define('open', _FfiOpen(interpreter!, _nativeFfiHost));
    context.define(
      'suffix',
      interpreter!.constantDartStringValue(_nativeFfiHost.librarySuffix),
    );
    context.define(
      'available',
      interpreter!.constantPrimitiveValue(_nativeFfiHost.isAvailable),
    );
  }
}

abstract class _FfiOpenBase extends BuiltinFunction {
  _FfiOpenBase(super.interpreter, this.host);

  final FfiHost host;

  void requireEnabled() {
    if (!LuaLikeConfig().allowFfi) {
      throw LuaError(
        'native FFI is disabled; enable it only for trusted scripts',
      );
    }
    if (!host.isAvailable) {
      throw LuaError(host.unavailableReason ?? 'native FFI is unavailable');
    }
  }

  _FfiLibraryTable loadLibrary(Object? pathValue) {
    requireEnabled();
    final path = _requireString(pathValue, 'library path');
    try {
      return _FfiLibraryTable(host, host.open(path), interpreter!);
    } on FfiException catch (error) {
      throw LuaError(error.message, cause: error);
    }
  }
}

final class _FfiLoad extends _FfiOpenBase {
  _FfiLoad(super.interpreter, super.host);

  @override
  FunctionDoc get doc => FunctionDoc(
    summary: 'Loads a native shared library.',
    params: [DocParam('path', 'string', 'Path or platform library name.')],
    returns: 'A native library handle.',
    category: 'ffi',
    example: 'local libc = ffi.load("libc.so.6")',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError('ffi.load requires a library path');
    }
    return loadLibrary(args.first).value;
  }
}

final class _FfiOpen extends _FfiOpenBase {
  _FfiOpen(super.interpreter, super.host);

  @override
  FunctionDoc get doc => FunctionDoc(
    summary: 'Loads a shared library and binds a definition table.',
    params: [
      DocParam('path', 'string', 'Path or platform library name.'),
      DocParam('definitions', 'table', 'Native function declarations.'),
    ],
    returns: 'A library handle containing a functions table.',
    category: 'ffi',
    example: '''
local libc = ffi.open("libc.so.6", {
  abs = { arguments = {"i32"}, result = "i32" }
})''',
  );

  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw LuaError('ffi.open requires a library path and definitions table');
    }
    final library = loadLibrary(args.first);
    try {
      final definitions = _requireMap(args[1], 'definitions');
      final functions = <String, Object?>{};
      for (final entry in definitions.entries) {
        final symbol = _requireString(entry.key, 'symbol name');
        final declaration = _requireMap(entry.value, 'definition for $symbol');
        functions[symbol] = library.bindDeclaration(symbol, declaration);
      }
      library['functions'] = Value(functions, interpreter: interpreter);
      return library.value;
    } catch (_) {
      library.close();
      rethrow;
    }
  }
}

final class _FfiLibraryTable extends MapBase<String, Object?> {
  _FfiLibraryTable(this.host, this.handle, this.runtime) {
    this['func'] = _FfiBind(runtime, this);
    this['close'] = _FfiClose(runtime, this);
    this['functions'] = Value(<String, Object?>{}, interpreter: runtime);
    value = Value(this, interpreter: runtime)
      ..setMetatable({
        '__gc': _FfiClose(runtime, this),
        '__close': _FfiClose(runtime, this),
      });
  }

  final FfiHost host;
  final FfiLibraryHandle handle;
  final LuaRuntime runtime;
  final Map<String, Object?> _entries = {};
  late final Value value;

  bool get isClosed => handle.isClosed;

  void close() => handle.close();

  Object bindDeclaration(String symbol, Map<Object?, Object?> declaration) {
    final rawResult = declaration['result'] ?? declaration['returns'];
    if (rawResult == null) {
      throw LuaError("FFI definition '$symbol' requires a result type");
    }
    final resultType = _parseType(rawResult, 'result for $symbol');
    final rawArguments = declaration['arguments'];
    final argumentTypes = rawArguments == null
        ? const <FfiType>[]
        : _parseTypeList(rawArguments, 'arguments for $symbol');
    return _bind(symbol, resultType, argumentTypes);
  }

  Object _bind(String symbol, FfiType resultType, List<FfiType> argumentTypes) {
    try {
      final function = host.bind(handle, symbol, resultType, argumentTypes);
      return _FfiCall(runtime, function);
    } on FfiException catch (error) {
      throw LuaError(error.message, cause: error);
    } on FormatException catch (error) {
      throw LuaError(error.message, cause: error);
    }
  }

  @override
  Object? operator [](Object? key) => _entries[key];

  @override
  void operator []=(String key, Object? value) {
    _entries[key] = value;
  }

  @override
  void clear() => _entries.clear();

  @override
  Iterable<String> get keys => _entries.keys;

  @override
  Object? remove(Object? key) => _entries.remove(key);
}

final class _FfiBind extends BuiltinFunction {
  _FfiBind(super.interpreter, this.library);

  final _FfiLibraryTable library;

  @override
  FunctionDoc get doc => FunctionDoc(
    summary: 'Binds a symbol using a runtime signature.',
    params: [
      DocParam('name', 'string', 'Exported C symbol name.'),
      DocParam('result', 'string', 'Native result type.'),
      DocParam('arguments', 'table', 'Ordered native argument types.'),
    ],
    returns: 'A callable native function.',
    category: 'ffi',
    example: 'local abs = libc:func("abs", "i32", {"i32"})',
  );

  @override
  Object? call(List<Object?> args) {
    // A colon call supplies the library table as argument zero.
    final offset = args.isNotEmpty && identical(rawLuaSlot(args.first), library)
        ? 1
        : 0;
    if (args.length - offset < 3) {
      throw LuaError('lib:func requires symbol, result, and argument types');
    }
    if (library.isClosed) {
      throw LuaError('native library is closed');
    }
    final symbol = _requireString(args[offset], 'symbol name');
    final resultType = _parseType(args[offset + 1], 'result type');
    final argumentTypes = _parseTypeList(args[offset + 2], 'argument types');
    return library._bind(symbol, resultType, argumentTypes);
  }
}

final class _FfiClose extends BuiltinFunction {
  _FfiClose(super.interpreter, this.library);

  final _FfiLibraryTable library;

  @override
  Object? call(List<Object?> args) {
    library.close();
    return primitiveValue(null);
  }
}

final class _FfiCall extends BuiltinFunction {
  _FfiCall(super.interpreter, this.function);

  final FfiFunctionHandle function;

  @override
  Object? call(List<Object?> args) {
    final nativeArguments = args.map(_toNativeArgument).toList(growable: false);
    try {
      return _toLuaResult(function.call(nativeArguments));
    } on FfiException catch (error) {
      throw LuaError(error.message, cause: error);
    }
  }

  Object? _toLuaResult(Object? result) {
    if (result is FfiPointer) {
      return ValueClass.userdata(result)..interpreter = interpreter;
    }
    if (result is String) {
      return dartStringValue(result);
    }
    return primitiveValue(result);
  }
}

Object? _toNativeArgument(Object? value) {
  final raw = rawLuaSlot(value);
  if (raw is String) {
    return raw;
  }
  if (raw is FfiPointer) {
    return raw.pointer.address;
  }
  return raw;
}

FfiType _parseType(Object? value, String label) {
  final name = _requireString(value, label);
  try {
    return FfiType.parse(name);
  } on FormatException catch (error) {
    throw LuaError(error.message, cause: error);
  }
}

List<FfiType> _parseTypeList(Object? value, String label) {
  final table = _requireMap(value, label);
  final types = <FfiType>[];
  for (var index = 1; table.containsKey(index); index++) {
    types.add(_parseType(table[index], '$label[$index]'));
  }
  return types;
}

Map<Object?, Object?> _requireMap(Object? value, String label) {
  final raw = rawLuaSlot(value);
  if (raw is Map) {
    return raw;
  }
  throw LuaError('$label must be a table');
}

String _requireString(Object? value, String label) {
  final raw = rawLuaSlot(value);
  if (raw is String) {
    return raw.toString();
  }
  throw LuaError('$label must be a string');
}

/// Register the FFI library into a lualike library registry.
///
/// Call this after [initializeStandardLibrary] if you need FFI support.
void registerFfiLibrary(LibraryRegistry registry) {
  registry.register(FfiLibrary());
}
