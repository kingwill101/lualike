part of '../love_api_bindings.dart';

/// Returns the LuaJIT-style string form of [value].
///
/// LOVE code commonly expects integer-valued numbers to round-trip without a
/// trailing `.0`, matching LuaJIT's default numeric string formatting.
String _loveLuaJitNumberToString(num value) {
  final text = value.toString();
  if (text.endsWith('.0')) {
    return text.substring(0, text.length - 2);
  }
  return text;
}
