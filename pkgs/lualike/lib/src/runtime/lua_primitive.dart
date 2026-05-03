import 'package:lualike/src/lua_string.dart';

/// Returns whether [slot] is one of Lua's immediate primitive payloads.
bool isLuaPrimitiveSlot(Object? slot) =>
    slot == null ||
    slot is bool ||
    slot is num ||
    slot is BigInt ||
    slot is String ||
    slot is LuaString;
