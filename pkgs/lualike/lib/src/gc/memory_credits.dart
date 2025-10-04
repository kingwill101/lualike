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

  int _total = 0;
  int _young = 0;
  int _old = 0;

  int get totalCredits => _total;
  int get youngCredits => _young;
  int get oldCredits => _old;

  /// Records a freshly allocated object.
  void onAllocate(GCObject obj, {required GCGenerationSpace space}) {
    final credits = obj.estimatedSize;
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
}
