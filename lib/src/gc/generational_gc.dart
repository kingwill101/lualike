import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';

/// Represents a generation of objects in the generational garbage collector.
///
/// In a generational garbage collector, objects are divided into different
/// generations based on their age. This class manages a collection of objects
/// belonging to the same generation.
class Generation {
  /// The objects belonging to this generation.
  final List<GCObject> objects = [];

  /// The age of this generation, incremented after each collection cycle.
  int age = 0;

  /// Adds an object to this generation.
  void add(GCObject obj) {
    objects.add(obj);
  }

  /// Removes an object from this generation.
  void remove(GCObject obj) {
    objects.remove(obj);
  }
}

/// Implementation of a generational garbage collector as described in Lua 5.4 reference manual.
///
/// The generational garbage collector divides objects into two generations:
/// - Young generation (nursery): Contains newly created objects
/// - Old generation: Contains objects that have survived at least one collection cycle
///
/// The collector performs two types of collections:
/// - Minor collections: Only traverse objects in the young generation
/// - Major collections: Traverse all objects in both generations
///
/// This implementation follows section 2.5.2 of the Lua 5.4 reference manual:
/// "In generational mode, the collector does frequent minor collections, which traverses
/// only objects recently created. If after a minor collection the use of memory is still
/// above a limit, the collector does a stop-the-world major collection, which traverses
/// all objects."
class GenerationalGCManager {
  /// Reference to the interpreter for accessing global state.
  // ignore: unused_field
  final Interpreter _interpreter;

  /// Singleton instance of the garbage collector.
  static late GenerationalGCManager instance;

  /// Initializes the garbage collector with a reference to the interpreter.
  static void initialize(Interpreter interpreter) {
    instance = GenerationalGCManager._(interpreter);
  }

  // Private constructor
  GenerationalGCManager._(Interpreter interpreter) : _interpreter = interpreter;

  /// Whether garbage collection is currently stopped.
  bool _isStopped = false;

  /// Returns whether garbage collection is currently stopped.
  bool get isStopped => _isStopped;

  /// GC tuning parameters as described in Lua 5.4 reference manual.

  /// Controls the size of each incremental step.
  /// In Lua, this is logarithmic: a value of n means allocating 2^n bytes between steps.
  int stepSize = 1;

  /// Controls the frequency of minor collections.
  /// For a minor multiplier x, a new minor collection will be done when memory
  /// grows x% larger than the memory in use after the previous major collection.
  /// Default in Lua is 20, maximum is 200.
  int minorMultiplier = 100;

  /// Controls the frequency of major collections.
  /// For a major multiplier x, a new major collection will be done when memory
  /// grows x% larger than the memory in use after the previous major collection.
  /// Default in Lua is 100, maximum is 1000.
  int majorMultiplier = 100;

  /// Memory tracking for determining when to trigger collections.
  int _lastMinorBytes = 0;
  int _lastMajorBytes = 0;

  /// Whether the current collection cycle is complete.
  // ignore: prefer_final_fields
  bool _cycleComplete = false;

  /// The young generation (nursery) containing newly created objects.
  final Generation youngGen = Generation();

  /// The old generation containing objects that have survived at least one collection.
  final Generation oldGen = Generation();

  // New fields for finalization logic
  final Set<GCObject> _toBeFinalized = {};
  final Set<GCObject> _alreadyFinalized = {};

  /// Stops the garbage collector.
  ///
  /// This is equivalent to the Lua collectgarbage("stop") function.
  void stop() {
    _isStopped = true;
    Logger.debug('GC stopped', category: 'GC');
  }

  /// Starts the garbage collector.
  ///
  /// This is equivalent to the Lua collectgarbage("restart") function.
  void start() {
    _isStopped = false;
    Logger.debug('GC started', category: 'GC');
  }

  /// Returns whether the current collection cycle is complete.
  bool isCollectionCycleComplete() => _cycleComplete;

