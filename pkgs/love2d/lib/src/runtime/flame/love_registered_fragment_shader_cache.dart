// Caches registered Flutter fragment programs for LOVE shader rendering.
//
// The cache keeps compiled fragment programs warm and creates a fresh shader
// instance for each bind. Flutter fragment shaders carry mutable uniform
// slots, so reusing a single shader instance across draws would leak bound
// state between commands.
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../love_runtime.dart';

/// The load state of a registered Flutter fragment asset.
enum LoveRegisteredFragmentShaderLoadState { idle, pending, ready, error }

/// The current cache status for one registered fragment asset.
class LoveRegisteredFragmentShaderStatus<TProgram, TShader> {
  /// Creates a cache status snapshot.
  const LoveRegisteredFragmentShaderStatus({
    required this.assetKey,
    required this.state,
    required this.requestedByLoveShader,
    this.program,
    this.shader,
    this.error,
    this.stackTrace,
  });

  /// The Flutter asset key for this fragment program.
  final String assetKey;

  /// The current cache state for [assetKey].
  final LoveRegisteredFragmentShaderLoadState state;

  /// Whether a LOVE shader has explicitly requested this asset yet.
  final bool requestedByLoveShader;

  /// The cached fragment program, when loading has completed successfully.
  final TProgram? program;

  /// A shader instance associated with this status, when one is available.
  final TShader? shader;

  /// The last load error recorded for this asset.
  final Object? error;

  /// The stack trace captured with [error], if one was available.
  final StackTrace? stackTrace;

  /// Whether this asset has not been queued yet.
  bool get isIdle => state == LoveRegisteredFragmentShaderLoadState.idle;

  /// Whether this asset is currently loading.
  bool get isPending => state == LoveRegisteredFragmentShaderLoadState.pending;

  /// Whether this asset has a compiled program ready for use.
  bool get isReady => state == LoveRegisteredFragmentShaderLoadState.ready;

  /// Whether loading this asset failed.
  bool get hasError => state == LoveRegisteredFragmentShaderLoadState.error;

  /// The filename portion of [assetKey].
  String get shortLabel => assetKey.split('/').last;
}

/// Loads a compiled fragment program for a Flutter asset key.
typedef LoveRegisteredFragmentProgramLoader<TProgram> =
    Future<TProgram> Function(String assetKey);

/// Creates a bindable shader instance from a cached fragment program.
typedef LoveRegisteredFragmentShaderFactory<TProgram, TShader> =
    TShader Function(TProgram program);

/// Schedules background warmup work.
typedef LoveRegisteredFragmentShaderTaskScheduler =
    void Function(VoidCallback callback);

/// Reports a warmup failure for a requested fragment asset.
typedef LoveRegisteredFragmentShaderErrorReporter =
    void Function(String assetKey, Object error, StackTrace? stackTrace);

