part of '../love_api_bindings.dart';

/// An exception thrown when strict LOVE UTF-8 decoding fails.
final class _LoveUtf8DecodeError implements Exception {
  const _LoveUtf8DecodeError(this.message);

  /// The human-readable reason the decode failed.
  final String message;
}

/// Decodes the UTF-8 code point beginning at [index].
///
/// Throws [_LoveUtf8DecodeError] when the byte sequence is truncated, invalid,
/// overlong, or resolves to a code point rejected by
/// [_isValidGlyphStringCodepoint].
({int codePoint, int nextIndex}) _decodeLoveUtf8CodePointAt(
  List<int> bytes,
  int index,
) {
  final first = bytes[index];
  if (first <= 0x7f) {
    return (codePoint: first, nextIndex: index + 1);
  }

  final sequenceLength = switch (first) {
    >= 0xc2 && <= 0xdf => 2,
    >= 0xe0 && <= 0xef => 3,
    >= 0xf0 && <= 0xf4 => 4,
    _ => throw const _LoveUtf8DecodeError('Invalid UTF-8'),
  };

  if (index + sequenceLength > bytes.length) {
    throw const _LoveUtf8DecodeError('Not enough space');
  }

  var codePoint = first & ((1 << (8 - sequenceLength - 1)) - 1);
  for (var offset = 1; offset < sequenceLength; offset++) {
    final continuation = bytes[index + offset];
    if ((continuation & 0xc0) != 0x80) {
      throw const _LoveUtf8DecodeError('Invalid UTF-8');
    }
    codePoint = (codePoint << 6) | (continuation & 0x3f);
  }

  final minimumCodePoint = switch (sequenceLength) {
    2 => 0x80,
    3 => 0x800,
    4 => 0x10000,
    _ => 0,
  };
  if (codePoint < minimumCodePoint) {
    throw const _LoveUtf8DecodeError('Invalid UTF-8');
  }

  if (!_isValidGlyphStringCodepoint(codePoint)) {
    throw const _LoveUtf8DecodeError('Invalid code point');
  }

  return (codePoint: codePoint, nextIndex: index + sequenceLength);
}

/// Decodes [bytes] as a strictly validated LOVE UTF-8 string.
String _decodeLoveUtf8Strict(List<int> bytes) {
  final buffer = StringBuffer();
  var index = 0;

  while (index < bytes.length) {
    final decoded = _decodeLoveUtf8CodePointAt(bytes, index);
    buffer.writeCharCode(decoded.codePoint);
    index = decoded.nextIndex;
  }

  return buffer.toString();
}

/// Decodes only the first UTF-8 code point in [bytes].
///
/// Returns an empty string when [bytes] is empty.
String _decodeLoveUtf8FirstCodepoint(List<int> bytes) {
  if (bytes.isEmpty) {
    return '';
  }

  final decoded = _decodeLoveUtf8CodePointAt(bytes, 0);
  return String.fromCharCode(decoded.codePoint);
}
