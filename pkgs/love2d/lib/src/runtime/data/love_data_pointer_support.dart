part of '../love_runtime.dart';

/// Logical pointer used to emulate LOVE's lightuserdata Data pointers.
///
/// Dart code can't safely expose raw native addresses here, so APIs such as
/// `Data:getPointer` return a lightuserdata handle that preserves object
/// identity and direct byte access for other LOVE APIs that expect pointers.
final class LoveDataPointer {
  LoveDataPointer({required this.identity, required List<int> bytes})
    : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  final Object identity;
  final Uint8List _bytes;

  Uint8List get bytes => _bytes;
}
