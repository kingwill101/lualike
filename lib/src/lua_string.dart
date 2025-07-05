import 'dart:typed_data';
import 'dart:convert';
import 'package:collection/collection.dart';

class LuaString {
  final Uint8List bytes;

  LuaString(this.bytes);

  factory LuaString.fromDartString(String s) {
    // Use UTF-8 for all strings to avoid decoding issues when characters are
    // outside the Latin-1 range. This ensures `toString()` always produces the
    // original Dart string regardless of content.
    return LuaString(Uint8List.fromList(utf8.encode(s)));
  }

  factory LuaString.fromBytes(List<int> b) => LuaString(Uint8List.fromList(b));

  @override
  String toString() {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      // Fallback for malformed UTF-8, though allowMalformed should handle most cases
      return bytes.map((byte) => String.fromCharCode(byte)).join();
    }
  }

  int get length => bytes.length;

  int operator [](int index) => bytes[index];

  LuaString slice(int start, [int? end]) =>
      LuaString(bytes.sublist(start, end));

  LuaString operator +(LuaString other) =>
      LuaString(Uint8List.fromList([...bytes, ...other.bytes]));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is LuaString) {
      return const ListEquality().equals(bytes, other.bytes);
    } else if (other is String) {
      // Allow comparison with Dart strings by converting LuaString to Dart string
      return toString() == other;
    }
    return false;
  }

  bool operator <(LuaString other) {
    for (int i = 0; i < bytes.length && i < other.bytes.length; i++) {
      if (bytes[i] < other.bytes[i]) return true;
      if (bytes[i] > other.bytes[i]) return false;
    }
    return bytes.length < other.bytes.length;
  }

  bool operator >(LuaString other) {
    for (int i = 0; i < bytes.length && i < other.bytes.length; i++) {
      if (bytes[i] > other.bytes[i]) return true;
      if (bytes[i] < other.bytes[i]) return false;
    }
    return bytes.length > other.bytes.length;
  }

  bool operator <=(LuaString other) => this < other || this == other;

  bool operator >=(LuaString other) => this > other || this == other;

  @override
  int get hashCode => Object.hashAll(bytes);

  static bool _equalBytes(Uint8List a, Uint8List b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
