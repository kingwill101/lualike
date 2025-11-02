import 'package:lualike/lualike.dart';
import 'package:lualike/src/gc/gc.dart';

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

  final Expando<int> _objectCredits = Expando<int>('gcCredits');
  final Expando<GCGenerationSpace> _objectSpaces = Expando<GCGenerationSpace>(
    'gcSpace',
  );

  // Debug: Track allocation stack traces
  static bool enableStackTraces = false;
  final Expando<StackTrace> _objectStackTraces = Expando<StackTrace>(
    'objectStackTraces',
  );
  final List<GCObject> _trackedObjects = [];

  int _total = 0;
  int _young = 0;
  int _old = 0;

  int get totalCredits => _total;
  int get youngCredits => _young;
  int get oldCredits => _old;

  /// Records a freshly allocated object.
  void onAllocate(GCObject obj, {required GCGenerationSpace space}) {
    // Check if object already has credits assigned - if so, skip to avoid double-counting
    final existingCredits = _objectCredits[obj];
    if (existingCredits != null) {
      // Object already tracked - just update space if needed
      final existingSpace = _objectSpaces[obj];
      if (existingSpace != space) {
        _objectSpaces[obj] = space;
      }
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
          ? 'Value(${obj.raw?.runtimeType ?? 'null'})'
          : obj.runtimeType.toString();
      Logger.debug(
        '[MemoryCredits] onAllocate during large op: $objType#${obj.hashCode}, credits=$credits, _total: $_total -> ${_total + credits}',
        category: 'GC',
      );
    }

    _objectCredits[obj] = credits;
    _objectSpaces[obj] = space;
    _total += credits;
    if (space == GCGenerationSpace.young) {
      _young += credits;
    } else {
      _old += credits;
    }
  }

  /// Adjusts the tracked credits when an object is promoted.
  void onPromote(GCObject obj) {
    final credits = _objectCredits[obj];
    if (credits == null) {
      return;
    }
    final space = _objectSpaces[obj];
    if (space == GCGenerationSpace.young) {
      _young -= credits;
      _old += credits;
      _objectSpaces[obj] = GCGenerationSpace.old;
    } else {
      _objectSpaces[obj] = GCGenerationSpace.old;
    }
  }

  /// Updates bookkeeping after an object has been reclaimed.
  void onFree(GCObject obj) {
    final credits = _objectCredits[obj];
    if (credits == null) {
      return;
    }
    final space = _objectSpaces[obj];
    if (space == GCGenerationSpace.young) {
      _young -= credits;
    } else if (space == GCGenerationSpace.old) {
      _old -= credits;
    }
    _total -= credits;
    _objectCredits[obj] = null;
    _objectSpaces[obj] = null;
  }

  /// Recalculates the cost of an object after it changed shape (for example a
  /// table gaining or losing entries).
  void recalculate(GCObject obj) {
    final space = _objectSpaces[obj];
    if (space == null) {
      return;
    }
    final previous = _objectCredits[obj] ?? 0;
    final updated = obj.estimatedSize;
    if (updated == previous) {
      return;
    }
    final diff = updated - previous;
    _objectCredits[obj] = updated;
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
      final credits = obj.estimatedSize;
      recalculatedYoung += credits;
      _objectCredits[obj] = credits;
      _objectSpaces[obj] = GCGenerationSpace.young;
    }

    for (final obj in old) {
      final credits = obj.estimatedSize;
      recalculatedOld += credits;
      _objectCredits[obj] = credits;
      _objectSpaces[obj] = GCGenerationSpace.old;
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
      final credits = _objectCredits[obj];
      if (credits != null && credits > 0) {
        String typeName;
        if (obj is Value) {
          final raw = obj.raw;
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
          (sum, obj) => sum + (_objectCredits[obj] ?? 0),
        );
        final bTotal = b.value.fold<int>(
          0,
          (sum, obj) => sum + (_objectCredits[obj] ?? 0),
        );
        return bTotal.compareTo(aTotal);
      });

    for (final entry in sortedTypes) {
      final typeName = entry.key;
      final objects = entry.value;
      final totalCredits = objects.fold<int>(
        0,
        (sum, obj) => sum + (_objectCredits[obj] ?? 0),
      );

      buffer.writeln(
        '$typeName: ${objects.length} objects, $totalCredits credits',
      );

      // Show top 3 instances with stack traces
      final sortedObjs = objects.toList()
        ..sort(
          (a, b) => (_objectCredits[b] ?? 0).compareTo(_objectCredits[a] ?? 0),
        );

      for (var i = 0; i < sortedObjs.length && i < 3; i++) {
        final obj = sortedObjs[i];
        final credits = _objectCredits[obj] ?? 0;

        // Add useful object info to the output
        String objInfo = '#${obj.hashCode}: $credits credits';
        if (obj is Value) {
          if (obj.isTempKey) {
            objInfo += ' [TEMP]';
          }
          final raw = obj.raw;
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
