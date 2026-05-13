part of '../love_api_bindings.dart';

/// Table entry key that stores the backing [LoveMouseCursor] instance.
const String _loveCursorObjectKey = '__love2d_cursor__';
const String _loveCursorReleasedWrapperKey = '__love2d_cursor_released__';

/// Reuses Lua wrapper tables so the same cursor keeps a stable identity.
final Expando<Value> _loveCursorWrapperCache = Expando<Value>(
  'love2dCursorWrapper',
);

/// Whether a cursor has already been released through `Object:release`.
final Expando<bool> _loveCursorReleased = Expando<bool>('love2dCursorReleased');

/// Returns the Lua wrapper table for a `Cursor`, including released wrappers.
Map<dynamic, dynamic>? _cursorWrapperTableIfPresent(Object? value) {
  final table = _tableIdentityIfPresent(value);
  if (table == null) {
    return null;
  }

  final cursor = table[_loveCursorObjectKey];
  if (cursor is LoveMouseCursor ||
      table[_loveCursorReleasedWrapperKey] == true) {
    return table;
  }

  return null;
}

/// Returns whether [value] is a released `Cursor` wrapper.
bool _cursorWrapperReleased(Object? value) {
  final table = _cursorWrapperTableIfPresent(value);
  return table?[_loveCursorReleasedWrapperKey] == true;
}

/// Returns wrapped [LoveMouseCursor] when [value] is a Cursor table.
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

/// Returns a required `Cursor` receiver.
LoveMouseCursor _requireCursor(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  if (_cursorWrapperReleased(value)) {
    _throwReleasedObjectError();
  }

  final cursor = _cursorIfPresent(value);
  if (cursor != null) {
    return cursor;
  }

  _throwLuaStyleTypeError(
    symbol: symbol,
    index: index,
    expected: 'Cursor',
    actual: value,
  );
}

/// Wraps [cursor] as a Lua-facing `Cursor` object table.
Value _wrapCursor(LibraryRegistrationContext context, LoveMouseCursor cursor) {
  final cached = _loveCursorWrapperCache[cursor];
  if (cached != null && _cursorIfPresent(cached) != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Cursor', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveCursorObjectKey: cursor,
    'getType': Value(
      builder.create(
        (args) => _requireCursor(args, 0, 'Cursor:getType').getType(),
      ),
      functionName: 'getType',
    ),
    'release': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        final table = _cursorWrapperTableIfPresent(receiver);
        if (table == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:release',
            index: 0,
            expected: 'Cursor',
            actual: receiver,
          );
        }

        final cursor = table[_loveCursorObjectKey];
        if (cursor is! LoveMouseCursor) {
          return false;
        }
        if (_loveCursorReleased[cursor] == true) {
          return false;
        }

        _loveCursorReleased[cursor] = true;
        table[_loveCursorReleasedWrapperKey] = true;
        table[_loveCursorObjectKey] = null;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_cursorWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:type',
            index: 0,
            expected: 'Cursor',
            actual: receiver,
          );
        }
        return 'Cursor';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        final receiver = _valueAt(args, 0);
        if (_cursorWrapperTableIfPresent(receiver) == null) {
          _throwLuaStyleTypeError(
            symbol: 'Object:typeOf',
            index: 0,
            expected: 'Cursor',
            actual: receiver,
          );
        }
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveCursorWrapperCache[cursor] = table;
  return table;
}
