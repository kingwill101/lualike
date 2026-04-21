import 'package:flutter/services.dart';

import '../love_runtime.dart';

class LoveFlameMouseCursorBridge {
  LoveFlameMouseCursorBridge({required LoveMouseState mouse}) : _mouse = mouse;

  final LoveMouseState _mouse;

  MouseCursor _currentCursor = SystemMouseCursors.basic;

  MouseCursor get currentCursor => _currentCursor;

  MouseCursor sync() {
    _currentCursor = _resolveCursor();
    return _currentCursor;
  }

  MouseCursor _resolveCursor() {
    if (!_mouse.visible || _mouse.programmaticPositionActive) {
      return SystemMouseCursors.none;
    }

    final cursor = _mouse.cursor;
    if (cursor == null) {
      return SystemMouseCursors.basic;
    }

    if (!cursor.isSystemCursor) {
      return SystemMouseCursors.none;
    }

    return switch (cursor.systemType) {
      'arrow' => SystemMouseCursors.basic,
      'ibeam' => SystemMouseCursors.text,
      'wait' => SystemMouseCursors.wait,
      'crosshair' => SystemMouseCursors.precise,
      'waitarrow' => SystemMouseCursors.progress,
      'sizenwse' => SystemMouseCursors.resizeUpLeftDownRight,
      'sizenesw' => SystemMouseCursors.resizeUpRightDownLeft,
      'sizewe' => SystemMouseCursors.resizeColumn,
      'sizens' => SystemMouseCursors.resizeRow,
      'sizeall' => SystemMouseCursors.move,
      'no' => SystemMouseCursors.forbidden,
      'hand' => SystemMouseCursors.click,
      _ => SystemMouseCursors.basic,
    };
  }
}
