import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/gc/memory_credits.dart';

/// Phases of incremental garbage collection
enum GCPhase { idle, marking, sweeping, finalizing }

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
  /// Reference to the runtime for accessing global state.
  // ignore: unused_field
  final LuaRuntime _runtime;

  static int totalRegistrations = 0;
  static final Map<Type, int> allocationHistogram = <Type, int>{};

  GenerationalGCManager(this._runtime);

  /// Whether garbage collection is currently stopped.
  bool _isStopped = false;

  /// Returns whether garbage collection is currently stopped.
  bool get isStopped => _isStopped;

  /// Whether garbage collection is currently in progress (prevents recursive GC)
  bool _isCollecting = false;

  /// Tracks whether an automatic GC trigger has been requested.
  bool _autoTriggerRequested = false;

  /// Temporarily suppress auto-GC triggers during critical allocations.
  /// Used to prevent transient objects from being freed before collectgarbage("count").
  bool _suppressAutoTrigger = false;

  /// Whether automatic GC triggering is enabled for this manager.
  /// When disabled, allocation debt will accumulate but no auto work runs
  /// at safe points until re-enabled. Manual steps still work.
  bool autoTriggerEnabled = true;

  /// GC tuning parameters as described in Lua 5.4 reference manual.

  /// Controls the size of each incremental step.
  /// In Lua, this is logarithmic: a value of n means allocating 2^n bytes between steps.
  /// Default to Lua-like small step size; callers can adjust via tuning APIs.
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
  bool _cycleComplete = true;

  /// Incremental GC state tracking
  GCPhase _currentPhase = GCPhase.idle;
  List<GCObject> _objectsToMark = [];
  List<GCObject> _objectsToSweep = [];
  int _sweepingIndex = 0;
  int _simulatedAllocationDebt = 0;

  /// Public getter for allocation debt (used by interpreter to trigger GC at safe points)
  int get allocationDebt => _simulatedAllocationDebt;
  int _manualStepDebtKb = 0;
  // Removed: _manualStepProgress (unused)
  // Deprecated: previous multi-step tracking target (unused)

  /// Expose current GC phase for observation-sensitive behaviors (e.g.,
  /// iteration over weak-keys tables during finalization should still see
  /// dead keys until weak-key removals are applied after finalizers).
  GCPhase get currentPhase => _currentPhase;
  bool get isFinalizing => _currentPhase == GCPhase.finalizing;
  bool get isCycleActive => _currentPhase != GCPhase.idle;
  bool get isFinalizerActive => _finalizerActive;

  bool get hasPendingFinalizers => _toBeFinalized.isNotEmpty;
  bool get isManualCollectRunning => _manualCollectRunning;

  bool tryEnterManualCollect() {
    if (_manualCollectRunning) {
      return false;
    }
    _manualCollectRunning = true;
    return true;
  }

  void exitManualCollect() {
    _manualCollectRunning = false;
  }

  DateTime? _lastManualCollectTimestamp;
  int _registrationsAtLastManualCollect = 0;
  int _manualCollectCooldown = 0;

  void noteManualCollectCompletion() {
    _lastManualCollectTimestamp = DateTime.now();
    _registrationsAtLastManualCollect = totalRegistrations;
    _manualCollectCooldown = 32;
  }

  void noteManualCollectSkip() {
    _lastManualCollectTimestamp = DateTime.now();
  }

  bool shouldThrottleManualCollect({
    Duration threshold = const Duration(milliseconds: 50),
    int maxNewRegistrations = 4096,
  }) {
    final newRegistrations =
        totalRegistrations - _registrationsAtLastManualCollect;

    if (_manualCollectCooldown > 0 && newRegistrations < maxNewRegistrations) {
      _manualCollectCooldown--;
      return true;
    }
    if (_lastManualCollectTimestamp == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(_lastManualCollectTimestamp!);
    if (elapsed < threshold &&
        newRegistrations < maxNewRegistrations &&
        !hasPendingFinalizers) {
      return true;
    }
    return false;
  }

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

  /// Pending removals for weak-key/all-weak tables that must wait until after
  /// finalizers run (Lua expects weak keys to survive during finalization).
  final Map<Value, Set<dynamic>> _pendingWeakKeyRemovals =
      HashMap<Value, Set<dynamic>>.identity();
  // Removed: _pendingAllWeakRemovals (unused)

  /// Multiplicative factor applied to the allocation debt threshold before
  /// automatic collection is requested. This prevents small, frequent
  /// allocations (like loop scopes) from triggering GC every safe point.
  // Lower multiplier so auto-GC engages promptly in tight loops (e.g. gc.lua GC1)
  static const int _autoTriggerDebtMultiplier = 8;

  int _autoTriggerDebtThreshold() {
    return _allocationDebtThreshold() * _autoTriggerDebtMultiplier;
  }

  int get autoTriggerDebtThreshold => _autoTriggerDebtThreshold();

  /// Whether we're currently in a major collection (affects weak table handling)
  bool _inMajorCollection = false;
  bool _finalizerActive = false;
  bool _manualCollectRunning = false;

  /// Stops the garbage collector.
  ///
  /// This is equivalent to the Lua collectgarbage("stop") function.
  void stop() {
    _isStopped = true;
    Logger.debug('GC stopped', category: 'GC');
  }

  /// Temporarily suppresses auto-GC triggers (for critical allocations).
  void suppressAutoTrigger() {
    _suppressAutoTrigger = true;
  }

  /// Re-enables auto-GC triggers after suppression.
  void resumeAutoTrigger() {
    _suppressAutoTrigger = false;
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
    if (_isStopped || bytes <= 0 || !autoTriggerEnabled) return;

    _simulatedAllocationDebt += bytes;
    Logger.debug(
      'Simulated allocation: bytes=$bytes, debt=$_simulatedAllocationDebt',
      category: 'GC',
    );

    _requestAutoTrigger();
  }

  /// Trigger GC if there's accumulated allocation debt.
  /// This should be called at safe points during execution.
  void triggerGCIfNeeded() {
    if (_simulatedAllocationDebt > 0 && !_isStopped && autoTriggerEnabled) {
      if (Logger.enabled) {
        Logger.debug(
          'Manual triggerGCIfNeeded invoked with debt=$_simulatedAllocationDebt phase=$_currentPhase',
          category: 'GC',
        );
      }
      _autoTriggerRequested = true;
      runPendingAutoTrigger();
    }
  }

  /// Perform an incremental garbage collection step.
  /// Returns true if the collection cycle is complete, false otherwise.
  bool performIncrementalStep(int stepSize) {
    // Note: Even when GC is stopped, manual steps should still work
    // Being "stopped" only means automatic collection is disabled

    final normalizedStepSize = math.max(1, stepSize);
    var remainingBudget = normalizedStepSize;
    var cycleComplete = false;

    Logger.debug(
      'Incremental GC step start: phase=$_currentPhase, stepSize=$normalizedStepSize, budget=$remainingBudget',
      category: 'GC',
    );

    while (remainingBudget > 0 && !cycleComplete) {
      switch (_currentPhase) {
        case GCPhase.idle:
          // Start a new collection cycle and re-evaluate with same budget.
          _startIncrementalCollection();
          continue;

        case GCPhase.marking:
          final workDone = _performMarkingWork(
            normalizedStepSize,
            remainingBudget,
          );
          remainingBudget -= workDone;
          break;

        case GCPhase.sweeping:
          final workDone = _performSweepingWork(
            normalizedStepSize,
            remainingBudget,
          );
          remainingBudget -= workDone;
          break;

        case GCPhase.finalizing:
          final workDone = _performFinalizingWork();
          remainingBudget -= workDone;
          cycleComplete = true;
          break;
      }
    }

    Logger.debug(
      'Incremental GC step end: phase=$_currentPhase, budgetRemaining=$remainingBudget, cycleComplete=$cycleComplete',
      category: 'GC',
    );

    return cycleComplete;
  }

  bool performManualStep(int sizeKb) {
    // Lua treats the argument as kilobytes of work to perform. Use it to scale
    // the incremental budget, so smaller requests need more iterations.
    final requestedKb = math.max(1, sizeKb);
    _manualStepDebtKb += requestedKb;

    // Clamp debt so extremely large requests do not overflow work units. Keep
    // debt in kilobytes; convert to work units below.
    const maxDebtKb = 1 << 20; // ~1GB equivalent budget ceiling
    _manualStepDebtKb = math.min(_manualStepDebtKb, maxDebtKb);

    // Scale KB into work units. Each unit corresponds to one object processed
    // in marking/sweeping. A modest scale factor keeps behaviour close to Lua.
    const workScale = 16; // Tuned to align with Lua step pacing
    final workUnits = math.min(
      math.max(1, _manualStepDebtKb * workScale),
      1 << 20,
    );

    var cycleComplete = false;
    var attempts = 0;
    while (!cycleComplete && attempts < 8) {
      final budget = workUnits * (attempts + 1);
      cycleComplete = performIncrementalStep(budget);
      if (!cycleComplete && _currentPhase == GCPhase.idle) {
        cycleComplete = true;
      }
      attempts++;
    }

    if (cycleComplete) {
      _manualStepDebtKb = 0;
    } else {
      // Reduce debt gradually so repeated calls progress toward completion.
      _manualStepDebtKb = math.max(1, _manualStepDebtKb ~/ 2);
    }

    if (_simulatedAllocationDebt > 0) {
      final reductionBytes = requestedKb * 1024;
      _simulatedAllocationDebt = math.max(
        0,
        _simulatedAllocationDebt - reductionBytes,
      );
      if (_simulatedAllocationDebt == 0) {
        _autoTriggerRequested = false;
      }
    }

    return cycleComplete;
  }

  // Removed: _estimateManualStepTarget (unused)

  void _processSimulatedAllocationDebt({int iterationBudget = 1024}) {
    if (_isStopped || _isCollecting) {
      return;
    }

    final threshold = _allocationDebtThreshold();
    if (threshold <= 0) {
      return;
    }

    _isCollecting = true;
    try {
      var iterations = 0;
      while (true) {
        if (_currentPhase != GCPhase.idle) {
          _simulatedAllocationDebt = math.max(
            _simulatedAllocationDebt,
            threshold,
          );
        }

        if (_simulatedAllocationDebt < threshold) {
          break;
        }

        iterations++;
        final debtKb = math.max(1, (_simulatedAllocationDebt + 1023) ~/ 1024);
        final requested = math.max(stepSize, debtKb);
        final stepBudget = requested.clamp(1, 1 << 20).toInt();
        final cycleComplete = performIncrementalStep(stepBudget);

        if (cycleComplete) {
          _simulatedAllocationDebt = 0;
          break;
        }

        _simulatedAllocationDebt -= threshold;
        if (_simulatedAllocationDebt < 0) {
          _simulatedAllocationDebt = 0;
        }

        if (_currentPhase == GCPhase.idle || iterations >= iterationBudget) {
          break;
        }
      }
    } finally {
      _isCollecting = false;
    }
  }

  int _allocationDebtThreshold() {
    final normalizedStep = math.max(1, stepSize);
    return normalizedStep * 1024;
  }

  void _startIncrementalCollection() {
    Logger.debug('Starting incremental collection cycle', category: 'GC');
    _cycleComplete = false;
    _currentPhase = GCPhase.marking;

    // Clear all marks first
    for (final obj in youngGen.objects) {
      obj.marked = false;
    }
    for (final obj in oldGen.objects) {
      obj.marked = false;
    }

    // Prepare objects to mark (start with roots)
    _objectsToMark = [];
    _objectsToSweep = [];
    _sweepingIndex = 0;

    // Add root objects to marking queue
    final roots = buildRootSet(_runtime);
    for (final root in roots) {
      if (root is GCObject && !_objectsToMark.contains(root)) {
        _objectsToMark.add(root);
      }
    }

    Logger.debug(
      'Initialized marking queue with ${_objectsToMark.length} root objects',
      category: 'GC',
    );

    // If no roots to mark, skip to sweeping
    if (_objectsToMark.isEmpty) {
      Logger.debug(
        'No roots to mark, moving directly to sweeping',
        category: 'GC',
      );
      _currentPhase = GCPhase.sweeping;
      _objectsToSweep = [...youngGen.objects, ...oldGen.objects];
      _sweepingIndex = 0;
    }
  }

  int _performMarkingWork(int stepSize, int budget) {
    Logger.debug(
      'Incremental marking work (${_objectsToMark.length} objects in queue, budget=$budget)',
      category: 'GC',
    );

    if (_objectsToMark.isEmpty) {
      Logger.debug('No objects to mark, switching to sweeping', category: 'GC');
      _currentPhase = GCPhase.sweeping;
      if (_objectsToSweep.isEmpty) {
        _objectsToSweep = [...youngGen.objects, ...oldGen.objects];
        _sweepingIndex = 0;
      }
      return 0;
    }

    var workDone = 0;
    final maxWorkPerStep = math.min(budget, _markingWorkQuota(stepSize));

    while (_objectsToMark.isNotEmpty && workDone < maxWorkPerStep) {
      final obj = _objectsToMark.removeAt(0);

      if (!obj.marked) {
        obj.marked = true;
        Logger.debug(
          'Marked: ${obj.runtimeType} ${obj.hashCode}',
          category: 'GC',
        );

        // Add referenced objects to marking queue
        for (final ref in obj.getReferences()) {
          if (ref is GCObject && !ref.marked && !_objectsToMark.contains(ref)) {
            _objectsToMark.add(ref);
          }
        }
      }

      workDone++;
    }

    Logger.debug(
      'Marking work complete: processed=$workDone, remaining=${_objectsToMark.length}',
      category: 'GC',
    );

    if (_objectsToMark.isEmpty) {
      Logger.debug(
        'Marking phase finished, preparing sweeping phase',
        category: 'GC',
      );
      _currentPhase = GCPhase.sweeping;
      _objectsToSweep = [...youngGen.objects, ...oldGen.objects];
      _sweepingIndex = 0;
    }

    return workDone;
  }

  int _performSweepingWork(int stepSize, int budget) {
    final remainingObjects = _objectsToSweep.length - _sweepingIndex;
    Logger.debug(
      'Incremental sweeping work ($remainingObjects objects remaining, budget=$budget)',
      category: 'GC',
    );

    if (_sweepingIndex >= _objectsToSweep.length) {
      _currentPhase = GCPhase.finalizing;
      return 0;
    }

    var workDone = 0;
    final maxWorkPerStep = math.min(budget, _sweepingWorkQuota(stepSize));
    final objectsToFree = <GCObject>[];

    while (_sweepingIndex < _objectsToSweep.length &&
        workDone < maxWorkPerStep) {
      final obj = _objectsToSweep[_sweepingIndex];

      if (!obj.marked) {
        if (obj is Value &&
            obj.hasMetamethod('__gc') &&
            !_alreadyFinalized.contains(obj)) {
          Logger.debug(
            'Queued for finalization: ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
          _toBeFinalized.add(obj);
        } else {
          objectsToFree.add(obj);
          Logger.debug(
            'Marked for freeing: ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
        }
      }

      _sweepingIndex++;
      workDone++;
    }

    Logger.debug(
      'Sweeping work complete: processed=$workDone, toFree=${objectsToFree.length}, remaining=${_objectsToSweep.length - _sweepingIndex}',
      category: 'GC',
    );

    for (final obj in objectsToFree) {
      MemoryCredits.instance.onFree(obj);
      obj.free();
      youngGen.remove(obj);
      oldGen.remove(obj);
    }

    if (_sweepingIndex >= _objectsToSweep.length) {
      Logger.debug(
        'Sweeping phase complete, moving to finalizing',
        category: 'GC',
      );
      _currentPhase = GCPhase.finalizing;
    }

    return workDone;
  }

  int _markingWorkQuota(int stepSize) {
    return _scaledWorkUnits(stepSize);
  }

  int _sweepingWorkQuota(int stepSize) {
    return _scaledWorkUnits(stepSize);
  }

  int _scaledWorkUnits(int stepSize) {
    final normalized = math.max(1, stepSize);
    return normalized;
  }

  // Removed: _totalWorkBudget (unused)

  int _performFinalizingWork() {
    Logger.debug('Incremental finalizing work', category: 'GC');

    if (_toBeFinalized.isNotEmpty) {
      _finalizerActive = true;
      try {
        final pending = List<GCObject>.from(_toBeFinalized);
        _toBeFinalized.clear();

        for (final obj in pending) {
          var finalized = false;
          if (obj is Value &&
              obj.finalizerEligible &&
              obj.hasMetamethod('__gc')) {
            // Prefer the canonical wrapper for the object's metatable map,
            // falling back to the stored metatableRef when needed.
            Value? metaOwner = obj.metatableRef;
            try {
              final ownerMap = obj.getMetatable();
              if (ownerMap != null) {
                final lookup = Value.lookupCanonicalTableWrapper(ownerMap);
                if (lookup != null) metaOwner = lookup;
              }
            } catch (_) {}
            bool ownerWeakV = false;
            if (metaOwner is Value) {
              ownerWeakV = metaOwner.hasWeakValues;
              if (!ownerWeakV && metaOwner.metatable != null) {
                final rawMode = metaOwner.metatable!['__mode'];
                String modeStr;
                if (rawMode is LuaString) {
                  modeStr = rawMode.toString();
                } else if (rawMode is Value) {
                  modeStr = rawMode.raw?.toString() ?? '';
                } else {
                  modeStr = rawMode?.toString() ?? '';
                }
                if (modeStr.contains('v')) ownerWeakV = true;
              }
            }
            // Skip finalizer if meta-owner is weak-values
            if (!ownerWeakV) {
              // Also re-check metamethod presence under current semantics
              if (!obj.hasMetamethod('__gc')) {
                continue;
              }
              _alreadyFinalized.add(obj);
              try {
                final result = obj.callMetamethod('__gc', [obj]);
                if (result is Future) {
                  // Allow asynchronous finalizers to complete without blocking.
                  result.catchError((error, stack) {
                    Logger.debug(
                      'Async finalizer error: $error',
                      category: 'GC',
                    );
                  });
                }
                finalized = true;
              } catch (error) {
                Logger.debug('Error in finalizer: $error', category: 'GC');
              }
            } else {
              if (Logger.enabled) {
                Logger.debug(
                  'Skip __gc (incremental) due to weak-values meta-owner: obj=${obj.hashCode} owner=${(metaOwner as Value).hashCode}',
                  category: 'GC',
                );
              }
            }
          }

          // Free object now in incremental mode
          MemoryCredits.instance.onFree(obj);
          youngGen.remove(obj);
          oldGen.remove(obj);
          obj.free();
          if (finalized) _alreadyFinalized.remove(obj);
        }
      } finally {
        _finalizerActive = false;
      }
    }

    // Update memory tracking
    _lastMinorBytes = estimateMemoryUse();
    _lastMajorBytes = estimateMemoryUse();
    _simulatedAllocationDebt = 0;

    // Clean up state
    _objectsToMark.clear();
    _objectsToSweep.clear();
    _sweepingIndex = 0;

    // Complete the cycle
    _cycleComplete = true;
    _currentPhase = GCPhase.idle;

    Logger.debug('Incremental collection cycle complete', category: 'GC');
    return 1;
  }

  void ensureTracked(GCObject obj) {
    if (youngGen.objects.contains(obj) || oldGen.objects.contains(obj)) {
      return;
    }

    // Check if this object should be counted for memory credits
    bool shouldCount = true;
    if (obj is Value) {
      // Respect the isTempKey and isMulti flags
      shouldCount = !(obj.isTempKey || obj.isMulti);
    }

    if (obj.isOld) {
      oldGen.add(obj);
      if (shouldCount) {
        MemoryCredits.instance.onAllocate(obj, space: GCGenerationSpace.old);
      }
    } else {
      youngGen.add(obj);
      if (shouldCount) {
        MemoryCredits.instance.onAllocate(obj, space: GCGenerationSpace.young);
      }
    }
  }

  bool _isTracked(GCObject obj) {
    return youngGen.objects.contains(obj) || oldGen.objects.contains(obj);
  }

  /// Registers a new object with the garbage collector.
  ///
  /// New objects are always placed in the young generation (nursery).
  void register(GCObject obj, {bool countAllocation = true}) {
    // Prevent duplicate registrations - if object is already tracked, skip
    if (youngGen.objects.contains(obj) || oldGen.objects.contains(obj)) {
      Logger.debug(
        'Skipping duplicate registration: ${obj.runtimeType} ${obj.hashCode}',
        category: 'GC',
      );
      return;
    }

    totalRegistrations++;
    final type = obj.runtimeType;
    final newCount = (allocationHistogram[type] ?? 0) + 1;
    allocationHistogram[type] = newCount;
    if (Logger.enabled && totalRegistrations % 5000 == 0) {
      final topEntries = allocationHistogram.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final summary = topEntries
          .take(5)
          .map((entry) => '${entry.key}:${entry.value}')
          .join(', ');
      Logger.debug(
        'GC register stats: total=$totalRegistrations, debt=$_simulatedAllocationDebt, topTypes=[$summary]',
        category: 'GC',
      );
    }
    youngGen.add(obj);
    if (countAllocation) {
      // Only count allocation in MemoryCredits if countAllocation is true
      // This excludes transient execution context objects (Environments, Boxes)
      // from collectgarbage("count") to match Lua's behavior
      MemoryCredits.instance.onAllocate(obj, space: GCGenerationSpace.young);
      // Don't trigger GC immediately during registration - only accumulate debt
      // GC will run at safe points during execution
      _simulatedAllocationDebt += obj.estimatedSize;
      _requestAutoTrigger();
    }
    if (obj is Value && obj.isTable) {
      Logger.debug(
        'Register table ${obj.hashCode} weakMode=${obj.tableWeakMode}',
        category: 'GC',
      );
    }
    Logger.debug(
      'Register: ${obj.runtimeType} ${obj.hashCode}',
      category: 'GC',
    );
  }

  void _requestAutoTrigger() {
    if (_isStopped || _suppressAutoTrigger || _simulatedAllocationDebt <= 0) {
      return;
    }
    final triggerThreshold = _autoTriggerDebtThreshold();
    if (_simulatedAllocationDebt >= triggerThreshold) {
      Logger.debug(
        'Auto trigger request check: debt=$_simulatedAllocationDebt threshold=$triggerThreshold requested=$_autoTriggerRequested',
        category: 'GC',
      );
      if (!_autoTriggerRequested && Logger.enabled) {
        Logger.debug(
          'Auto trigger requested: debt=$_simulatedAllocationDebt threshold=$triggerThreshold (stepSize=$stepSize, multiplier=$_autoTriggerDebtMultiplier)',
          category: 'GC',
        );
      }
      _autoTriggerRequested = true;
    }
  }

  /// Runs pending automatic garbage collection work if requested.
  ///
  /// This should only be called from interpreter-designated safe points.
  void runPendingAutoTrigger() {
    Logger.debug(
      'runPendingAutoTrigger start: stopped=$_isStopped enabled=$autoTriggerEnabled requested=$_autoTriggerRequested debt=$_simulatedAllocationDebt collecting=$_isCollecting phase=$_currentPhase',
      category: 'GC',
    );
    if (_isStopped ||
        !autoTriggerEnabled ||
        !_autoTriggerRequested ||
        _simulatedAllocationDebt <= 0) {
      Logger.debug('runPendingAutoTrigger bail', category: 'GC');
      return;
    }

    if (_isCollecting) {
      Logger.debug('runPendingAutoTrigger already collecting', category: 'GC');
      return;
    }

    final debtBefore = _simulatedAllocationDebt;
    final phaseBefore = _currentPhase;
    final stopwatch = Stopwatch()..start();

    _autoTriggerRequested = false;
    _processSimulatedAllocationDebt(iterationBudget: 16);

    final requeueThreshold = _autoTriggerDebtThreshold();
    if (!_isStopped && _simulatedAllocationDebt >= requeueThreshold) {
      // More debt remains; schedule another run at the next safe point.
      _autoTriggerRequested = true;
    }

    stopwatch.stop();
    if (Logger.enabled) {
      Logger.debug(
        'Auto GC safe point: phaseBefore=$phaseBefore, debtBefore=$debtBefore, debtAfter=$_simulatedAllocationDebt, duration=${stopwatch.elapsedMilliseconds}ms',
        category: 'GC',
      );
    }
  }

  /// Drains any in-progress incremental collection cycle by repeatedly
  /// performing incremental steps until the collector returns to the idle
  /// phase or a maximum iteration budget is reached. Returns `true` if the
  /// collector is idle afterwards.
  bool drainCurrentIncrementalCycle({
    int maxIterations = 4096,
    int stepSize = 256,
  }) {
    if (_currentPhase == GCPhase.idle) {
      return true;
    }
    final normalizedStep = math.max(1, stepSize);
    var iterations = 0;
    while (_currentPhase != GCPhase.idle && iterations < maxIterations) {
      final cycleComplete = performIncrementalStep(normalizedStep);
      iterations++;
      if (cycleComplete) {
        break;
      }
    }
    return _currentPhase == GCPhase.idle;
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
    MemoryCredits.instance.onPromote(obj);
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
  List<Object?> buildRootSet(LuaRuntime vm) {
    // Use the interpreter's existing getRoots method which includes:
    // - Current environment (globals)
    // - Call stack
    // - Evaluation stack
    // - Current coroutine and main thread
    // - Active coroutines set
    final roots = vm.getRoots();

    // Add evaluation stack contents explicitly so temporaries stay rooted
    if (vm.evalStack.items.isNotEmpty) {
      roots.addAll(vm.evalStack.items);
    }

    // Include environments and locals referenced by call frames
    for (final frame in vm.callStack.frames) {
      if (frame.env != null) {
        roots.add(frame.env);
      }
      for (final entry in frame.debugLocals) {
        roots.add(entry.value);
      }
    }

    // Seed locals from the current environment explicitly to ensure top-level
    // locals (e.g., in scripts) are discovered even if Box traversal happens
    // later in marking. This does not change reachability; it only ensures
    // locals are discovered early in the mark phase.
    try {
      final env = vm.getCurrentEnv();
      for (final entry in env.values.entries) {
        final box = entry.value;
        roots.add(box);
        final val = box.value;
        if (val is GCObject) {
          roots.add(val);
        }
      }
    } catch (_) {}

    Logger.debug('Built root set with ${roots.length} roots', category: 'GC');
    return roots;
  }

  /// Recursively discovers and marks live objects starting from a given object.
  ///
  /// This implements the mark phase of the mark-and-sweep algorithm,
  /// traversing the object graph to find all reachable objects.
  void _discover(Object? obj) {
    if (obj == null) {
      return;
    }

    Logger.debug(
      'Discover: ${obj.runtimeType} ${obj.hashCode} (inMajorCollection: $_inMajorCollection)',
      category: 'GC',
    );
    if (obj is Box) {
      Logger.debug(
        'Discover Box name=${obj.debugName} value=${obj.value}',
        category: 'GC',
      );
    }

    if (obj is GCObject) {
      // Ensure discovered Value objects are tracked by this manager so they
      // participate in separation/promotion and appear in generations. This
      // restores previous behavior used by the Lua GC integration tests.
      if (obj is Value) {
        ensureTracked(obj);
      }

      if (obj.marked) {
        if (_inMajorCollection &&
            obj is Value &&
            obj.isTable &&
            obj.tableWeakMode != null) {
          _handleTableTraversal(obj);
        }
        return;
      }

      obj.marked = true;

      if (obj is Value && obj.isTable) {
        Logger.debug(
          'Mark table ${obj.hashCode} weakMode=${obj.tableWeakMode}',
          category: 'GC',
        );
        if (_inMajorCollection) {
          _handleTableTraversal(obj);
          return;
        }
      }

      for (final ref in obj.getReferences()) {
        _discover(ref);
      }
      return;
    }

    if (obj is Map) {
      // If this Map belongs to a Value table, delegate discovery to the
      // owning Value wrapper so weak semantics (__mode) are honored. Also
      // make sure we actually discover the owner; otherwise we might skip
      // traversing this table entirely if only the raw Map is rooted.
      final owner = Value.lookupCanonicalTableWrapper(obj);
      if (owner != null) {
        _discover(owner);
        return;
      }

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
        'Map traversal (non-Value owner): ${obj.runtimeType} ${obj.hashCode} with ${obj.length} entries',
        category: 'GC',
      );

      // Only traverse entries that could contain GCObjects
      obj.forEach((key, value) {
        if (key is GCObject || value is GCObject) {
          _discover(key);
          _discover(value);
        }
      });
      return;
    }

    if (obj is Iterable) {
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
      return;
    }

    Logger.debug(
      'Ignoring non-GC object: ${obj.runtimeType} ${obj.hashCode}',
      category: 'GC',
    );
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
      Logger.debug(
        'Table ${table.hashCode} has no weak mode (metatable: ${table.metatable})',
        category: 'GC',
      );
      // Strong table - traverse normally
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
      if (!weakValuesTables.contains(table)) {
        weakValuesTables.add(table);
      }
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
      if (!ephemeronTables.contains(table)) {
        ephemeronTables.add(table);
      }

      if (_inMajorCollection) {
        final tableMap = table.raw as Map;
        for (final entry in tableMap.entries) {
          final key = entry.key;
          if (key is Value && key.marked) {
            key.marked = false;
            Logger.debug(
              'Unmarking weak key ${key.hashCode} for table ${table.hashCode}',
              category: 'GC',
            );
          }
        }
      }

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
      if (!allWeakTables.contains(table)) {
        allWeakTables.add(table);
      }
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
          'WeakValueCheck: table=${table.hashCode} keyType=${key.runtimeType} keyMarked=$keyMarked value=$value valueType=${value.runtimeType} valueMarked=$valueMarked isPrimitive=${value is Value ? value.isPrimitiveLike : false}',
          category: 'GC',
        );

        // If key and value are the same underlying object (common in a[t]=t),
        // the strong key keeps the object alive; do not clear such entries
        // even if the value wrapper itself is unmarked.
        bool sameObject = false;
        if (key is Value && value is Value) {
          sameObject = identical(key, value) || identical(key.raw, value.raw);
        }

        if (!sameObject &&
            ((value is Value &&
                    !value.isPrimitiveLike &&
                    (!value.marked || value.isFreed)) ||
                (_isCollectableNonPrimitiveGC(value) &&
                    !(value as GCObject).marked))) {
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
        // Before removing the entry, preserve the key if it's a Value object
        // This ensures the key survives the collection cycle as per Lua semantics
        if (key is Value && !key.isPrimitiveLike) {
          // Re-mark the key to keep it alive during this collection
          key.marked = true;
          // Add the key back to the appropriate generation so it survives separation
          if (youngGen.objects.contains(key)) {
            // Key is already in young generation, just keep it marked
          } else if (oldGen.objects.contains(key)) {
            // Key is already in old generation, just keep it marked
          } else {
            // Key is not in any generation, add it to young generation
            youngGen.add(key);
            Logger.debug(
              'Added preserved key ${key.hashCode} back to young generation',
              category: 'GC',
            );
          }
          Logger.debug(
            'Preserving weak table key ${key.hashCode} when clearing weak value',
            category: 'GC',
          );
        }
        tableMap.remove(key);
      }
      // Recalculate credits after removing entries to update total tracked memory
      if (entriesToRemove.isNotEmpty) {
        MemoryCredits.instance.recalculate(table);
      }
    }
    weakValuesTables.clear();
  }

  /// Clears dead entries from all-weak tables.
  /// Called after marking phase during major collection.
  void _clearAllWeak() {
    for (final table in allWeakTables) {
      final tableMap = table.raw as Map;
      final keysToRemove = <dynamic>[];
      for (final entry in tableMap.entries) {
        final key = entry.key;
        final value = entry.value;

        // In all-weak tables, primitive-like keys/values (e.g., strings, numbers)
        // behave as immediate values and should not cause removal when only
        // reachable through the weak table. This matches Lua's behavior that
        // allows string->string survivors in kv tables.
        final keyDead =
            (key is Value && !key.isPrimitiveLike && !key.marked) ||
            (_isCollectableNonPrimitiveGC(key) && !(key as GCObject).marked);
        var valueDead =
            (value is Value &&
                !value.isPrimitiveLike &&
                (!value.marked || value.isFreed)) ||
            (_isCollectableNonPrimitiveGC(value) &&
                !(value as GCObject).marked);
        if (!valueDead && value is Value && !_isTracked(value)) {
          if (!value.isPrimitiveLike) {
            valueDead = true;
          }
        }

        if (keyDead || valueDead) {
          keysToRemove.add(entry.key);
        } else {
          // Entry survives - ensure key and value are marked to survive sweep
          if (key is GCObject) {
            key.marked = true;
          }
          if (value is GCObject) {
            value.marked = true;
          }
        }
      }
      for (final k in keysToRemove) {
        tableMap.remove(k);
      }
      // Invalidate cache and recalculate credits after removing entries.
      // Don't manually adjust the cache - let recalculate() rebuild it from scratch
      // to avoid double-decrement bugs.
      if (keysToRemove.isNotEmpty) {
        Value.invalidateStringKeyCache(tableMap);
        MemoryCredits.instance.recalculate(table);
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
            if (_isCollectableNonPrimitiveGC(value) &&
                !(value as GCObject).marked) {
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

  void _scheduleWeakKeyRemoval(Value table, dynamic key) {
    final pending = _pendingWeakKeyRemovals.putIfAbsent(
      table,
      () => HashSet<dynamic>.identity(),
    );
    pending.add(key);
  }

  // Removed: _scheduleAllWeakRemoval (unused)

  bool _isCollectableNonPrimitiveGC(Object? value) {
    return value is GCObject && value is! Value && value is! LuaString;
  }

  void _applyPendingWeakRemovals() {
    void apply(Map<Value, Set<dynamic>> pending) {
      pending.forEach((table, keys) {
        final tableMap = table.raw as Map;
        for (final key in keys) {
          Logger.debug(
            'Applying pending removal for table ${table.hashCode} key=$key',
            category: 'GC',
          );
          tableMap.remove(key);
        }
        // Invalidate cache and recalculate credits after removing entries
        if (keys.isNotEmpty) {
          Value.invalidateStringKeyCache(tableMap);
          MemoryCredits.instance.recalculate(table);
        }
      });
      pending.clear();
    }

    apply(_pendingWeakKeyRemovals);
    // For all-weak tables, entries are cleared before finalizers.
  }

  /// Clean weak-values entries in metatables of objects scheduled for
  /// finalization before we re-mark them. This ensures metamethods whose only
  /// references are weak (e.g., __gc placed in a weak-values metatable) are
  /// removed prior to running finalizers, matching Lua's ordering.
  void _preFinalizerWeakValuesCleanup() {
    if (_toBeFinalized.isEmpty) return;
    for (final obj in _toBeFinalized) {
      if (obj is! Value) continue;
      final metaVal = obj.metatableRef;
      if (metaVal is! Value || !metaVal.isTable) continue;
      // Robust weak-values detection for the meta-owner: prefer canonical
      // wrapper and consult cached/registered weak mode if available.
      Value canonicalOwner;
      try {
        canonicalOwner =
            Value.lookupCanonicalTableWrapper(metaVal.raw) ?? metaVal;
      } catch (_) {
        canonicalOwner = metaVal;
      }
      bool isWeakV =
          canonicalOwner.hasWeakValues || canonicalOwner.cachedHasWeakValues;
      if (!isWeakV && canonicalOwner.metatable != null) {
        final rawMode = canonicalOwner.metatable!['__mode'];
        String modeStr;
        if (rawMode is LuaString) {
          modeStr = rawMode.toString();
        } else if (rawMode is Value) {
          modeStr = rawMode.raw?.toString() ?? '';
        } else {
          modeStr = rawMode?.toString() ?? '';
        }
        if (modeStr.contains('v')) isWeakV = true;
      }
      if (!isWeakV &&
          canonicalOwner.metatable == null &&
          canonicalOwner.metatableRef is Value) {
        final meta = canonicalOwner.metatableRef as Value;
        dynamic rawMode;
        if (meta.raw is Map) {
          final m = meta.raw as Map;
          rawMode = m['__mode'];
          if (rawMode == null) {
            for (final k in m.keys) {
              String? ks;
              if (k is LuaString) {
                ks = k.toString();
              } else if (k is Value) {
                final kr = k.raw;
                if (kr is LuaString) {
                  ks = kr.toString();
                } else if (kr is String) {
                  ks = kr;
                }
              }
              if (ks == '__mode') {
                rawMode = m[k];
                break;
              }
            }
          }
        }
        String modeStr;
        if (rawMode is LuaString) {
          modeStr = rawMode.toString();
        } else if (rawMode is Value) {
          modeStr = rawMode.raw?.toString() ?? '';
        } else {
          modeStr = rawMode?.toString() ?? '';
        }
        if (modeStr.contains('v')) isWeakV = true;
      }
      if (Logger.enabled) {
        Logger.debug(
          'Pre-finalizer: obj=${obj.hashCode} meta=${canonicalOwner.hashCode} mode=${canonicalOwner.tableWeakMode} weakV=$isWeakV entries=${(canonicalOwner.raw as Map).length}',
          category: 'GC',
        );
      }
      if (!isWeakV) continue; // only weak-values relevant here

      final tableMap = canonicalOwner.raw as Map;
      final keysToRemove = <dynamic>[];

      // Always drop __gc from a weak-values meta-owner before running
      // finalizers, regardless of the marking status of its value. Lua tests
      // expect that a __gc stored under a weak-values metatable does not run.
      // Support String, LuaString, or Value(LuaString) keys.
      for (final k in tableMap.keys) {
        String? ks;
        if (k is String) ks = k;
        if (k is LuaString) ks = k.toString();
        if (k is Value) {
          final kr = k.raw;
          if (kr is String) ks = kr;
          if (kr is LuaString) ks = kr.toString();
        }
        if (ks == '__gc') {
          keysToRemove.add(k);
          break;
        }
      }

      for (final entry in tableMap.entries) {
        final value = entry.value;
        // If value is a non-primitive GC object and not marked by the mark
        // phase, it should be cleared from this weak-values table.
        bool dead = false;
        if (value is Value) {
          if (!value.isPrimitiveLike && (!value.marked || value.isFreed)) {
            dead = true;
          }
        } else if (value is GCObject) {
          if (!value.marked) dead = true;
        }
        if (dead) {
          keysToRemove.add(entry.key);
        }
      }

      if (keysToRemove.isNotEmpty) {
        if (Logger.enabled) {
          Logger.debug(
            'Pre-finalizer cleanup: removing ${keysToRemove.length} entries from metatable ${canonicalOwner.hashCode}',
            category: 'GC',
          );
        }
        for (final k in keysToRemove) {
          tableMap.remove(k);
        }
        // Invalidate cache and recalculate credits after removing entries
        Value.invalidateStringKeyCache(tableMap);
        MemoryCredits.instance.recalculate(canonicalOwner);
        if (Logger.enabled) {
          Logger.debug(
            'Pre-finalizer cleanup: remaining entries in meta ${canonicalOwner.hashCode} => ${tableMap.length}',
            category: 'GC',
          );
        }
      }
    }
  }

  /// Additionally, before running finalizers, aggressively clean any all-weak
  /// (kv) tables referenced from the metatable of objects scheduled for
  /// finalization. This ensures assertions that inspect weak tables inside
  /// __gc see the cleared state even if earlier tracking missed an owner.
  void _preFinalizerAllWeakCleanup() {
    if (_toBeFinalized.isEmpty) return;
    for (final obj in _toBeFinalized) {
      if (obj is! Value) continue;
      final metaVal = obj.metatableRef;
      if (metaVal is! Value || !metaVal.isTable) continue;
      final metaMap = metaVal.raw as Map;
      for (final entry in metaMap.entries) {
        final val = entry.value;
        if (val is! Value || !val.isTable) continue;
        if (val.tableWeakMode != 'kv') continue;
        final tableMap = val.raw as Map;
        final keysToRemove = <dynamic>[];
        for (final e in tableMap.entries) {
          final k = e.key;
          final v = e.value;
          final keyDead =
              (k is Value && !k.marked) ||
              (_isCollectableNonPrimitiveGC(k) && !(k as GCObject).marked);
          final valueDead =
              (v is Value && (!v.marked || v.isFreed)) ||
              (_isCollectableNonPrimitiveGC(v) && !(v as GCObject).marked);
          if (keyDead || valueDead) {
            keysToRemove.add(k);
          }
        }
        if (keysToRemove.isNotEmpty) {
          if (Logger.enabled) {
            Logger.debug(
              'Pre-finalizer kv cleanup: removing ${keysToRemove.length} entries from ${val.hashCode}',
              category: 'GC',
            );
          }
          for (final k in keysToRemove) {
            tableMap.remove(k);
          }
          // Invalidate cache and recalculate credits after removing entries
          Value.invalidateStringKeyCache(tableMap);
          MemoryCredits.instance.recalculate(val);
        }
      }
    }
  }

  /// Clears dead entries from weak-keys tables.
  /// Called after ephemeron convergence during major collection.
  void _clearWeakKeys() {
    // Fallback: if no ephemeron tables were recorded during traversal,
    // perform a last-chance scan to discover them, to avoid missing clears
    // due to wrapper/owner mismatches in complex scripts.
    if (ephemeronTables.isEmpty) {
      _collectWeakTablesFromGenerations();
    }
    Logger.debug(
      'Starting weak keys clearing for ${ephemeronTables.length} tables',
      category: 'GC',
    );
    Logger.debug('In major collection: $_inMajorCollection', category: 'GC');

    for (final table in ephemeronTables) {
      final tableMap = table.raw as Map;

      Logger.debug(
        'Checking weak keys table ${table.hashCode} with ${tableMap.length} entries',
        category: 'GC',
      );

      for (final entry in tableMap.entries) {
        final key = entry.key;
        final value = entry.value;
        final keyMarked = (key is GCObject) ? key.marked : false;
        final valueMarked = (value is GCObject) ? value.marked : false;

        if (Logger.enabled) {
          Logger.debug(
            'Entry: key=$key type=${key.runtimeType} (marked: $keyMarked) -> value=$value type=${value.runtimeType} (marked: $valueMarked)',
            category: 'GC',
          );
        }

        // In weak keys tables, remove entries where the key is dead. Be robust
        // against identity/tracking: if a non-primitive Value key is either
        // unmarked OR not tracked by generations, consider it dead.
        bool schedule = false;
        if (key is Value && !key.isPrimitiveLike) {
          final tracked = _isTracked(key);
          if (!key.marked || !tracked) {
            schedule = true;
          }
        } else if (key is GCObject && key is! Value) {
          if (!key.marked) schedule = true;
        }

        if (schedule) {
          if (Logger.enabled) {
            Logger.debug(
              'Scheduling weak key removal for table ${table.hashCode} key=$key (marked=$keyMarked)',
              category: 'GC',
            );
          }
          _scheduleWeakKeyRemoval(table, entry.key);
        }
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
        bool eligible = false;
        if (obj is Value) {
          hasGc = obj.hasMetamethod('__gc');
          // If the object's metamethods are stored in a metatable whose own
          // metatable declares __mode = 'v' (weak values), Lua does not treat
          // __gc as a strong finalizer hook. Do not schedule finalization.
          final metaOwner = obj.metatableRef;
          bool ownerWeakV = false;
          Value? canonicalOwner;
          if (metaOwner is Value) {
            // Prefer canonical wrapper to avoid identity mismatches.
            try {
              canonicalOwner =
                  Value.lookupCanonicalTableWrapper(metaOwner.raw) ?? metaOwner;
            } catch (_) {
              canonicalOwner = metaOwner;
            }
            // Primary: use tableWeakMode (uses cached weak mode and registry).
            ownerWeakV =
                canonicalOwner.hasWeakValues ||
                canonicalOwner.cachedHasWeakValues;
            // Fallback A: inspect current metatable directly if available.
            if (!ownerWeakV && canonicalOwner.metatable != null) {
              final rawMode = canonicalOwner.metatable!['__mode'];
              String modeStr;
              if (rawMode is LuaString) {
                modeStr = rawMode.toString();
              } else if (rawMode is Value) {
                modeStr = rawMode.raw?.toString() ?? '';
              } else {
                modeStr = rawMode?.toString() ?? '';
              }
              if (modeStr.contains('v')) ownerWeakV = true;
            }
            // Fallback B: if owner's metatable is null now, consult the
            // owner's metatableRef raw map for '__mode' (supports LuaString keys).
            if (!ownerWeakV &&
                canonicalOwner.metatable == null &&
                canonicalOwner.metatableRef is Value) {
              final meta = canonicalOwner.metatableRef as Value;
              dynamic rawMode;
              if (meta.raw is Map) {
                final m = meta.raw as Map;
                rawMode = m['__mode'];
                if (rawMode == null) {
                  for (final k in m.keys) {
                    String? ks;
                    if (k is LuaString) {
                      ks = k.toString();
                    } else if (k is Value) {
                      final kr = k.raw;
                      if (kr is LuaString) {
                        ks = kr.toString();
                      } else if (kr is String) {
                        ks = kr;
                      }
                    }
                    if (ks == '__mode') {
                      rawMode = m[k];
                      break;
                    }
                  }
                }
              }
              String modeStr;
              if (rawMode is LuaString) {
                modeStr = rawMode.toString();
              } else if (rawMode is Value) {
                modeStr = rawMode.raw?.toString() ?? '';
              } else {
                modeStr = rawMode?.toString() ?? '';
              }
              if (modeStr.contains('v')) ownerWeakV = true;
            }
          }
          if (Logger.enabled && hasGc) {
            final mtInfo = (canonicalOwner is Value)
                ? (canonicalOwner.metatable?.keys.toString() ?? 'null')
                : 'n/a';
            final ownerMode = (canonicalOwner is Value)
                ? canonicalOwner.tableWeakMode
                : null;
            Logger.debug(
              'Finalize check: obj=${obj.hashCode} hasGc=$hasGc eligible=${obj.finalizerEligible} owner=${(metaOwner is Value) ? metaOwner.hashCode : 'null'} owner.mtKeys=$mtInfo ownerMode=$ownerMode ownerWeakV=$ownerWeakV',
              category: 'GC',
            );
          }
          if (ownerWeakV) {
            if (Logger.enabled && hasGc) {
              Logger.debug(
                'Finalizer suppressed due to weak-values meta-owner: obj=${obj.hashCode} owner=${(metaOwner as Value).hashCode}',
                category: 'GC',
              );
            }
            hasGc = false;
          }
          eligible = obj.finalizerEligible;
        }

        if (hasGc && eligible && !_alreadyFinalized.contains(obj)) {
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
          MemoryCredits.instance.onFree(obj);
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
    _finalizerActive = true;
    try {
      // According to Lua spec, finalizers are called in an unspecified order.
      // Make a copy of the list to avoid concurrent modification during iteration
      // (finalizers might trigger GC which could modify _toBeFinalized)
      final objectsToFinalize = _toBeFinalized.toList();
      _toBeFinalized.clear();

      for (final obj in objectsToFinalize) {
        if (obj is! Value) {
          if (Logger.enabled) {
            Logger.debug(
              'Skip __gc for non-Value object during finalization: ${obj.runtimeType} ${obj.hashCode}',
              category: 'GC',
            );
          }
          continue;
        }

        final value = obj;

        // Skip running __gc if the object's metamethods are under a weak-values
        // metatable owner. In this case, Lua does not consider __gc a strong
        // finalizer hook.
        // Prefer the canonical wrapper for the object's metatable map,
        // falling back to the stored metatableRef when needed.
        Value? metaOwner = value.metatableRef;
        Value? canonicalOwner;
        bool ownerWeakV = false;
        try {
          final ownerMap = value.getMetatable();
          if (ownerMap != null) {
            final lookup = Value.lookupCanonicalTableWrapper(ownerMap);
            if (lookup != null) metaOwner = lookup;
          }
        } catch (_) {}
        if (metaOwner is Value) {
          try {
            canonicalOwner =
                Value.lookupCanonicalTableWrapper(metaOwner.raw) ?? metaOwner;
          } catch (_) {
            canonicalOwner = metaOwner;
          }
          ownerWeakV =
              canonicalOwner.hasWeakValues ||
              canonicalOwner.cachedHasWeakValues;
          if (!ownerWeakV && canonicalOwner.metatable != null) {
            final rawMode = canonicalOwner.metatable!['__mode'];
            String modeStr;
            if (rawMode is LuaString) {
              modeStr = rawMode.toString();
            } else if (rawMode is Value) {
              modeStr = rawMode.raw?.toString() ?? '';
            } else {
              modeStr = rawMode?.toString() ?? '';
            }
            if (modeStr.contains('v')) ownerWeakV = true;
          }
          if (!ownerWeakV &&
              canonicalOwner.metatable == null &&
              canonicalOwner.metatableRef is Value) {
            final meta = canonicalOwner.metatableRef as Value;
            dynamic rawMode;
            if (meta.raw is Map) {
              final m = meta.raw as Map;
              rawMode = m['__mode'];
              if (rawMode == null) {
                for (final k in m.keys) {
                  String? ks;
                  if (k is LuaString) {
                    ks = k.toString();
                  } else if (k is Value) {
                    final kr = k.raw;
                    if (kr is LuaString) {
                      ks = kr.toString();
                    } else if (kr is String) {
                      ks = kr;
                    }
                  }
                  if (ks == '__mode') {
                    rawMode = m[k];
                    break;
                  }
                }
              }
            }
            String modeStr;
            if (rawMode is LuaString) {
              modeStr = rawMode.toString();
            } else if (rawMode is Value) {
              modeStr = rawMode.raw?.toString() ?? '';
            } else {
              modeStr = rawMode?.toString() ?? '';
            }
            if (modeStr.contains('v')) ownerWeakV = true;
          }
        }
        if (ownerWeakV) {
          if (Logger.enabled) {
            Logger.debug(
              'Skip __gc due to weak-values meta-owner during finalization: obj=${value.hashCode} owner=${(canonicalOwner ?? metaOwner).hashCode}',
              category: 'GC',
            );
          }
          // Do not mark as finalized; allow normal collection to proceed.
          continue;
        }
        // Also re-check current metamethod under semantics; if absent, skip.
        if (value.getMetamethod('__gc') == null) {
          continue;
        }
        // Mark as finalized BEFORE calling __gc. This prevents re-finalization
        // if the object is resurrected and then becomes dead again.
        _alreadyFinalized.add(value);
        try {
          Logger.debug(
            'Run finalizer: ${value.runtimeType} ${value.hashCode}',
            category: 'GC',
          );
          await value.callMetamethodAsync('__gc', [value]);
        } catch (e) {
          // Errors in finalizers are reported but not propagated.
          Logger.debug('Error in finalizer: $e', category: 'GC');
        }
      }
    } finally {
      _finalizerActive = false;
    }
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
    _currentPhase = GCPhase.idle;

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
        final needsFinalizer =
            obj is Value &&
            obj.hasMetamethod('__gc') &&
            !_alreadyFinalized.contains(obj);
        if (needsFinalizer) {
          Logger.debug(
            'Minor queued finalizer: ${obj.runtimeType} ${obj.hashCode}',
            category: 'GC',
          );
          _toBeFinalized.add(obj);
          survivors.add(obj);
        } else {
          final credits = obj.estimatedSize;
          Logger.debug(
            'Minor free: ${obj.runtimeType} ${obj.hashCode}, credits=${(credits / 1024).toStringAsFixed(2)} KB',
            category: 'GC',
          );
          MemoryCredits.instance.onFree(obj);
          obj.free();
        }
      }
    }

    // Promote all survivors of a minor collection to the old generation.
    for (final obj in survivors) {
      promote(obj);
    }

    youngGen.objects.clear();

    _lastMinorBytes = estimateMemoryUse();
    _cycleComplete = true;
    _currentPhase = GCPhase.idle;
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
    _currentPhase = GCPhase.idle;
    _inMajorCollection = true;
    if (Logger.enabled) {
      Logger.debug(
        'Major pre-count: young=${youngGen.objects.length} old=${oldGen.objects.length}',
        category: 'GC',
      );
    }

    // Ensure all objects participate in this major collection cycle.
    // Without clearing existing marks, objects touched by prior incremental
    // passes remain marked and skip traversal, which breaks weak-table logic.
    _resetMarksForMajorCycle();

    // Clear weak table tracking lists from previous collection
    weakValuesTables.clear();
    ephemeronTables.clear();
    allWeakTables.clear();

    // Phase 1: Mark all reachable objects
    _markGeneration(youngGen, roots);
    _markGeneration(oldGen, roots);

    // Ensure top-level locals (Boxes in the active environment chains for the
    // provided roots) are discovered before weak clearing. This guarantees
    // discovery order so live locals are marked when we clear kv tables,
    // without unintentionally pulling in the interpreter's global environment
    // when tests use custom, isolated Environment roots.
    try {
      final visited = HashSet<Environment>.identity();
      for (final root in roots) {
        if (root is! Environment) continue;
        Environment? env = root;
        while (env != null && visited.add(env)) {
          for (final entry in env.values.entries) {
            final boxed = entry.value;
            final val = boxed.value;
            if (val is GCObject) {
              _discover(val);
            }
          }
          env = env.parent;
        }
      }
    } catch (_) {}

    // Ensure weak tables are tracked even if discovered via raw Map roots
    // or alternate wrappers: scan generations and then roots for tables with
    // weak modes. The root scan is a safety net for wrappers that may not
    // have been enrolled into generations yet under complex scripts.
    _collectWeakTablesFromGenerations();
    _collectWeakTablesFromRoots(roots);

    // Phase 2: Ephemeron convergence for weak keys tables (while objects are still marked)
    _convergeEphemerons();

    // Phase 3: Clear weak table entries (while objects are still marked)
    _clearWeakValues();
    _clearWeakKeys();
    _clearAllWeak();

    // Phase 4: Separate survivors from dead, and identify finalizables
    final beforeYoung = youngGen.objects.length;
    final beforeOld = oldGen.objects.length;
    _separate(youngGen);
    _separate(oldGen);
    if (Logger.enabled) {
      Logger.debug(
        'Major post-separate: young=${youngGen.objects.length} (was $beforeYoung) old=${oldGen.objects.length} (was $beforeOld)',
        category: 'GC',
      );
    }

    // Phase 5: Clean weak-values in metatables of objects scheduled for
    // finalization, so __gc stored via weak-values will be cleared before we
    // attempt to run finalizers (matches Lua semantics for this scenario).
    _preFinalizerWeakValuesCleanup();
    _preFinalizerAllWeakCleanup();

    // Phase 6: Re-mark objects to be finalized to handle resurrection
    for (final obj in _toBeFinalized) {
      _discover(obj);
    }

    // Phase 7: Run finalizers for objects collected in this cycle.
    // Expose the finalizing phase so that observation-sensitive operations
    // (like next()/pairs over weak-keys tables) can see entries until removals
    // are applied after finalizers, matching Lua semantics.
    _currentPhase = GCPhase.finalizing;
    await _callFinalizersAsync();
    // Note: We intentionally keep phase as finalizing until after applying
    // pending weak-key removals so iterators in finalizers can observe keys.

    // Weak keys/all-weak entries are only cleared after finalizers run to
    // match Lua's observation order during __gc metamethods.
    _applyPendingWeakRemovals();

    _lastMajorBytes = estimateMemoryUse();
    _cycleComplete =
        true; // The full cycle (including finalization) is now complete
    _currentPhase = GCPhase.idle;
    _inMajorCollection = false;
    // Ensure tracking lists are empty post-collection per tests and spec
    weakValuesTables.clear();
    ephemeronTables.clear();
    allWeakTables.clear();
    Logger.debug('Major collection complete', category: 'GC');
  }

  void _collectWeakTablesFromGenerations() {
    final beforeK = ephemeronTables.length;
    final beforeV = weakValuesTables.length;
    final beforeKV = allWeakTables.length;
    void scan(Generation gen) {
      final snapshot = List<GCObject>.from(gen.objects);
      for (final obj in snapshot) {
        // Only consider tables that survived the mark phase. Unreachable
        // weak tables must not influence clearing; enlisting them here would
        // allow their entries to preserve otherwise collectable keys/values
        // during _clearWeakValues/_clearWeakKeys, violating Lua semantics.
        if (!obj.marked) {
          continue;
        }
        if (obj is Value && obj.isTable) {
          final mode = obj.tableWeakMode;
          if (Logger.enabled && mode != null) {
            Logger.debug(
              'Weak table candidate in gen(${gen == youngGen ? 'young' : 'old'}): table=${obj.hashCode} mode=$mode',
              category: 'GC',
            );
          }
          if (mode == 'k') {
            if (!ephemeronTables.contains(obj)) ephemeronTables.add(obj);
          } else if (mode == 'v') {
            if (!weakValuesTables.contains(obj)) weakValuesTables.add(obj);
          } else if (mode == 'kv') {
            if (!allWeakTables.contains(obj)) allWeakTables.add(obj);
          }
          // Also consider the object's metatable as a weak table owner if its
          // own metatable declares __mode. This captures cases like
          // setmetatable(getmetatable(u), { __mode = 'v' }) where weakness
          // applies to entries in the metatable of 'u'.
          final metaOwner = obj.metatableRef;
          if (metaOwner is Value && metaOwner.isTable) {
            final metaMode = metaOwner.tableWeakMode;
            if (Logger.enabled && metaMode != null) {
              Logger.debug(
                'Weak meta-owner in gen(${gen == youngGen ? 'young' : 'old'}): table=${metaOwner.hashCode} mode=$metaMode (owner=${obj.hashCode})',
                category: 'GC',
              );
            }
            if (metaMode == 'k') {
              if (!ephemeronTables.contains(metaOwner)) {
                ephemeronTables.add(metaOwner);
              }
            } else if (metaMode == 'v') {
              if (!weakValuesTables.contains(metaOwner)) {
                weakValuesTables.add(metaOwner);
              }
            } else if (metaMode == 'kv') {
              if (!allWeakTables.contains(metaOwner)) {
                allWeakTables.add(metaOwner);
              }
            }
          }
        }
      }
    }

    scan(youngGen);
    scan(oldGen);
    if (Logger.enabled) {
      Logger.debug(
        'Weak table tracking: k:$beforeK->${ephemeronTables.length} v:$beforeV->${weakValuesTables.length} kv:$beforeKV->${allWeakTables.length}',
        category: 'GC',
      );
    }
  }

  void _collectWeakTablesFromRoots(List<Object?> roots) {
    final visited = HashSet<Object>.identity();

    void scan(Object? obj) {
      if (obj == null) return;
      if (!visited.add(obj)) return;

      if (obj is Value) {
        if (obj.isTable) {
          final mode = obj.tableWeakMode;
          if (mode == 'k') {
            if (!ephemeronTables.contains(obj)) ephemeronTables.add(obj);
          } else if (mode == 'v') {
            if (!weakValuesTables.contains(obj)) weakValuesTables.add(obj);
          } else if (mode == 'kv') {
            if (!allWeakTables.contains(obj)) allWeakTables.add(obj);
          }

          final bool strongKeys = mode != 'k' && mode != 'kv';
          final bool strongValues = mode != 'v' && mode != 'kv';
          for (final ref in obj.getReferencesForGC(
            strongKeys: strongKeys,
            strongValues: strongValues,
          )) {
            scan(ref);
          }
          return;
        }
        for (final ref in obj.getReferences()) {
          scan(ref);
        }
        return;
      }

      if (obj is GCObject) {
        for (final ref in obj.getReferences()) {
          scan(ref);
        }
        return;
      }

      if (obj is Map) {
        final owner = Value.lookupCanonicalTableWrapper(obj);
        if (owner != null) {
          scan(owner);
          return;
        }
        obj.forEach((k, v) {
          if (k is GCObject || k is Value) scan(k);
          if (v is GCObject || v is Value) scan(v);
        });
        return;
      }

      if (obj is Iterable) {
        for (final item in obj) {
          if (item is GCObject || item is Value) scan(item);
        }
        return;
      }
    }

    for (final root in roots) {
      scan(root);
    }

    if (Logger.enabled) {
      Logger.debug(
        'Weak table tracking (root scan): k=${ephemeronTables.length} v=${weakValuesTables.length} kv=${allWeakTables.length}',
        category: 'GC',
      );
    }
  }

  void _resetMarksForMajorCycle() {
    int clearedCount = 0;
    void clearMarks(Generation gen) {
      for (final obj in gen.objects) {
        if (obj.marked) {
          obj.marked = false;
          clearedCount++;
        }
      }
    }

    clearMarks(youngGen);
    clearMarks(oldGen);

    for (final obj in _toBeFinalized) {
      obj.marked = false;
      clearedCount++;
    }

    void unmark(Object? root) {
      if (root is GCObject && root.marked) {
        root.marked = false;
        clearedCount++;
      }
    }

    unmark(_runtime.getCurrentEnv());
    unmark(_runtime.callStack);
    unmark(_runtime.evalStack);
    unmark(_runtime.getCurrentCoroutine());
    unmark(_runtime.getMainThread());

    void unmarkEnvChain(Environment? env) {
      final visited = HashSet<Environment>.identity();
      Environment? current = env;
      while (current != null && visited.add(current)) {
        if (current.marked) {
          current.marked = false;
          clearedCount++;
        }
        current = current.parent;
      }
    }

    unmarkEnvChain(_runtime.getCurrentEnv());

    Logger.debug(
      'Reset $clearedCount marks before major collection (young=${youngGen.objects.length}, old=${oldGen.objects.length})',
      category: 'GC',
    );
  }

  /// Returns the current tracked memory credits without rescanning.
  ///
  /// Credits are maintained incrementally via onAllocate/onFree/onPromote calls.
  /// For debugging or validation, use [validateMemoryTracking()] instead.
  int estimateMemoryUse() {
    return MemoryCredits.instance.totalCredits;
  }

  /// Validates credit tracking by rescanning all generations.
  ///
  /// This is for debugging only - normal operation should not need this.
  /// Returns true if tracked credits match actual generation contents.
  bool validateMemoryTracking() {
    final beforeTotal = MemoryCredits.instance.totalCredits;
    MemoryCredits.instance.reconcileGenerations(
      young: youngGen.objects,
      old: oldGen.objects,
    );
    final afterTotal = MemoryCredits.instance.totalCredits;
    return beforeTotal == afterTotal;
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
    final roots = buildRootSet(_runtime);
    await majorCollection(roots);
  }
}
