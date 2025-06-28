import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/stdlib/metatables.dart';

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
    // New objects go to young generation
    youngGen.add(obj);
    Logger.debug('Registered new object in young generation', category: 'GC');
  }

  /// Promotes an object from the young generation to the old generation.
  ///
  /// This happens when an object survives a minor collection cycle,
  /// indicating it may have a longer lifetime.
  void promote(GCObject obj) {
    youngGen.remove(obj);
    oldGen.add(obj);
    obj.isOld = true;
    Logger.debug('Promoted object to old generation', category: 'GC');
  }

  /// Marks all live objects in a generation starting from the given roots.
  void _markGeneration(Generation gen, List<Object?> roots) {
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

  /// Sweeps a generation, removing unmarked objects and clearing marks on survivors.
  ///
  /// This implements the sweep phase of the mark-and-sweep algorithm,
  /// removing objects that were not marked during the mark phase.
  void _sweepGeneration(Generation gen) {
    final survivors = <GCObject>[];

    for (final obj in gen.objects) {
      if (!obj.marked) {
        obj.free();
      } else {
        obj.marked = false;
        survivors.add(obj);
      }
    }

    gen.objects.clear();
    gen.objects.addAll(survivors);
  }

  /// Performs a minor collection, which only traverses the young generation.
  ///
  /// As described in the Lua 5.4 reference manual section 2.5.2:
  /// "In generational mode, the collector does frequent minor collections,
  /// which traverses only objects recently created."
  ///
  /// Objects that survive a minor collection are promoted to the old generation.
  void minorCollection(List<Object?> roots) {
    Logger.debug('Starting minor collection', category: 'GC');
    _cycleComplete = false;

    // Mark from roots
    _markGeneration(youngGen, roots);

    // Promote surviving objects to old generation
    final survivors = youngGen.objects.where((obj) => obj.marked).toList();
    for (final obj in survivors) {
      promote(obj);
    }

    // Sweep young generation
    _sweepGeneration(youngGen);

    _lastMinorBytes = estimateMemoryUse();
    _cycleComplete = true;
    Logger.debug('Minor collection complete', category: 'GC');
  }

  /// Performs a major collection, which traverses all objects in both generations.
  ///
  /// As described in the Lua 5.4 reference manual section 2.5.2:
  /// "If after a minor collection the use of memory is still above a limit,
  /// the collector does a stop-the-world major collection, which traverses all objects."
  ///
  /// During a major collection, finalizers are run for objects with __gc metamethods.
  void majorCollection(List<Object?> roots) {
    Logger.debug('Starting major collection', category: 'GC');
    _cycleComplete = false;

    // Mark both generations
    _markGeneration(youngGen, roots);
    _markGeneration(oldGen, roots);

    // Run metatables finalizers
    // This follows section 2.5.3 of the Lua reference manual:
    // "When a marked object becomes dead, it is not collected immediately by the garbage collector.
    // Instead, Lua puts it in a list. After the collection, Lua goes through that list."
    MetaTable().runFinalizers();

    // Sweep both generations
    _sweepGeneration(youngGen);
    _sweepGeneration(oldGen);

    _lastMajorBytes = estimateMemoryUse();
    _cycleComplete = true;
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
  void collect(List<Object?> roots) {
    final currentBytes = estimateMemoryUse();

    // Check if we need a major collection
    if (currentBytes > _lastMajorBytes * (1 + majorMultiplier / 100)) {
      majorCollection(roots);
    }
    // Check if we need a minor collection
    else if (currentBytes > _lastMinorBytes * (1 + minorMultiplier / 100)) {
      minorCollection(roots);
    }
  }
}
