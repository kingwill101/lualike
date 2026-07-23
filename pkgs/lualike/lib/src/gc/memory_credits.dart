import 'dart:collection';

import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';
import 'package:lualike/src/runtime/lua_slot.dart';

/// Identifies the generation an object currently belongs to for credit
/// accounting purposes.
enum GCGenerationSpace { young, old }

/// Tracks the garbage collector "allocation credits" – an abstract unit that
/// mimics the relative memory cost of runtime structures.
///
/// The manager keeps a running tally for young and old generations so that GC
/// scheduling decisions can use the same numbers without walking the heap on
/// every query. Whenever the bookkeeping might drift (for instance because a
/// table changed size), clients can ask the tracker to reconcile its view with
/// the actual generations.
class MemoryCredits {
  MemoryCredits._();

  static final MemoryCredits instance = MemoryCredits._();

  /// When true, bookkeeping uses fields on [GCObject] instead of Expando / Set
  /// side tables. The fast path is the new default for performance-sensitive
  /// apps, but callers can disable it to preserve the older bookkeeping shape.
  static bool useDirectObjectTracking = true;

  // Debug: Track allocation stack traces
  static bool enableStackTraces = false;
  final Expando<StackTrace> _objectStackTraces = Expando<StackTrace>(
    'objectStackTraces',
  );
  final List<GCObject> _trackedObjects = [];
  final Expando<int> _objectCredits = Expando<int>('gcCredits');
  final Set<GCObject> _excludedObjects = HashSet<GCObject>.identity();

  int _total = 0;
  int _young = 0;
  int _old = 0;

  int get totalCredits => _total;
  int get youngCredits => _young;
  int get oldCredits => _old;

  bool _isExcluded(GCObject obj) =>
      useDirectObjectTracking ? obj.gcExcluded : _excludedObjects.contains(obj);

  int? _creditsOf(GCObject obj) =>
      useDirectObjectTracking ? obj.gcCredits : _objectCredits[obj];

  void _setCredits(GCObject obj, int? credits) {
    if (useDirectObjectTracking) {
      obj.gcCredits = credits;
    } else {
      _objectCredits[obj] = credits;
    }
  }

  void _setExcluded(GCObject obj, bool value) {
    if (useDirectObjectTracking) {
      obj.gcExcluded = value;
    } else if (value) {
      _excludedObjects.add(obj);
    } else {
      _excludedObjects.remove(obj);
    }
  }

  /// Records a freshly allocated object.
  void onAllocate(GCObject obj, {required GCGenerationSpace space}) {
    // Check if object already has credits assigned - if so, skip to avoid double-counting.
    final existingCredits = _creditsOf(obj);
    if (existingCredits != null) {
      _setExcluded(obj, false);
      if (obj.gcSpace != space) {
        obj.gcSpace = space;
      }
      return;
    }

    if (_isExcluded(obj)) {
      _setExcluded(obj, false);
      onAllocate(obj, space: space);
      return;
    }

    final credits = obj.estimatedSize;

    // Debug: Capture stack trace if enabled
    if (enableStackTraces) {
      // Capture current stack trace BEFORE any async operations
      try {
        throw Exception('Stack trace capture');
      } catch (e, stackTrace) {
        _objectStackTraces[obj] = stackTrace;
      }
      // Only add if not already in the list (prevent duplicate entries)
      if (!_trackedObjects.contains(obj)) {
        _trackedObjects.add(obj);
      }
    }

    // Debug: Log allocations during large operations
    if (Logger.enabled && _total > 1000000 && credits > 100) {
      final objType = obj is Value
          ? 'Value(${rawLuaSlot(obj)?.runtimeType ?? 'null'})'
          : obj.runtimeType.toString();
      Logger.debugLazy(
        () =>
            '[MemoryCredits] onAllocate during large op: $objType#${obj.hashCode}, credits=$credits, _total: $_total -> ${_total + credits}',
        category: 'GC',
      );
    }

    _setCredits(obj, credits);
    obj.gcSpace = space;
    _total += credits;
    if (space == GCGenerationSpace.young) {
      _young += credits;
    } else {
      _old += credits;
    }
  }