  /// Simulates memory allocation to potentially trigger garbage collection.
  ///
  /// This is used to trigger collection based on allocation pressure,
  /// similar to how Lua triggers collection when memory usage increases.
  void simulateAllocation(int bytes) {
    if (_isStopped) return;

    final currentBytes = estimateMemoryUse();
    if (currentBytes - _lastMinorBytes > bytes) {
      minorCollection([]); // Trigger minor collection
    }
    Logger.debug('Simulated allocation of $bytes bytes', category: 'GC');
  }

  /// Registers a new object with the garbage collector.
  ///
  /// New objects are always placed in the young generation (nursery).
  void register(GCObject obj) {
    print('[GC] Register: ${obj.runtimeType} ${obj.hashCode}');
    youngGen.add(obj);
    Logger.debug('Registered new object in young generation', category: 'GC');
  }

  /// Promotes an object from the young generation to the old generation.
  ///
  /// This happens when an object survives a minor collection cycle,
  /// indicating it may have a longer lifetime.
  void promote(GCObject obj) {
    print('[GC] Promote: ${obj.runtimeType} ${obj.hashCode}');
    youngGen.remove(obj);
    oldGen.add(obj);
    obj.isOld = true;
    Logger.debug('Promoted object to old generation', category: 'GC');
  }

  /// Marks all live objects in a generation starting from the given roots.
  void _markGeneration(Generation gen, List<Object?> roots) {
    print('[GC] Marking generation (${gen == youngGen ? 'young' : 'old'})');
    for (final root in roots) {
      _discover(root);
    }
  }

  /// Recursively discovers and marks live objects starting from a given object.
  ///
  /// This implements the mark phase of the mark-and-sweep algorithm,
  /// traversing the object graph to find all reachable objects.
  void _discover(Object? obj) {
    if (obj == "t") {
      print("t");
    }
    if (obj is GCObject) {
      if (!obj.marked) {
        print('[GC] Mark: ${obj.runtimeType} ${obj.hashCode}');
        obj.marked = true;
        for (final ref in obj.getReferences()) {
          _discover(ref);
        }
      }
    } else if (obj is Environment) {
      _discover(obj.values);
      if (obj.parent != null) _discover(obj.parent);
    } else if (obj is Map) {
      obj.forEach((key, value) {
        if (key == "t") {
          print("t");
        }
        _discover(key);
        _discover(value);
      });
    } else if (obj is Iterable) {
      for (final item in obj) {
        _discover(item);
      }
    }
  }

  /// Separates objects in a generation into survivors and dead.
  /// Moves dead objects with finalizers to the _toBeFinalized list for later processing.
  void _separate(Generation gen) {
    print(
      '[GC] Separate: ${gen == youngGen ? 'young' : 'old'} generation, ${gen.objects.length} objects',
    );
    final survivors = <GCObject>[];

    // Use toList() to create a copy, allowing modification of the original list.
    for (final obj in gen.objects.toList()) {
      if (obj.marked) {
        // It's alive, keep it for the next cycle.
        obj.marked = false; // Unmark for the next GC cycle.
        survivors.add(obj);
      } else {
        // It's dead (unreachable).
        bool hasGc = false;
        if (obj is Value) {
          hasGc = obj.hasMetamethod('__gc');
        }

        if (hasGc && !_alreadyFinalized.contains(obj)) {
          // It's finalizable and has not been finalized yet.
          // Add to the finalization list and "resurrect" it for this cycle.
          // It will be collected in the next GC cycle if still unreachable.
          print('[GC] To be finalized: ${obj.runtimeType} ${obj.hashCode}');
          _toBeFinalized.add(obj);
          survivors.add(obj);
        } else {
          // It's truly dead (no finalizer or already finalized), so collect it.
          print('[GC] Free: ${obj.runtimeType} ${obj.hashCode}');
          obj.free();
        }
      }
    }

    // Update the generation with only the survivors (including resurrected objects).
    gen.objects.clear();
    gen.objects.addAll(survivors);
  }

