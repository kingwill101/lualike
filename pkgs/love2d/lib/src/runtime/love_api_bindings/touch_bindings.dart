part of '../love_api_bindings.dart';

LoveApiImplementation _bindTouchGetTouches(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) => Value(_touchIdTable(runtime.touch.getTouches()));
}

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

LoveApiImplementation _bindTouchGetPressure(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final id = _requireTouchId(args, 0, 'love.touch.getPressure');
    return _requireActiveTouch(runtime.touch, id).pressure;
  };
}

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

LoveTouchInfo _requireActiveTouch(LoveTouchState state, int id) {
  final touch = state.activeTouch(id);
  if (touch != null) {
    return touch;
  }

  throw LuaError('Invalid active touch ID: $id');
}

Map<Object?, Object?> _touchIdTable(List<int> ids) {
  final table = <Object?, Object?>{};
  for (var i = 0; i < ids.length; i++) {
    table[i + 1] = ids[i];
  }
  return table;
}
