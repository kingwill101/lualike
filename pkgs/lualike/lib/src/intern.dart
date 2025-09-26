import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

/// String interning cache for short strings (Lua-like behavior)
/// In Lua, short strings are typically internalized while long strings are not
class StringInterning {
  static const int shortStringThreshold = 40; // Lua 5.4 uses 40 characters
  static final Map<String, LuaString> _internCache = <String, LuaString>{};

  /// Creates or retrieves an interned LuaString
  static LuaString intern(String content) {
    // Only intern short strings
    if (content.length <= shortStringThreshold) {
      return _internCache.putIfAbsent(
        content,
        () => LuaString.fromDartString(content),
      );
    } else {
      // Long strings are not interned - always create new instances
      return LuaString.fromDartString(content);
    }
  }

  /// Creates a Value with proper string interning
  static Value createStringValue(String content) {
    return Value(intern(content));
  }
}
