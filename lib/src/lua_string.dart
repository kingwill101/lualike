import 'dart:typed_data';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'value.dart';

/// String interning cache for short strings (Lua-like behavior)
/// In Lua, short strings are typically internalized while long strings are not
class StringInterning {
  static const int shortStringThreshold = 40; // Lua 5.4 uses 40 characters
  static final Map<String, LuaString> _internCache = <String, LuaString>{};

  /// Creates or retrieves an interned LuaString
  static LuaString intern(String content) {
    // Intern all string literals (Lua interns string literals regardless of length)
    return _internCache.putIfAbsent(
      content,
      () => LuaString._internal(Uint8List.fromList(utf8.encode(content))),
    );
  }

  /// Creates a Value with proper string interning
  static Value createStringValue(String content) {
    return Value(intern(content));
  }
}

class LuaString {
  final Uint8List bytes;

  LuaString._internal(this.bytes);

  factory LuaString(Uint8List bytes) {
    // For internal use only - doesn't intern
    return LuaString._internal(bytes);
  }

  factory LuaString.fromDartString(String s) {
    // Use StringInterning for proper interning behavior
    return StringInterning.intern(s);
  }

  factory LuaString.fromBytes(List<int> b) {
    // Convert bytes to string for interning lookup
    final s = utf8.decode(b, allowMalformed: true);
    return LuaString.fromDartString(s);
  }

  @override
  String toString() {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      // Fallback for malformed UTF-8, though allowMalformed should handle most cases
      return bytes.map((byte) => String.fromCharCode(byte)).join();
    }
  }

  /// Convert to string using Latin-1 interpretation (for Lua string display)
  String toLatin1String() {
    return bytes.map((byte) => String.fromCharCode(byte)).join();
  }

  int get length => bytes.length;

  int operator [](int index) => bytes[index];

  LuaString slice(int start, [int? end]) {
    final newBytes = bytes.sublist(start, end);
    return LuaString.fromBytes(newBytes);
  }

  LuaString operator +(LuaString other) {
    final newBytes = [...bytes, ...other.bytes];
    // Don't intern concatenated strings - only string literals should be interned
    return LuaString._internal(Uint8List.fromList(newBytes));
  }

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
}
