/// Web-platform implementations of 64-bit typed-data operations.
///
/// `dart2js` does not support `ByteData` 64-bit accessors (`setInt64`,
/// `setUint64`, `getInt64`, `getUint64`), and JavaScript bitwise operators
/// truncate to 32 bits. These functions work around both limitations by
/// splitting 64-bit values into two 32-bit words and using `BigInt`
/// arithmetic to reconstruct full-range values.
library;

import 'dart:typed_data';

/// Writes a signed 64-bit integer to [data] at [offset] in little-endian order.
///
/// The value is split into low and high 32-bit words using `BigInt` to avoid
/// JS bitwise truncation. The low word is stored as `uint32` and the high word
/// as `int32` (preserving sign).
void writeInt64(ByteData data, int offset, int value) {
  // Split into low and high 32-bit words using division to avoid JS
  // 32-bit bitwise truncation on negative values.
  final big = BigInt.from(value);
  final low = (big & BigInt.from(0xFFFFFFFF)).toInt();
  final high = (big >> 32).toInt();
  data.setUint32(offset, low, Endian.little);
  data.setInt32(offset + 4, high, Endian.little);
}

/// Writes an unsigned 64-bit integer to [data] at [offset] in little-endian order.
///
/// Both 32-bit words are stored as `uint32` since the value is unsigned.
void writeUint64(ByteData data, int offset, int value) {
  final big = BigInt.from(value);
  final low = (big & BigInt.from(0xFFFFFFFF)).toInt();
  final high = (big >> 32).toInt();
  data.setUint32(offset, low, Endian.little);
  data.setUint32(offset + 4, high, Endian.little);
}

/// Reads a signed 64-bit integer from [data] at [offset] in little-endian order.
///
/// Reads two 32-bit words and reconstructs the full 64-bit value using
/// `BigInt` arithmetic. Negative values (high bit set) are converted from
/// unsigned to signed representation.
int readInt64(ByteData data, int offset) {
  final low = data.getUint32(offset, Endian.little);
  final high = data.getInt32(offset + 4, Endian.little);
  // Reconstruct using BigInt to avoid JS 32-bit bitwise shift limitation.
  final result = (BigInt.from(high) << 32) | BigInt.from(low);
  // Convert from unsigned 64-bit to signed 64-bit Dart int.
  if (result >= (BigInt.one << 63)) {
    return (result - (BigInt.one << 64)).toInt();
  }
  return result.toInt();
}

/// Reads an unsigned 64-bit integer from [data] at [offset] in little-endian order.
///
/// Reads two 32-bit words and reconstructs the full 64-bit value using
/// `BigInt` arithmetic.
int readUint64(ByteData data, int offset) {
  final low = data.getUint32(offset, Endian.little);
  final high = data.getUint32(offset + 4, Endian.little);
  return ((BigInt.from(high) << 32) | BigInt.from(low)).toInt();
}
