import 'package:lualike/src/gc/generational_gc.dart';
import 'package:lualike/src/environment.dart';
import 'package:lualike/src/value.dart';

/// Helper to obtain the GC manager from nearby context.
class GCAccess {
  static GenerationalGCManager? fromValue(Value? v) => v?.interpreter?.gc;
  static GenerationalGCManager? fromEnv(Environment? env) => env?.interpreter?.gc;
}
