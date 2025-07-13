import 'package:lualike/lualike.dart';

/// Every object that lives in lualike's "heap" and that should be garbage‐collected
/// must extend this GCObject.
///
/// In accordance with Lua's garbage collection system, objects that need to be
/// garbage collected must provide a way to:
/// 1. Determine if they're marked (for mark-and-sweep collection)
/// 2. Provide references to other objects they hold (for traversal)
/// 3. Free any resources when collected
///
/// This base class provides the foundation for both incremental and generational
/// garbage collection strategies as described in the Lua reference manual.
abstract class GCObject {
  /// Whether this object has been marked during the current GC cycle.
  /// Used in mark-and-sweep collection to identify live objects.
  bool marked = false;

  /// Whether this object belongs to the old generation.
  /// Used in generational collection to determine which generation the object belongs to.
  bool isOld = false;

  /// Return direct references so the GC can traverse the object graph.
  ///
  /// This method is crucial for the mark phase of garbage collection,
  /// allowing the collector to find all reachable objects.
  List<Object?> getReferences();

  /// Free any resources (for debugging or finalization).
  ///
  /// Similar to Lua's finalizers, this method is called when an object
  /// is about to be collected, allowing it to release any external resources.
  void free() {
    Logger.debug(
      'GCObject.free() called for $runtimeType $hashCode',
      category: "GC",
    );
    // By default, nothing needs to be done.
  }
}
