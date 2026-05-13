import 'package:flutter/services.dart';

import '../love_runtime.dart';

/// Maps LOVE mouse cursor state onto Flutter [MouseCursor] values.
class LoveFlameMouseCursorBridge {
  /// Creates a cursor bridge backed by [mouse].
  LoveFlameMouseCursorBridge({required LoveMouseState mouse}) : _mouse = mouse;

  /// The LOVE mouse state being observed.
  final LoveMouseState _mouse;

  /// The last cursor value resolved for Flutter.
  MouseCursor _currentCursor = SystemMouseCursors.basic;

  /// The current Flutter cursor value.
  MouseCursor get currentCursor => _currentCursor;

  /// Recomputes and returns the current Flutter cursor.
  MouseCursor sync() {
    _currentCursor = _resolveCursor();
    return _currentCursor;
  }

  /// Resolves the Flutter cursor implied by the current LOVE mouse state.
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