/// Caches registered Flutter fragment programs used by LOVE shaders.
class LoveRegisteredFragmentShaderCache<TProgram, TShader>
    extends ChangeNotifier {
  /// Creates a fragment shader cache.
  LoveRegisteredFragmentShaderCache({
    required LoveRegisteredFragmentProgramLoader<TProgram> loadProgram,
    required LoveRegisteredFragmentShaderFactory<TProgram, TShader>
    createShader,
    LoveRegisteredFragmentShaderTaskScheduler? scheduleTask,
    LoveRegisteredFragmentShaderErrorReporter? reportError,
    bool Function(String assetKey)? candidateAssetPredicate,
  }) : _loadProgram = loadProgram,
       _createShader = createShader,
       _scheduleTask = scheduleTask ?? _defaultRegisteredFragmentScheduleTask,
       _reportError =
           reportError ?? _defaultRegisteredFragmentShaderErrorReporter,
       _candidateAssetPredicate =
           candidateAssetPredicate ?? _looksLikeRegisteredShaderAssetKey;

  final LoveRegisteredFragmentProgramLoader<TProgram> _loadProgram;
  final LoveRegisteredFragmentShaderFactory<TProgram, TShader> _createShader;
  final LoveRegisteredFragmentShaderTaskScheduler _scheduleTask;
  final LoveRegisteredFragmentShaderErrorReporter _reportError;
  final bool Function(String assetKey) _candidateAssetPredicate;

  final Map<String, TProgram> _programs = <String, TProgram>{};
  final Map<String, Object> _errors = <String, Object>{};
  final Map<String, StackTrace?> _errorStacks = <String, StackTrace?>{};
  final Set<String> _pending = <String>{};
  final Set<String> _requestedByLoveShader = <String>{};
  final Set<String> _queued = <String>{};
  final Set<String> _reportedErrors = <String>{};
  final Queue<String> _warmupQueue = ListQueue<String>();

  Future<void>? _bundleWarmupFuture;
  bool _drainScheduled = false;
  String? _activeAssetKey;

  /// Returns the current cache status for [assetKey].
  LoveRegisteredFragmentShaderStatus<TProgram, TShader> statusForAsset(
    String assetKey,
  ) {
    final program = _programs[assetKey];
    final error = _errors[assetKey];
    final stackTrace = _errorStacks[assetKey];
    final state = switch ((program, error, _pending.contains(assetKey))) {
      (_, final Object _, _) => LoveRegisteredFragmentShaderLoadState.error,
      (final TProgram _, _, _) => LoveRegisteredFragmentShaderLoadState.ready,
      (_, _, true) => LoveRegisteredFragmentShaderLoadState.pending,
      _ => LoveRegisteredFragmentShaderLoadState.idle,
    };
    return LoveRegisteredFragmentShaderStatus<TProgram, TShader>(
      assetKey: assetKey,
      state: state,
      requestedByLoveShader: _requestedByLoveShader.contains(assetKey),
      program: program,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Returns the most actionable status for [assetKeys].
  ///
  /// Errors are preferred over pending work so the caller can surface the
  /// failure immediately.
  LoveRegisteredFragmentShaderStatus<TProgram, TShader>? diagnosticForAssets(
    Iterable<String> assetKeys,
  ) {
    LoveRegisteredFragmentShaderStatus<TProgram, TShader>? pending;
    final seen = <String>{};
    for (final assetKey in assetKeys) {
      if (!seen.add(assetKey)) {
        continue;
      }
      final status = statusForAsset(assetKey);
      if (!status.requestedByLoveShader) {
        continue;
      }
      if (status.hasError) {
        return status;
      }
      pending ??= status.isPending ? status : null;
    }
    return pending;
  }

  /// Returns a diagnostic status for the registered fragments used by
  /// [surface].
  LoveRegisteredFragmentShaderStatus<TProgram, TShader>? diagnosticForSurface(
    LoveGraphicsSurfaceSnapshot surface,
  ) {
    return diagnosticForAssets(
      loveRegisteredFragmentShaderAssetsInSurface(surface),
    );
  }

  /// Marks every registered fragment referenced by [surface] as requested by
  /// LOVE.
  void markSurfaceAssetsRequested(LoveGraphicsSurfaceSnapshot surface) {
    for (final assetKey in loveRegisteredFragmentShaderAssetsInSurface(
      surface,
    )) {
      markAssetRequested(assetKey, prioritize: true);
    }
  }

  /// Marks [assetKey] as requested by a LOVE shader and queues warmup work.
  void markAssetRequested(String assetKey, {bool prioritize = false}) {
    final firstRequest = _requestedByLoveShader.add(assetKey);
    if (_errors.containsKey(assetKey)) {
      _reportAssetErrorIfNeeded(assetKey);
      if (firstRequest) {
        notifyListeners();
      }
      return;
    }

    queueWarmup(assetKey, prioritize: prioritize);
    if (firstRequest) {
      notifyListeners();
    }
  }

  /// Returns a fresh shader instance for [assetKey].
  ///
  /// Returns `null` while the fragment program is still loading or after a load
  /// failure.
  TShader? shaderForAsset(
    String assetKey, {
    bool explicitLoveShaderRequest = true,
  }) {
    if (explicitLoveShaderRequest) {
      markAssetRequested(assetKey, prioritize: true);
    } else {
      queueWarmup(assetKey);
    }

    final program = _programs[assetKey];
    if (program == null) {
      return null;
    }

    return _createShader(program);
  }

  /// Queues every shader-like asset in [bundle] for background warmup.
  Future<void> prewarmShaderAssetsInBundle(AssetBundle bundle) {
    final existingFuture = _bundleWarmupFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final future = _loadBundleShaderManifest(bundle);
    _bundleWarmupFuture = future;
    return future;
  }

  /// Queues [assetKey] for background warmup if it is not already resolved.
  void queueWarmup(String assetKey, {bool prioritize = false}) {
    if (_programs.containsKey(assetKey) ||
        _errors.containsKey(assetKey) ||
        _pending.contains(assetKey)) {
      return;
    }

    if (_queued.add(assetKey)) {
      if (prioritize) {
        _warmupQueue.addFirst(assetKey);
      } else {
        _warmupQueue.addLast(assetKey);
      }
    } else if (prioritize) {
      _warmupQueue.remove(assetKey);
      _warmupQueue.addFirst(assetKey);
    }

    _scheduleQueueDrain();
  }

  Future<void> _loadBundleShaderManifest(AssetBundle bundle) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle);
      final assetKeys = manifest.listAssets()
        ..retainWhere(_candidateAssetPredicate)
        ..sort();
      for (final assetKey in assetKeys) {
        queueWarmup(assetKey);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'love2d',
          context: ErrorDescription(
            'while loading the Flutter asset manifest for registered shader prewarming',
          ),
        ),
      );
    }
  }

  void _scheduleQueueDrain() {
    if (_drainScheduled || _activeAssetKey != null || _warmupQueue.isEmpty) {
      return;
    }

    _drainScheduled = true;
    _scheduleTask(() {
      _drainScheduled = false;
      unawaited(_drainQueue());
    });
  }

  Future<void> _drainQueue() async {
    if (_activeAssetKey != null || _warmupQueue.isEmpty) {
      return;
    }

    final assetKey = _warmupQueue.removeFirst();
    _queued.remove(assetKey);
    _activeAssetKey = assetKey;
    _pending.add(assetKey);
    notifyListeners();

    try {
      final program = await _loadProgram(assetKey);
      _errors.remove(assetKey);
      _errorStacks.remove(assetKey);
      _programs[assetKey] = program;
    } catch (error, stackTrace) {
      _errors[assetKey] = error;
      _errorStacks[assetKey] = stackTrace;
      _programs.remove(assetKey);
      _reportAssetErrorIfNeeded(assetKey);
    } finally {
      _pending.remove(assetKey);
      _activeAssetKey = null;
      notifyListeners();
      _scheduleQueueDrain();
    }
  }

  void _reportAssetErrorIfNeeded(String assetKey) {
    if (!_requestedByLoveShader.contains(assetKey) ||
        _reportedErrors.contains(assetKey)) {
      return;
    }

    final error = _errors[assetKey];
    if (error == null) {
      return;
    }

    _reportedErrors.add(assetKey);
    _reportError(assetKey, error, _errorStacks[assetKey]);
  }
}