  /// Tracks an object for generation bookkeeping without charging it against
  /// Lua-visible memory use.
  ///
  /// This is used for wrappers and runtime helpers that still need correct
  /// generation placement, promotion, and reclamation bookkeeping, but should
  /// not contribute to Lua's externally reported memory pressure. Recording the
  /// generation here avoids special cases later in [onPromote], [onFree], and
  /// [reconcileGenerations], while the zero credit keeps them out of the
  /// collector's accounting totals.
  void onTrackExcluded(GCObject obj, {required GCGenerationSpace space}) {
    _setExcluded(obj, true);
    obj.gcSpace = space;
  }

  /// Adjusts the tracked credits when an object is promoted.
  void onPromote(GCObject obj) {
    if (_isExcluded(obj)) {
      return;
    }

    final credits = _creditsOf(obj);
    if (credits == null) {
      return;
    }

    final space = obj.gcSpace;
    if (space == GCGenerationSpace.young) {
      _young -= credits;
      _old += credits;
    }
    obj.gcSpace = GCGenerationSpace.old;
  }

  /// Updates bookkeeping after an object has been reclaimed.
  void onFree(GCObject obj) {
    if (_isExcluded(obj)) {
      _setExcluded(obj, false);
      _setCredits(obj, null);
      obj.gcSpace = null;
      return;
    }

    final credits = _creditsOf(obj);
    if (credits == null) {
      return;
    }

    final space = obj.gcSpace;
    if (space == GCGenerationSpace.young) {
      _young -= credits;
    } else if (space == GCGenerationSpace.old) {
      _old -= credits;
    }
    _total -= credits;

    _setCredits(obj, null);
    obj.gcSpace = null;
  }

  /// Recalculates the cost of an object after it changed shape (for example a
  /// table gaining or losing entries).
  void recalculate(GCObject obj) {
    if (_isExcluded(obj)) {
      return;
    }

    final space = obj.gcSpace;
    if (space == null) {
      return;
    }
    final previous = _creditsOf(obj) ?? 0;
    final updated = obj.estimatedSize;
    if (updated == previous) {
      return;
    }
    final diff = updated - previous;
    _setCredits(obj, updated);
    _total += diff;
    if (space == GCGenerationSpace.young) {
      _young += diff;
    } else {
      _old += diff;
    }
  }

  /// Ensures that the tracked credits match the actual content of the two
  /// generations. This is a safety net for places where we might not know about
  /// mutations ahead of time.
  void reconcileGenerations({
    required Iterable<GCObject> young,
    required Iterable<GCObject> old,
  }) {
    var recalculatedYoung = 0;
    var recalculatedOld = 0;

    for (final obj in young) {
      final excluded = _isExcluded(obj);
      final credits = excluded ? 0 : obj.estimatedSize;
      if (!excluded) {
        recalculatedYoung += credits;
      }
      if (excluded) {
        _setCredits(obj, null);
        obj.gcSpace = null;
        _setExcluded(obj, true);
      } else {
        _setCredits(obj, credits);
        obj.gcSpace = GCGenerationSpace.young;
        _setExcluded(obj, false);
      }
    }

    for (final obj in old) {
      final excluded = _isExcluded(obj);
      final credits = excluded ? 0 : obj.estimatedSize;
      if (!excluded) {
        recalculatedOld += credits;
      }
      if (excluded) {
        _setCredits(obj, null);
        obj.gcSpace = null;
        _setExcluded(obj, true);
      } else {
        _setCredits(obj, credits);
        obj.gcSpace = GCGenerationSpace.old;
        _setExcluded(obj, false);
      }
    }

    _young = recalculatedYoung;
    _old = recalculatedOld;
    _total = recalculatedYoung + recalculatedOld;
  }

