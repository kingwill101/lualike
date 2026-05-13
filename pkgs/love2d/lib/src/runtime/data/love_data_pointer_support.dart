part of '../love_runtime.dart';

/// Logical pointer used to emulate LOVE's lightuserdata Data pointers.
///
/// Dart code can't safely expose raw native addresses here, so APIs such as
/// `Data:getPointer` return a lightuserdata handle that preserves object
/// identity and direct byte access for other LOVE APIs that expect pointers.
final class LoveDataPointer {
  /// Creates a logical data pointer with stable [identity] and backing [bytes].
  LoveDataPointer({required this.identity, required List<int> bytes})
    : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  /// The object identity used to preserve pointer equality semantics.
  final Object identity;

  /// The bytes exposed through this logical pointer.
  final Uint8List _bytes;

  /// The bytes referenced by this logical pointer.
  Uint8List get bytes => _bytes;
}