/// The default scheduler used for asynchronous fragment-program warmup work.
LoveRegisteredFragmentShaderTaskScheduler
_defaultRegisteredFragmentScheduleTask = (callback) {
  Timer.run(callback);
};

/// Reports registered fragment shader load failures through Flutter errors.
void _defaultRegisteredFragmentShaderErrorReporter(
  String assetKey,
  Object error,
  StackTrace? stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'love2d',
      context: ErrorDescription(
        'while loading the registered Flutter fragment shader "$assetKey"',
      ),
    ),
  );
}

/// Whether [assetKey] looks like a fragment shader source asset path.
bool _looksLikeRegisteredShaderAssetKey(String assetKey) {
  final lower = assetKey.toLowerCase();
  return lower.endsWith('.frag') ||
      lower.endsWith('.glsl') ||
      lower.endsWith('.fsh') ||
      lower.endsWith('.fs');
}

/// Yields the unique registered fragment asset keys referenced by [surface].
Iterable<String> loveRegisteredFragmentShaderAssetsInSurface(
  LoveGraphicsSurfaceSnapshot surface,
) sync* {
  final emitted = <String>{};
  for (final command in surface.commands) {
    final assetKey = command.shader?.flutterFragmentAssetKey;
    if (assetKey != null && emitted.add(assetKey)) {
      yield assetKey;
    }
  }
}

/// The shared registered fragment cache used by the Flame harness renderer.
final LoveRegisteredFragmentShaderCache<ui.FragmentProgram, ui.FragmentShader>
loveFlameRegisteredFragmentShaderCache =
    LoveRegisteredFragmentShaderCache<ui.FragmentProgram, ui.FragmentShader>(
      loadProgram: ui.FragmentProgram.fromAsset,
      createShader: (program) => program.fragmentShader(),
    );
