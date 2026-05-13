part of '../love_runtime.dart';

/// A single active touch tracked by the LOVE touch subsystem.
class LoveTouchInfo {
  /// Creates touch information for one active contact.
  const LoveTouchInfo({
    required this.id,
    required this.x,
    required this.y,
    required this.dx,
    required this.dy,
    required this.pressure,
  });

  /// The runtime touch identifier.
  final int id;

  /// The current horizontal position in LOVE coordinates.
  final double x;

  /// The current vertical position in LOVE coordinates.
  final double y;

  /// The horizontal delta since the previous touch update.
  final double dx;

  /// The vertical delta since the previous touch update.
  final double dy;

  /// The normalized pressure reported for this touch, when available.
  final double pressure;
}

/// Tracks the currently active touches reported to LOVE.
class LoveTouchState {
  /// Creates touch state optionally preloaded with active [touches].
  LoveTouchState({Iterable<LoveTouchInfo> touches = const <LoveTouchInfo>[]}) {
    for (final touch in touches) {
      _touches[touch.id] = touch;
    }
  }

  /// The active touches keyed by identifier in insertion order.
  final LinkedHashMap<int, LoveTouchInfo> _touches =
      LinkedHashMap<int, LoveTouchInfo>();

  /// The active touch identifiers in stable iteration order.
  List<int> getTouches() => List<int>.unmodifiable(_touches.keys);

  /// The active touch for [id], if one is currently tracked.
  LoveTouchInfo? activeTouch(int id) => _touches[id];

  /// The active touches in stable iteration order.
  Iterable<LoveTouchInfo> get activeTouches =>
      UnmodifiableListView<LoveTouchInfo>(_touches.values);

  /// Starts or replaces the active touch identified by [id].
  void beginTouch({
    required int id,
    required double x,
    required double y,
    double dx = 0.0,
    double dy = 0.0,
    double pressure = 1.0,
  }) {
    _touches.remove(id);
    _touches[id] = LoveTouchInfo(
      id: id,
      x: x,
      y: y,
      dx: dx,
      dy: dy,
      pressure: pressure,
    );
  }

  /// Updates the active touch identified by [id].
  void moveTouch({
    required int id,
    required double x,
    required double y,
    required double dx,
    required double dy,
    required double pressure,
  }) {
    _touches[id] = LoveTouchInfo(
      id: id,
      x: x,
      y: y,
      dx: dx,
      dy: dy,
      pressure: pressure,
    );
  }

  /// Ends the active touch identified by [id].
  void endTouch(int id) {
    _touches.remove(id);
  }

  /// Removes every active touch.
  void clear() {
    _touches.clear();
  }
}
