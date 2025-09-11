import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/upvalue.dart';

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
  static bool isInitialized = false;

  /// Initializes the garbage collector with a reference to the interpreter.
  static void initialize(Interpreter interpreter) {
    instance = GenerationalGCManager._(interpreter);
    isInitialized = true;
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

  // Weak table tracking for major collections (package-private for testing)
  final List<Value> weakValuesTables = [];
  final List<Value> ephemeronTables = [];
  final List<Value> allWeakTables = [];

  /// Whether we're currently in a major collection (affects weak table handling)
  bool _inMajorCollection = false;

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
    youngGen.add(obj);
    Logger.debug(
      'Register: ${obj.runtimeType} ${obj.hashCode}',
      category: 'GC',
    );
  }

  /// Promotes an object from the young generation to the old generation.
  ///
  /// This happens when an object survives a minor collection cycle,
  /// indicating it may have a longer lifetime.
  void promote(GCObject obj) {
    Logger.debug('Promote: ${obj.runtimeType} ${obj.hashCode}', category: 'GC');
    youngGen.remove(obj);
    oldGen.add(obj);
    obj.isOld = true;
    Logger.debug('Promoted object to old generation', category: 'GC');
  }

  /// Marks all live objects in a generation starting from the given roots.
  void _markGeneration(Generation gen, List<Object?> roots) {
    Logger.debug(
      'Marking generation (${gen == youngGen ? 'young' : 'old'})',
      category: 'GC',
    );
    for (final root in roots) {
      _discover(root);
    }
  }

  /// Builds the root set for garbage collection from interpreter state.
  /// This should include all objects that should be considered as roots:
  /// - Global environment and current stack frames
  /// - All live coroutines
  /// - VM singletons that hold GCObjects
  List<Object?> buildRootSet(Interpreter vm) {
    // Use the interpreter's existing getRoots method which includes:
    // - Current environment (globals)
    // - Call stack
    // - Evaluation stack
    // - Current coroutine and main thread
    // - Active coroutines set
    final roots = vm.getRoots();

    Logger.debug('Built root set with ${roots.length} roots', category: 'GC');
    return roots;
  }

  /// Recursively discovers and marks live objects starting from a given object.
  ///
  /// This implements the mark phase of the mark-and-sweep algorithm,
  /// traversing the object graph to find all reachable objects.
  void _discover(Object? obj) {
    Logger.debug(
      'Discover: ${obj.runtimeType} ${obj.hashCode} (inMajorCollection: $_inMajorCollection)',
      category: 'GC',
    );

    if (obj == "t") {
      Logger.debug("t", category: 'GC');
    }
    if (obj is GCObject) {
      if (!obj.marked) {
        Logger.debug(
          'Mark: ${obj.runtimeType} ${obj.hashCode}',
          category: 'GC',
        );
        obj.marked = true;

        // Handle Value objects with potential weak table semantics
        if (obj is Value && obj.isTable && _inMajorCollection) {
          Logger.debug(
            'Found Value table ${obj.hashCode} during major collection, calling _handleTableTraversal',
            category: 'GC',
          );
          _handleTableTraversal(obj);
        } else if (obj is Value && obj.isTable) {
          Logger.debug(
            'Found Value table ${obj.hashCode} but not in major collection, using regular traversal',
            category: 'GC',
          );
          // Regular GCObject traversal
          for (final ref in obj.getReferences()) {
            _discover(ref);
          }
        } else {
          // Regular GCObject traversal
          Logger.debug(
            'Regular GCObject traversal for ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
          for (final ref in obj.getReferences()) {
            _discover(ref);
          }
        }
      } else {
        Logger.debug(
          'Already marked: ${obj.runtimeType} ${obj.hashCode}',
          category: 'GC',
        );
      }
    } else if (obj is Environment) {
      Logger.debug('Environment traversal: ${obj.hashCode}', category: 'GC');
      _discover(obj.values);
      if (obj.parent != null) _discover(obj.parent);
    } else if (obj is Map) {
      // Skip empty maps and perform quick scan for GC-relevant entries
      if (obj.isEmpty) return;

      bool hasGCContent = false;
      for (final entry in obj.entries) {
        if (entry.key is GCObject || entry.value is GCObject) {
          hasGCContent = true;
          break;
        }
      }

      if (!hasGCContent) return;

      Logger.debug(
        'Map traversal: ${obj.runtimeType} ${obj.hashCode} with ${obj.length} entries',
        category: 'GC',
      );

      // Only traverse entries that could contain GCObjects
      obj.forEach((key, value) {
        if (key == "t") {
          Logger.debug("t", category: 'GC');
        }
        if (key is GCObject ||
            value is GCObject ||
            key is Value ||
            value is Value) {
          Logger.debug(
            'Map entry: key=${key.runtimeType} ${key.hashCode} -> value=${value.runtimeType} ${value.hashCode}',
            category: 'GC',
          );
          _discover(key);
          _discover(value);
        }
      });
    } else if (obj is Iterable) {
      // Skip empty iterables and perform quick scan for GC-relevant content
      if (obj.isEmpty) return;

      bool hasGCContent = false;
      for (final item in obj) {
        if (item is GCObject) {
          hasGCContent = true;
          break;
        }
      }

      if (!hasGCContent) return;

      Logger.debug(
        'Iterable traversal: ${obj.runtimeType} ${obj.hashCode} with ${obj.length} items',
        category: 'GC',
      );
      for (final item in obj) {
        if (item is GCObject || item is Value) {
          _discover(item);
        }
      }
    } else {
      Logger.debug(
        'Ignoring non-GC object: ${obj.runtimeType} ${obj.hashCode}',
        category: 'GC',
      );
    }
  }

  /// Handles traversal of table objects based on their weak mode.
  /// This is only used during major collections where weak semantics apply.
  void _handleTableTraversal(Value table) {
    assert(table.isTable);

    final weakMode = table.tableWeakMode;

    Logger.debug(
      'Handling table traversal for table ${table.hashCode}, weak mode: $weakMode',
      category: 'GC',
    );

    if (weakMode == null) {
      // Strong table - traverse normally
      Logger.debug(
        'Table ${table.hashCode} is strong, traversing normally',
        category: 'GC',
      );
      for (final ref in table.getReferencesForGC(
        strongKeys: true,
        strongValues: true,
      )) {
        _discover(ref);
      }
    } else if (weakMode == 'v') {
      // Weak values - traverse keys only, mark table for later clearing
      Logger.debug(
        'Table ${table.hashCode} has weak values, adding to tracking list',
        category: 'GC',
      );
      weakValuesTables.add(table);
      for (final ref in table.getReferencesForGC(
        strongKeys: true,
        strongValues: false,
      )) {
        _discover(ref);
      }
    } else if (weakMode == 'k') {
      // Weak keys (ephemeron) - special handling needed
      Logger.debug(
        'Table ${table.hashCode} has weak keys, adding to ephemeron list',
        category: 'GC',
      );
      ephemeronTables.add(table);

      // For ephemeron tables, we don't traverse table entries initially.
      // Instead, we only traverse non-entry references (metatable, etc.)
      // The entries will be handled during ephemeron convergence.

      // Only traverse metatable and other non-entry references
      if (table.metatable != null) {
        _discover(table.metatable);
      }

      // Include upvalues if present (now GCObjects themselves)
      if (table.upvalues != null) {
        for (final upvalue in table.upvalues!) {
          _discover(upvalue);
        }
      }
    } else if (weakMode == 'kv') {
      // All weak - don't traverse entries at all
      Logger.debug(
        'Table ${table.hashCode} is all-weak, adding to all-weak list',
        category: 'GC',
      );
      allWeakTables.add(table);
      for (final ref in table.getReferencesForGC(
        strongKeys: false,
        strongValues: false,
      )) {
        _discover(ref);
      }
    }
  }

  /// Clears dead entries from weak-values tables.
  /// Called after marking phase during major collection.
  void _clearWeakValues() {
    Logger.debug(
      'Starting weak values clearing for ${weakValuesTables.length} tables',
      category: 'GC',
    );

    for (final table in weakValuesTables) {
      final tableMap = table.raw as Map;
      final entriesToRemove = <dynamic>[];

      Logger.debug(
        'Checking weak table ${table.hashCode} with ${tableMap.length} entries',
        category: 'GC',
      );

      for (final entry in tableMap.entries) {
        final key = entry.key;
        final value = entry.value;
        final keyMarked = (key is GCObject) ? key.marked : 'N/A';
        final valueMarked = (value is GCObject) ? value.marked : 'N/A';

        Logger.debug(
          'Entry: key=$key (marked: $keyMarked) -> value=$value (marked: $valueMarked)',
          category: 'GC',
        );

        if ((value is GCObject && !value.marked) ||
            (value is Value && !value.marked)) {
          entriesToRemove.add(entry.key);
          Logger.debug(
            'Marking for removal: ${entry.key} -> $value',
            category: 'GC',
          );
        }
      }

      Logger.debug(
        'Removing ${entriesToRemove.length} entries from table ${table.hashCode}',
        category: 'GC',
      );

      for (final key in entriesToRemove) {
        tableMap.remove(key);
      }
    }
    weakValuesTables.clear();
  }

  /// Clears dead entries from all-weak tables.
  /// Called after marking phase during major collection.
  void _clearAllWeak() {
    for (final table in allWeakTables) {
      final tableMap = table.raw as Map;
      final entriesToRemove = <dynamic>[];

      for (final entry in tableMap.entries) {
        final key = entry.key;
        final value = entry.value;

        final keyDead =
            (key is GCObject && !key.marked) || (key is Value && !key.marked);
        final valueDead =
            (value is GCObject && !value.marked) ||
            (value is Value && !value.marked);

        if (keyDead || valueDead) {
          entriesToRemove.add(key);
          Logger.debug(
            'Clearing all-weak entry: $key -> $value',
            category: 'GC',
          );
        }
      }

      for (final key in entriesToRemove) {
        tableMap.remove(key);
      }
    }
    allWeakTables.clear();
  }

  /// Performs ephemeron convergence for weak keys tables.
  ///
  /// Ephemeron semantics: a value in a weak-keys table survives only if
  /// its key is strongly reachable from outside the ephemeron tables.
  /// This requires iterative convergence until a fixed point is reached.
  void _convergeEphemerons() {
    if (ephemeronTables.isEmpty) return;

    Logger.debug(
      'Starting ephemeron convergence for ${ephemeronTables.length} tables',
      category: 'GC',
    );

    bool changed = true;
    int iterations = 0;
    const maxIterations = 100; // Safety limit to prevent infinite loops

    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;

      Logger.debug(
        'Ephemeron convergence iteration $iterations',
        category: 'GC',
      );

      for (final table in ephemeronTables) {
        final tableMap = table.raw as Map;

        for (final entry in tableMap.entries) {
          final key = entry.key;
          final value = entry.value;

          // If key is marked (strongly reachable) and value is not yet marked,
          // mark the value and propagate from it
          if ((key is GCObject && key.marked) || (key is Value && key.marked)) {
            if (value is GCObject && !value.marked) {
              Logger.debug(
                'Ephemeron: marking value ${value.hashCode} due to marked key ${key.hashCode}',
                category: 'GC',
              );
              _discover(value);
              changed = true;
            } else if (value is Value && !value.marked) {
              Logger.debug(
                'Ephemeron: marking value ${value.hashCode} due to marked key ${key.hashCode}',
                category: 'GC',
              );
              _discover(value);
              changed = true;
            }
          }
        }
      }
    }

    Logger.debug(
      'Ephemeron convergence completed after $iterations iterations',
      category: 'GC',
    );

    if (iterations >= maxIterations) {
      Logger.debug(
        'Warning: Ephemeron convergence hit iteration limit',
        category: 'GC',
      );
    }
  }

  /// Clears dead entries from weak-keys tables.
  /// Called after ephemeron convergence during major collection.
  void _clearWeakKeys() {
    Logger.debug(
      'Starting weak keys clearing for ${ephemeronTables.length} tables',
      category: 'GC',
    );

    for (final table in ephemeronTables) {
      final tableMap = table.raw as Map;
      final entriesToRemove = <dynamic>[];

      Logger.debug(
        'Checking weak keys table ${table.hashCode} with ${tableMap.length} entries',
        category: 'GC',
      );

      for (final entry in tableMap.entries) {
        final key = entry.key;
        final value = entry.value;
        final keyMarked = (key is GCObject) ? key.marked : 'N/A';
        final valueMarked = (value is GCObject) ? value.marked : 'N/A';

        Logger.debug(
          'Entry: key=$key (marked: $keyMarked) -> value=$value (marked: $valueMarked)',
          category: 'GC',
        );

        // In weak keys tables, remove entries where the key is dead
        if ((key is GCObject && !key.marked) || (key is Value && !key.marked)) {
          entriesToRemove.add(entry.key);
          Logger.debug(
            'Marking for removal: ${entry.key} -> $value',
            category: 'GC',
          );
        }
      }

      Logger.debug(
        'Removing ${entriesToRemove.length} entries from table ${table.hashCode}',
        category: 'GC',
      );

      for (final key in entriesToRemove) {
        tableMap.remove(key);
      }
    }
    ephemeronTables.clear();
  }

  /// Separates objects in a generation into survivors and dead.
  /// Moves dead objects with finalizers to the _toBeFinalized list for later processing.
  void _separate(Generation gen) {
    Logger.debug(
      'Separate: ${gen == youngGen ? 'young' : 'old'} generation, ${gen.objects.length} objects',
      category: 'GC',
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
          Logger.debug(
            'To be finalized: ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
          _toBeFinalized.add(obj);
          survivors.add(obj);
        } else {
          // It's truly dead (no finalizer or already finalized), so collect it.
          Logger.debug(
            'Free: ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
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
    Logger.debug(
      'Calling finalizers for ${_toBeFinalized.length} objects',
      category: 'GC',
    );
    // According to Lua spec, finalizers are called in an unspecified order.
    // Iterating and clearing is sufficient.
    for (final obj in _toBeFinalized) {
      if (obj is Value) {
        // Mark as finalized BEFORE calling __gc. This prevents re-finalization
        // if the object is resurrected and then becomes dead again.
        _alreadyFinalized.add(obj);
        try {
          Logger.debug(
            'Run finalizer: ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
          await obj.callMetamethodAsync('__gc', [obj]);
        } catch (e) {
          // Errors in finalizers are reported but not propagated.
          Logger.debug('Error in finalizer: $e', category: 'GC');
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
    Logger.debug('Minor collection start', category: 'GC');
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
        Logger.debug(
          'Minor free: ${obj.runtimeType} ${obj.hashCode}',
          category: 'GC',
        );
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
    Logger.debug('Minor collection end', category: 'GC');
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
    Logger.debug('Major collection start', category: 'GC');
    _cycleComplete = false;
    _inMajorCollection = true;

    // Clear weak table tracking lists from previous collection
    weakValuesTables.clear();
    ephemeronTables.clear();
    allWeakTables.clear();

    // Phase 1: Mark all reachable objects
    _markGeneration(youngGen, roots);
    _markGeneration(oldGen, roots);

    // Phase 2: Ephemeron convergence for weak keys tables (while objects are still marked)
    _convergeEphemerons();

    // Phase 3: Clear weak table entries (while objects are still marked)
    _clearWeakValues();
    _clearWeakKeys();
    _clearAllWeak();

    // Phase 4: Separate survivors from dead, and identify finalizables
    _separate(youngGen);
    _separate(oldGen);

    // Phase 5: Re-mark objects to be finalized to handle resurrection
    for (final obj in _toBeFinalized) {
      _discover(obj);
    }

    // Phase 6: Run finalizers for objects collected in this cycle.
    await _callFinalizersAsync();

    _lastMajorBytes = estimateMemoryUse();
    _cycleComplete =
        true; // The full cycle (including finalization) is now complete
    _inMajorCollection = false;
    Logger.debug('Major collection complete', category: 'GC');
  }

  /// Estimates the current memory usage for determining when to trigger collections.
  ///
  /// This provides a rough approximation based on object counts and sizes.
  int estimateMemoryUse() {
    int totalSize = 0;

    // Base object count
    int objectCount = youngGen.objects.length + oldGen.objects.length;
    totalSize += objectCount * 64; // Rough overhead per GC object

    // Add size estimates for different object types
    for (final gen in [youngGen, oldGen]) {
      for (final obj in gen.objects) {
        if (obj is Value) {
          totalSize += _estimateValueSize(obj);
        } else if (obj is Environment) {
          totalSize += _estimateEnvironmentSize(obj);
        } else if (obj is Upvalue) {
          totalSize += _estimateUpvalueSize(obj);
        } else {
          totalSize += 32; // Default object size
        }
      }
    }

    return totalSize;
  }

  /// Estimates the memory footprint of a Value object
  int _estimateValueSize(Value value) {
    int size = 128; // Base Value overhead

    if (value.isTable && value.raw is Map) {
      final table = value.raw as Map;
      size += table.length * 48; // Approximate entry overhead
    }

    if (value.upvalues != null) {
      // Upvalues are now GCObjects and counted separately in main estimation
      // But include reference overhead here
      size += value.upvalues!.length * 8; // Reference overhead only
    }

    if (value.metatable != null) {
      size += 64; // Metatable overhead
    }

    return size;
  }

  /// Estimates the memory footprint of an Environment object
  int _estimateEnvironmentSize(Environment env) {
    int size = 96; // Base Environment overhead
    size += env.values.length * 40; // Box overhead per variable
    return size;
  }

  /// Estimates the memory footprint of an Upvalue object
  int _estimateUpvalueSize(Upvalue upvalue) {
    int size = 96; // Base Upvalue overhead

    // Add Box overhead
    size += 48; // valueBox overhead

    // Add closed value overhead if closed
    if (!upvalue.isOpen) {
      size += 32; // Closed value storage
    }

    // Add name overhead if present
    if (upvalue.name != null) {
      size += upvalue.name!.length * 2; // String overhead
    }

    return size;
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

  /// Convenience method for major collection using the built root set.
  /// This is the main entry point for triggering major collections.
  Future<void> collectMajor() async {
    final roots = buildRootSet(_interpreter);
    await majorCollection(roots);
  }
}
