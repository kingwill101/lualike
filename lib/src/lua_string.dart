import 'dart:typed_data';
import 'dart:convert';

class LuaString {
  final Uint8List bytes;

  LuaString(this.bytes);

  factory LuaString.fromDartString(String s) {
    try {
      // Try Latin-1 encoding first (fastest for ASCII/Latin-1 strings)
      return LuaString(Uint8List.fromList(latin1.encode(s)));
    } catch (e) {
      // If Latin-1 fails, encode as UTF-8 bytes (handles all Unicode characters)
      return LuaString(Uint8List.fromList(utf8.encode(s)));
    }
  }

  factory LuaString.fromBytes(List<int> b) => LuaString(Uint8List.fromList(b));

  @override
  String toString() => latin1.decode(bytes, allowInvalid: true);

  int get length => bytes.length;

  int operator [](int index) => bytes[index];

  LuaString slice(int start, [int? end]) =>
      LuaString(bytes.sublist(start, end));

  LuaString operator +(LuaString other) =>
      LuaString(Uint8List.fromList([...bytes, ...other.bytes]));

  @override
  bool operator ==(Object other) =>
      other is LuaString &&
      bytes.length == other.bytes.length &&
      _equalBytes(bytes, other.bytes);

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
  int get hashCode => bytes.fold(0, (hash, byte) => hash ^ byte.hashCode);

  static bool _equalBytes(Uint8List a, Uint8List b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
