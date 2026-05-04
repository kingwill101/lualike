import '../../lualike.dart';
import '../coroutine.dart';
import '../runtime/lua_slot.dart';
import '../table_storage.dart';

String? _metamethodTypeName(Value value) {
  final rawName = rawLuaSlot(value.getMetamethod('__name'));
  return switch (rawName) {
    final String stringName => stringName,
    final LuaString stringName => stringName.toString(),
    _ => null,
  };
}

String getLuaType(Object? value) {
  if (value case final Value wrapped) {
    final typeName = _metamethodTypeName(wrapped);
    if (typeName != null) {
      return typeName;
    }
    value = rawLuaSlot(wrapped);
  }
  if (value case final Map<dynamic, dynamic> table) {
    final wrapped = Value.lookupCanonicalTableWrapper(table);
    if (wrapped != null) {
      final typeName = _metamethodTypeName(wrapped);
      if (typeName != null) {
        return typeName;
      }
    }
  }
  final t = value;
  return switch (t) {
    null => 'nil',
    String() || LuaString() => 'string',
    num() || BigInt() => 'number',
    bool() => 'boolean',
    Function() || BuiltinFunction() || LuaCallableArtifact() => 'function',
    Map() || List() || TableStorage() => 'table',
    Coroutine() => 'thread',
    _ when t.runtimeType.toString() == 'LuaFile' => 'userdata',
    _
        when t.runtimeType.toString() == 'Box' ||
            t.runtimeType.toString().startsWith('Box<') =>
      'light userdata',
    _ => 'userdata',
  };
}

String getLuaBaseType(Object? value) {
  if (value case final Value wrapped) {
    value = rawLuaSlot(wrapped);
  }
  final t = value;
  return switch (t) {
    null => 'nil',
    String() || LuaString() => 'string',
    num() || BigInt() => 'number',
    bool() => 'boolean',
    Function() || BuiltinFunction() || LuaCallableArtifact() => 'function',
    Map() || List() || TableStorage() => 'table',
    Coroutine() => 'thread',
    _ => 'userdata',
  };
}
