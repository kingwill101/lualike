import '../../lualike.dart';
import '../coroutine.dart';
import '../table_storage.dart';

String getLuaType(Object? value) {
  if (value case final Value wrapped) {
    final name = wrapped.getMetamethod('__name');
    final rawName = name is Value ? name.raw : name;
    switch (rawName) {
      case final String stringName:
        return stringName;
      case final LuaString stringName:
        return stringName.toString();
    }
    value = wrapped.raw;
  }
  if (value case final Map<dynamic, dynamic> table) {
    final wrapped = Value.lookupCanonicalTableWrapper(table);
    if (wrapped != null) {
      final name = wrapped.getMetamethod('__name');
      final rawName = name is Value ? name.raw : name;
      switch (rawName) {
        case final String stringName:
          return stringName;
        case final LuaString stringName:
          return stringName.toString();
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
    _ when t.runtimeType.toString() == 'Box' ||
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
