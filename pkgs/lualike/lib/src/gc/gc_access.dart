import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/value.dart';

/// Helper to obtain the GC manager from nearby context.
class GCAccess {
  static GenerationalGCManager? fromValue(Value? v) =>
      v?.interpreter?.gc ?? defaultManager;
  static GenerationalGCManager? fromEnv(Environment? env) =>
      env?.interpreter?.gc ?? defaultManager;

  /// Fallback global GC manager for contexts where objects are created
  /// without an attached interpreter but tests expect immediate GC tracking.
  /// Set by Interpreter during construction.
  static GenerationalGCManager? defaultManager;
}
