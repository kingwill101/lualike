part of '../love_api_bindings.dart';

const String _loveCursorObjectKey = '__love2d_cursor__';

final Expando<Value> _loveCursorWrapperCache = Expando<Value>(
  'love2dCursorWrapper',
);

LoveMouseCursor? _cursorIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final cursor = table[_loveCursorObjectKey];
  return cursor is LoveMouseCursor ? cursor : null;
}

LoveMouseCursor _requireCursor(List<Object?> args, int index, String symbol) {
  final cursor = _cursorIfPresent(_valueAt(args, index));
  if (cursor != null) {
    return cursor;
  }

  throw LuaError('$symbol expected a Cursor at argument ${index + 1}');
}

Value _wrapCursor(LibraryRegistrationContext context, LoveMouseCursor cursor) {
  final cached = _loveCursorWrapperCache[cursor];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveCursorObjectKey: cursor,
    'getType': Value(
      builder.create(
        (args) => _requireCursor(args, 0, 'Cursor:getType').getType(),
      ),
      functionName: 'getType',
    ),
  });
  _loveCursorWrapperCache[cursor] = table;
  return table;
}
