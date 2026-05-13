part of '../love_api_bindings.dart';

/// Binds `love.touch.getTouches`.
///
/// The returned Lua table uses LOVE's 1-based indexing for active touch IDs.
LoveApiImplementation _bindTouchGetTouches(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => Value(_touchIdTable(runtime.touch.getTouches()));
}

/// Binds `love.touch.getPosition`.
LoveApiImplementation _bindTouchGetPosition(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final id = _requireTouchId(args, 0, 'love.touch.getPosition');
    final touch = _requireActiveTouch(runtime.touch, id);
    return Value.multi(<Object?>[touch.x, touch.y]);
  };
}

/// Binds `love.touch.getPressure`.
LoveApiImplementation _bindTouchGetPressure(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final id = _requireTouchId(args, 0, 'love.touch.getPressure');
    return _requireActiveTouch(runtime.touch, id).pressure;
  };
}

/// Coerces the touch identifier at [index] into a LOVE touch ID.
///
/// Numeric values are rounded to match the general numeric coercion used by the
/// rest of the binding layer.
int _requireTouchId(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.round();
  }

  throw LuaError('$symbol expected a touch id at argument ${index + 1}');
}

/// Returns the active touch with [id] or throws a [LuaError].
LoveTouchInfo _requireActiveTouch(LoveTouchState state, int id) {
  final touch = state.activeTouch(id);
  if (touch != null) {
    return touch;
  }

  throw LuaError('Invalid active touch ID: $id');
}

/// Builds a LOVE-style array table for active touch [ids].
Map<Object?, Object?> _touchIdTable(List<int> ids) {
  final table = <Object?, Object?>{};
  for (var i = 0; i < ids.length; i++) {
    table[i + 1] = ids[i];
  }
  return table;
}