  /// Calls finalizers for objects in the _toBeFinalized list.
  Future<void> _callFinalizersAsync() async {
    print('[GC] Calling finalizers for ${_toBeFinalized.length} objects');
    // According to Lua spec, finalizers are called in an unspecified order.
    // Iterating and clearing is sufficient.
    for (final obj in _toBeFinalized) {
      if (obj is Value) {
        // Mark as finalized BEFORE calling __gc. This prevents re-finalization
        // if the object is resurrected and then becomes dead again.
        _alreadyFinalized.add(obj);
        try {
          print('[GC] Run finalizer: ${obj.runtimeType} ${obj.hashCode}');
          await obj.callMetamethodAsync('__gc', [obj]);
        } catch (e) {
          // Errors in finalizers are reported but not propagated.
          print('[GC] Error in finalizer: $e');
        }
      }
    }
    _toBeFinalized.clear();
  }

  /// Performs a minor collection, which only traverses the young generation.
  ///
  /// As described in the Lua 5.4 reference manual section 2.5.2:
  /// "In generational mode, the collector does frequent minor collections,
  /// which traverses only objects recently created."
  ///
  /// Objects that survive a minor collection are promoted to the old generation.
  void minorCollection(List<Object?> roots) {
    print('[GC] Minor collection start');
    _cycleComplete = false;

    // In a real generational GC, we'd need a write barrier to track pointers
    // from the old generation to the young generation. For now, we'll just
    // consider all old-gen objects as roots for the minor collection mark phase.
    final minorRoots = [...roots, ...oldGen.objects];

    // Mark from roots
    _markGeneration(youngGen, minorRoots);

    final survivors = <GCObject>[];
    for (final obj in youngGen.objects) {
      if (obj.marked) {
        obj.marked = false; // unmark for next cycle
        survivors.add(obj);
      } else {
        // In minor collection, we don't finalize.
        // If it's dead, it's just dead.
        print('[GC] Minor free: ${obj.runtimeType} ${obj.hashCode}');
        obj.free();
      }
    }

    // Promote all survivors of a minor collection to the old generation.
    for (final obj in survivors) {
      promote(obj);
    }

    youngGen.objects.clear();

    _lastMinorBytes = estimateMemoryUse();
    _cycleComplete = true;
    print('[GC] Minor collection end');
    Logger.debug('Minor collection complete', category: 'GC');
  }

  /// Performs a major collection, which traverses all objects in both generations.
  ///
  /// As described in the Lua 5.4 reference manual section 2.5.2:
  /// "If after a minor collection the use of memory is still above a limit,
  /// the collector does a stop-the-world major collection, which traverses all objects."
  ///
  /// During a major collection, finalizers are run for objects with __gc metamethods.
  Future<void> majorCollection(List<Object?> roots) async {
    print('[GC] Major collection start');
    _cycleComplete = false;

    // Phase 1: Mark all reachable objects
    _markGeneration(youngGen, roots);
    _markGeneration(oldGen, roots);

    // Phase 2: Separate survivors from dead, and identify finalizables
    _separate(youngGen);
    _separate(oldGen);

    // Phase 3: Run finalizers for objects collected in this cycle.
    await _callFinalizersAsync();

    _lastMajorBytes = estimateMemoryUse();
    _cycleComplete =
        true; // The full cycle (including finalization) is now complete
    print('[GC] Major collection end');
    Logger.debug('Major collection complete', category: 'GC');
  }

  /// Estimates the current memory usage for determining when to trigger collections.
  ///
  /// This is a simple estimate based on the number of objects in both generations.
  int estimateMemoryUse() {
    return youngGen.objects.length + oldGen.objects.length;
  }

  /// Performs a garbage collection cycle if needed based on memory usage.
  ///
  /// This method decides whether to perform a minor or major collection
  /// based on the current memory usage compared to the usage after the
  /// previous collections, using the minor and major multipliers.
  Future<void> collect(List<Object?> roots) async {
    final currentBytes = estimateMemoryUse();

    // Check if we need a major collection
    if (currentBytes > _lastMajorBytes * (1 + majorMultiplier / 100)) {
      await majorCollection(roots);
    }
    // Check if we need a minor collection
    else if (currentBytes > _lastMinorBytes * (1 + minorMultiplier / 100)) {
      minorCollection(roots);
    }
  }
}