  /// Prints an allocation tree showing what objects are currently tracked
  /// and where they were allocated from (if stack traces are enabled).
  void printAllocationTree() {
    final buffer = StringBuffer();
    buffer.writeln('\n=== Memory Allocation Tree ===');
    buffer.writeln('Total Credits: $_total ($_young young, $_old old)');

    // Create a snapshot to avoid concurrent modification during iteration
    final snapshot = List<GCObject>.from(_trackedObjects);

    buffer.writeln('Tracked Objects: ${snapshot.length}');
    for (final obj in snapshot) {
      buffer.writeln('$obj');
    }

    buffer.writeln();

    // Group by type
    final byType = <String, List<GCObject>>{};
    for (final obj in snapshot) {
      final credits = _creditsOf(obj);
      if (credits != null && credits > 0) {
        String typeName;
        if (obj is Value) {
          final raw = rawLuaSlot(obj);
          typeName = 'Value(${raw?.runtimeType ?? 'null'})';
        } else {
          typeName = obj.runtimeType.toString();
        }
        byType.putIfAbsent(typeName, () => []).add(obj);
      }
    }

    // Sort by total credits per type
    final sortedTypes = byType.entries.toList()
      ..sort((a, b) {
        final aTotal = a.value.fold<int>(
          0,
          (sum, obj) => sum + (_creditsOf(obj) ?? 0),
        );
        final bTotal = b.value.fold<int>(
          0,
          (sum, obj) => sum + (_creditsOf(obj) ?? 0),
        );
        return bTotal.compareTo(aTotal);
      });

    for (final entry in sortedTypes) {
      final typeName = entry.key;
      final objects = entry.value;
      final totalCredits = objects.fold<int>(
        0,
        (sum, obj) => sum + (_creditsOf(obj) ?? 0),
      );

      buffer.writeln(
        '$typeName: ${objects.length} objects, $totalCredits credits',
      );

      // Show top 3 instances with stack traces
      final sortedObjs = objects.toList()
        ..sort(
          (a, b) => (_creditsOf(b) ?? 0).compareTo(_creditsOf(a) ?? 0),
        );

      for (var i = 0; i < sortedObjs.length && i < 3; i++) {
        final obj = sortedObjs[i];
        final credits = _creditsOf(obj) ?? 0;

        // Add useful object info to the output
        String objInfo = '#${obj.hashCode}: $credits credits';
        if (obj is Value) {
          if (obj.isTempKey) {
            objInfo += ' [TEMP]';
          }
          final raw = rawLuaSlot(obj);
          if (raw is LuaString && raw.length <= 200) {
            final preview = raw.toString();
            final truncated = preview.length > 50
                ? '${preview.substring(0, 50)}...'
                : preview;
            objInfo += ' content="$truncated"';
          } else if (raw is String && raw.length <= 200) {
            final truncated = raw.length > 50
                ? '${raw.substring(0, 50)}...'
                : raw;
            objInfo += ' content="$truncated"';
          }
        }
        buffer.writeln('  ├─ $objInfo');

        if (enableStackTraces) {
          final trace = _objectStackTraces[obj];
          if (trace != null) {
            // Extract relevant frames with more context
            final allFrames = trace.toString().split('\n');

            allFrames.removeRange(0, 2);

            for (final frame in allFrames) {
              buffer.writeln('  │  $frame');
            }

            if (allFrames.isEmpty) {
              buffer.writeln('  │  (no relevant stack frames)');
            }
          }
        }
      }
      if (objects.length > 3) {
        buffer.writeln('  └─ ... and ${objects.length - 3} more');
      }
      buffer.writeln();
    }

    buffer.writeln('=============================\n');
    print(buffer.toString());
  }

  /// Clears tracked objects list (for debugging specific allocations)
  void clearTrackedObjects() {
    _trackedObjects.clear();
  }
}
