part of '../love_runtime.dart';

class LoveTouchInfo {
  const LoveTouchInfo({
    required this.id,
    required this.x,
    required this.y,
    required this.dx,
    required this.dy,
    required this.pressure,
  });

  final int id;
  final double x;
  final double y;
  final double dx;
  final double dy;
  final double pressure;
}

class LoveTouchState {
  LoveTouchState({Iterable<LoveTouchInfo> touches = const <LoveTouchInfo>[]}) {
    for (final touch in touches) {
      _touches[touch.id] = touch;
    }
  }

  final LinkedHashMap<int, LoveTouchInfo> _touches =
      LinkedHashMap<int, LoveTouchInfo>();

  List<int> getTouches() => List<int>.unmodifiable(_touches.keys);

  LoveTouchInfo? activeTouch(int id) => _touches[id];

  Iterable<LoveTouchInfo> get activeTouches =>
      UnmodifiableListView<LoveTouchInfo>(_touches.values);

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

  void endTouch(int id) {
    _touches.remove(id);
  }

  void clear() {
    _touches.clear();
  }
}
