import 'package:lualike/src/lua_string.dart';

/// Returns whether [slot] is one of Lua's immediate primitive payloads.
bool isLuaPrimitiveSlot(Object? slot) =>
    slot == null ||
    slot is bool ||
    slot is num ||
    slot is BigInt ||
    slot is String ||
    slot is LuaString;

/// Returns whether [slot] is an immediate non-string Lua payload.
///
/// Strings are primitive-like for weak-table and wrapper construction paths,
/// but they still have string-metatable and GC-accounting behavior that many
/// scalar fast paths must preserve.
bool isLuaScalarPrimitiveSlot(Object? slot) =>
    slot == null || slot is bool || slot is num || slot is BigInt;
