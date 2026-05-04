import '../../lualike.dart';
import '../coroutine.dart';
import '../table_storage.dart';

Object? _rawTypeName(Object? name) => name is Value ? name.raw : name;

String? _metamethodTypeName(Value value) {
  final rawName = _rawTypeName(value.getMetamethod('__name'));
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
    value = wrapped.raw;
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
    value = wrapped.raw;
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
