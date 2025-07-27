import '../../lualike.dart';
import '../coroutine.dart';

String getLuaType(Object? value) {
  final t = value is Value ? value.raw : value;
  return switch (t) {
    null => 'nil',
    String() || LuaString() => 'string',
    num() || BigInt() => 'number',
    bool() => 'boolean',
    Function() || BuiltinFunction() => 'function',
    Map() || List() => 'table',
    Coroutine() => 'thread',
    _ => 'userdata',
  };
}
