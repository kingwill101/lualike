/// Native-platform implementations of 64-bit typed-data operations.
///
/// These functions delegate directly to `ByteData`'s built-in 64-bit
/// accessors (`setInt64`, `setUint64`, `getInt64`, `getUint64`), which
/// are fully supported on native Dart VM and AOT targets.
///
/// On the web, these implementations are replaced by [byte_data_web.dart]
/// because `dart2js` does not support 64-bit typed-data accessors.
library;

import 'dart:typed_data';

/// Writes a signed 64-bit integer to [data] at [offset] in little-endian order.
void writeInt64(ByteData data, int offset, int value) {
  data.setInt64(offset, value, Endian.little);
}

/// Writes an unsigned 64-bit integer to [data] at [offset] in little-endian order.
void writeUint64(ByteData data, int offset, int value) {
  data.setUint64(offset, value, Endian.little);
}

/// Reads a signed 64-bit integer from [data] at [offset] in little-endian order.
int readInt64(ByteData data, int offset) {
  return data.getInt64(offset, Endian.little);
}

/// Reads an unsigned 64-bit integer from [data] at [offset] in little-endian order.
int readUint64(ByteData data, int offset) {
  return data.getUint64(offset, Endian.little);
}
