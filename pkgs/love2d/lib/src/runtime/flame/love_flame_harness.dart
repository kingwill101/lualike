import 'dart:async';
import 'dart:convert' show utf8;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lualike/lualike.dart' show EngineMode, LuaError, Value;

import '../filesystem/love_asset_bundle_filesystem.dart';
import '../filesystem/love_flutter_filesystem.dart';
import '../filesystem/love_filesystem_runtime.dart';
import '../input/love_joystick_input_adapter.dart';
import '../love_runtime.dart';
import '../love_script_runtime.dart';
import 'love_flame_harness_renderer.dart';
import 'love_flame_input.dart';
import 'love_flame_live_video_overlay.dart';
import 'love_flame_mouse_cursor_bridge.dart';
import 'love_registered_fragment_shader_cache.dart';
import 'love_flame_text_input_bridge.dart';
import 'love_flame_viewport_geometry.dart';
import 'love_profile_region_support.dart';

const String _loveFlameLiveVideoOverlayKey = 'love-live-video-overlay';
const int _loveProfileMainLoopRegionMilliseconds = int.fromEnvironment(
  'LOVE2D_PROFILE_MAIN_LOOP_MS',
  defaultValue: 5000,
);
const int _loveTraceFrameThresholdMilliseconds = int.fromEnvironment(
  'LOVE2D_TRACE_FRAME_MS',
  defaultValue: 0,
);
final RegExp _loveFlamePrewarmableImageAssetPattern = RegExp(
  r'\.(png|jpg|jpeg|gif|webp|bmp|wbmp)$',
  caseSensitive: false,
);

Future<LoveFilesystemAdapter> resolveLoveFlameHarnessFilesystemAdapter({
  required AssetBundle bundle,
  LoveFilesystemAdapter? filesystemAdapter,
  bool? useFlutterFilesystemFallback,
}) async {
  final shouldUseFlutterFilesystemFallback =
      useFlutterFilesystemFallback ?? !kIsWeb;
  if (!shouldUseFlutterFilesystemFallback) {
    return switch (filesystemAdapter) {
      final LoveAssetBundleFilesystemAdapter assetAdapter => assetAdapter,
      final LoveFilesystemAdapter adapter? => adapter,
      _ => await LoveAssetBundleFilesystemAdapter.load(bundle: bundle),
    };
  }

  final fallbackAdapter = switch (filesystemAdapter) {
    null || LoveAssetBundleFilesystemAdapter() =>
      await LoveFlutterFilesystemAdapter.load(),
    final LoveFilesystemAdapter adapter => adapter,
  };

  return switch (filesystemAdapter) {
    final LoveAssetBundleFilesystemAdapter assetAdapter
        when assetAdapter.hasExplicitFallback =>
      assetAdapter,
    final LoveAssetBundleFilesystemAdapter assetAdapter =>
      assetAdapter.withFallback(fallbackAdapter),
    _ => await LoveAssetBundleFilesystemAdapter.load(
      bundle: bundle,
      fallback: fallbackAdapter,
    ),
  };
}

/// A Flutter widget that boots and presents a LOVE entry point through Flame.
class LoveFlameHarness extends StatefulWidget {
  /// Creates a Flame-backed LOVE harness widget.
  const LoveFlameHarness({
    super.key,
    required this.entryAsset,
    this.title,
    this.bundle,
    this.filesystemAdapter,
    this.audioBackendFactory,
    this.videoFrameProviderFactory,
    this.onInputAdaptersReady,
    this.onQuitRequested,
    this.engineMode = EngineMode.luaBytecode,
    this.automaticGc = false,
    this.imageWarmupAssetKeys,
    this.debugImageWarmupOverride,
    this.debugOnGameCreated,
  });

  /// The mounted LOVE entry asset, typically `main.lua`.
  final String entryAsset;

  /// The overlay title shown above the rendered viewport.
  final String? title;

  /// The asset bundle used to load the LOVE source tree.
  final AssetBundle? bundle;

  /// The filesystem adapter exposed to the runtime.
  final LoveFilesystemAdapter? filesystemAdapter;

  /// A factory used to create audio backends for runtime sources.
  final LoveAudioBackendFactory? audioBackendFactory;

  /// A factory used to snapshot video frames for `love.graphics.newVideo`.
  final LoveVideoFrameProviderFactory? videoFrameProviderFactory;

  /// Called after the keyboard/mouse and joystick adapters are ready.
  final FutureOr<void> Function(
    LoveFlameInputAdapter input,
    LoveJoystickInputAdapter joystickInput,
  )?
  onInputAdaptersReady;

  /// Called when the LOVE runtime requests shutdown.
  final Future<void> Function()? onQuitRequested;

  /// The LuaLike engine used by the Flame-hosted LOVE runtime.
  final EngineMode engineMode;

  /// Whether Lualike's automatic GC safe points are enabled.
  ///
  /// Defaults to false so frame-time profiling can isolate interpreter and
  /// rendering costs without GC pauses.
  final bool automaticGc;

  /// Bundled image assets to prewarm before marking the harness ready.
  ///
  /// When omitted, the harness prewarms image assets under the LOVE source
  /// directory. Large games can pass the startup-critical image set here and
  /// let secondary images load lazily.
  final Iterable<String>? imageWarmupAssetKeys;

  /// Testing hook that replaces bundled startup image warmup.
  final Future<void> Function(
    LoveFlameHarnessGame game,
    LoveFilesystemState filesystem,
  )?
  debugImageWarmupOverride;

  /// Testing and benchmark hook that exposes the created Flame game instance.
  final void Function(LoveFlameHarnessGame game)? debugOnGameCreated;

  @override
  State<LoveFlameHarness> createState() => _LoveFlameHarnessState();
}

class _LoveFlameHarnessState extends State<LoveFlameHarness>
    with WidgetsBindingObserver {
  AssetBundle get _bundle => widget.bundle ?? rootBundle;

  late final LoveFlameHarnessGame _game = LoveFlameHarnessGame(
    assetBundle: _bundle,
    audioBackendFactory: widget.audioBackendFactory,
    videoFrameProviderFactory: widget.videoFrameProviderFactory,
  );
  late final _LoveFlameHarnessController _controller =
      _LoveFlameHarnessController(
        game: _game,
        entryAsset: widget.entryAsset,
        bundle: _bundle,
        filesystemAdapter: widget.filesystemAdapter,
        onQuitRequested: widget.onQuitRequested ?? _defaultQuitRequested,
        engineMode: widget.engineMode,
        automaticGc: widget.automaticGc,
        imageWarmupAssetKeys: widget.imageWarmupAssetKeys,
        debugImageWarmupOverride: widget.debugImageWarmupOverride,
      );

  Future<void> _defaultQuitRequested() async {
    try {
      await SystemNavigator.pop();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game.onTick = _controller.onFrame;
    _game.onKeyEventHandler = (event, _) =>
        _controller.input.handleKeyEvent(event);
    widget.debugOnGameCreated?.call(_game);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null) {
      _controller.handleAppLifecycleState(lifecycleState);
    }
    unawaited(_initializeController());
  }

  Future<void> _initializeController() async {
    final onInputAdaptersReady = widget.onInputAdaptersReady;
    if (onInputAdaptersReady != null) {
      await onInputAdaptersReady(_controller.input, _controller.joystickInput);
    }
    await _controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleAppLifecycleState(state);
  }

  @override
  void didHaveMemoryPressure() {
    _controller.reportLowMemoryPressure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.onTick = null;
    _game.onKeyEventHandler = null;
    _controller.dispose();
    _game.disposePresentationNotifier();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final listenable = Listenable.merge(<Listenable>[
      _controller,
      loveFlameRegisteredFragmentShaderCache,
    ]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final activeShaderDiagnostic = loveFlameRegisteredFragmentShaderCache
            .diagnosticForSurface(_game.presentedFrame);
        return ColoredBox(
          color: const Color(0xFF050816),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _LoveHarnessViewport(
                  game: _game,
                  controller: _controller,
                  onViewportSizeChanged: _controller.reportViewportSize,
                ),
                if (title != null && title.isNotEmpty)
                  Positioned(
                    left: 16,
                    top: 16,
                    child: _HarnessBadge(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: _HarnessBadge(
                    child: Text(
                      _controller.statusLabel,
                      key: const Key('status-label'),
                    ),
                  ),
                ),
                if (_controller.errorMessage case final error?)
                  if (!_controller.hasRuntimeErrorLoop)
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC111827),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              error,
                              key: const Key('error-message'),
                              style: const TextStyle(
                                color: Color(0xFFFCA5A5),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                if (!_controller.isReady && _controller.errorMessage == null)
                  Center(
                    child: _HarnessBadge(
                      child: Text(_controller.loadingMessage),
                    ),
                  ),
                if (activeShaderDiagnostic != null)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: _HarnessBadge(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Text(
                          _registeredShaderDiagnosticLabel(
                            activeShaderDiagnostic,
                          ),
                          key: const Key('shader-diagnostic-label'),
                        ),
                      ),
                    ),
                  ),
                // const Positioned(
                //   left: 16,
                //   bottom: 16,
                //   child: _HarnessBadge(
                //     child: Text(
                //       'Click to focus. Keyboard and mouse map to LOVE callbacks.',
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoveFlameHarnessController extends ChangeNotifier {
  _LoveFlameHarnessController({
    required this.game,
    required this.entryAsset,
    required this.bundle,
    this.filesystemAdapter,
    required this.onQuitRequested,
    required this.engineMode,
    required this.automaticGc,
    this.imageWarmupAssetKeys,
    this.debugImageWarmupOverride,
  });

  final LoveFlameHarnessGame game;
  final String entryAsset;
  final AssetBundle bundle;
  final LoveFilesystemAdapter? filesystemAdapter;
  final Future<void> Function() onQuitRequested;
  final EngineMode engineMode;
  final bool automaticGc;
  final Iterable<String>? imageWarmupAssetKeys;
  final Future<void> Function(
    LoveFlameHarnessGame game,
    LoveFilesystemState filesystem,
  )?
  debugImageWarmupOverride;

  late final LoveJoystickInputAdapter joystickInput = LoveJoystickInputAdapter(
    host: game.host,
    runtimeProvider: () => _runtime,
    onError: (error, stackTrace) => _recordError(
      error,
      phase: 'while dispatching LOVE joystick callbacks',
      stackTrace: stackTrace,
    ),
  );
  late final LoveFlameInputAdapter input = LoveFlameInputAdapter(
    host: game.host,
    runtimeProvider: () => _runtime,
    viewportSizeProvider: () => _viewportSize,
    cameraProvider: () => game.camera,
    joystickInput: joystickInput,
    onError: (error, stackTrace) => _recordError(
      error,
      phase: 'while dispatching LOVE input callbacks',
      stackTrace: stackTrace,
    ),
  );

  LoveScriptRuntime? _runtime;
  bool _disposed = false;
  bool _initialized = false;
  bool _startupWarmupPending = false;
  bool _updateInFlight = false;
  bool _quitRequested = false;
  bool _restartRequested = false;
  Value? _errorLoop;
  String? _errorMessage;
  Size? _viewportSize;
  Size? _lastDispatchedViewportSize;
  bool _visible = true;
  bool? _pendingVisibleState;
  bool? _lastDispatchedVisibleState;
  bool _lowMemoryPending = false;
  bool _profileRegionsDisabled = false;
  bool _mainLoopProfileCompleted = false;
  Duration _mainLoopProfileElapsed = Duration.zero;
  Stopwatch? _mainLoopProfileStopwatch;
  LoveProfileRegionHandle? _mainLoopProfileRegion;
  int _frameTraceIndex = 0;

  bool get isReady => _initialized;
  String? get errorMessage => _errorMessage;
  bool get hasRuntimeErrorLoop => _errorLoop != null;
  String get loadingMessage => _startupWarmupPending
      ? 'Prewarming LOVE assets...'
      : 'Loading LOVE runtime...';

  String get statusLabel {
    if (_errorMessage != null) {
      return 'Error';
    }
    if (_quitRequested) {
      return 'Quit';
    }
    if (_startupWarmupPending) {
      return 'Prewarming';
    }
    if (!_initialized) {
      return 'Loading';
    }
    return 'Running';
  }

  Future<T> _runProfileRegion<T>(
    String name,
    Future<T> Function() body, {
    Map<String, String> attributes = const <String, String>{},
  }) async {
    if (_profileRegionsDisabled) {
      return body();
    }

    LoveProfileRegionHandle region;
    try {
      region = await startLoveProfileRegion(name, attributes: attributes);
    } on LoveProfileRegionConfigurationException {
      _profileRegionsDisabled = true;
      return body();
    }

    try {
      return await body();
    } finally {
      try {
        await region.stop();
      } on LoveProfileRegionConfigurationException {
        _profileRegionsDisabled = true;
      }
    }
  }

  Future<void> _startMainLoopProfileRegionIfNeeded() async {
    if (_profileRegionsDisabled ||
        _mainLoopProfileCompleted ||
        _mainLoopProfileRegion != null ||
        _loveProfileMainLoopRegionMilliseconds <= 0) {
      return;
    }

    try {
      _mainLoopProfileRegion = await startLoveProfileRegion(
        'love2d-main-loop',
        attributes: <String, String>{
          'entryAsset': entryAsset,
          'phase': 'frame-loop',
          'durationMs': _loveProfileMainLoopRegionMilliseconds.toString(),
        },
      );
      _mainLoopProfileStopwatch = Stopwatch()..start();
    } on LoveProfileRegionConfigurationException {
      _profileRegionsDisabled = true;
    }
  }

  Future<void> _advanceMainLoopProfileRegion() async {
    final region = _mainLoopProfileRegion;
    if (region == null || _mainLoopProfileCompleted) {
      return;
    }

    _mainLoopProfileElapsed =
        _mainLoopProfileStopwatch?.elapsed ?? _mainLoopProfileElapsed;
    if (_mainLoopProfileElapsed.inMilliseconds <
        _loveProfileMainLoopRegionMilliseconds) {
      return;
    }

    _mainLoopProfileRegion = null;
    _mainLoopProfileStopwatch?.stop();
    _mainLoopProfileStopwatch = null;
    _mainLoopProfileCompleted = true;
    try {
      await region.stop();
    } on LoveProfileRegionConfigurationException {
      _profileRegionsDisabled = true;
    }
  }

  void _discardMainLoopProfileRegion() {
    final region = _mainLoopProfileRegion;
    _mainLoopProfileRegion = null;
    _mainLoopProfileStopwatch?.stop();
    _mainLoopProfileStopwatch = null;
    if (region != null) {
      unawaited(_stopDiscardedMainLoopProfileRegion(region));
    }
  }

  Future<void> _stopDiscardedMainLoopProfileRegion(
    LoveProfileRegionHandle region,
  ) async {
    try {
      await region.stop();
    } on LoveProfileRegionConfigurationException {
      _profileRegionsDisabled = true;
    }
  }

  Future<void> initialize() {
    return _runProfileRegion(
      'love2d-startup',
      _initialize,
      attributes: <String, String>{
        'entryAsset': entryAsset,
        'phase': 'startup',
      },
    );
  }

  Future<void> _initialize() async {
    _discardMainLoopProfileRegion();
    _initialized = false;
    _startupWarmupPending = false;
    _updateInFlight = false;
    _quitRequested = false;
    _restartRequested = false;
    _errorLoop = null;
    _errorMessage = null;
    _runtime = null;
    _lastDispatchedVisibleState = null;
    _mainLoopProfileCompleted = false;
    _mainLoopProfileElapsed = Duration.zero;
    _mainLoopProfileStopwatch = null;
    notifyListeners();

    LoveScriptRuntime? runtimeForError;
    try {
      unawaited(
        loveFlameRegisteredFragmentShaderCache.prewarmShaderAssetsInBundle(
          bundle,
        ),
      );
      final adapter = await resolveLoveFlameHarnessFilesystemAdapter(
        bundle: bundle,
        filesystemAdapter: filesystemAdapter,
      );
      final runtime = LoveScriptRuntime(
        host: game.host,
        filesystemAdapter: adapter,
        engineMode: engineMode,
        automaticGc: automaticGc,
      );
      runtimeForError = runtime;
      final filesystem = LoveFilesystemState.of(runtime.runtime);
      if (!filesystem.setSource(entryAsset)) {
        throw StateError('Failed to mount LOVE source asset "$entryAsset".');
      }

      if (_viewportSize case final viewportSize?) {
        _syncHostMetrics(viewportSize);
        _lastDispatchedViewportSize = viewportSize;
      }

      await runtime.loadConfIfPresent();

      final logicalEntryAsset = entryAsset.split(RegExp(r'[\\/]')).last;
      final entryData = await filesystem.readFileData(
        logicalEntryAsset,
        filename: entryAsset,
      );
      if (entryData == null) {
        throw StateError('Failed to load LOVE entry asset "$entryAsset".');
      }

      await runtime.execute(
        utf8.decode(entryData.bytes),
        scriptPath: entryData.filename,
      );
      await runtime.callLoadIfDefined();
      await _flushPendingRuntimeSignals(runtime);
      if (await _handleMainLoopExitStatus(
        await runtime.processMainLoopEvents(),
      )) {
        await _restartIfRequested();
        return;
      }
      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();
      await _commitPresentedFrame(runtime);
      await _awaitStartupWarmups(
        imageWarmup: _startupImageWarmup(filesystem),
        surfaceSnapshot: game.presentedFrame,
      );
      if (await _restartIfRequested()) {
        return;
      }

      _runtime = runtime;
      _initialized = true;
      if (!_disposed) {
        notifyListeners();
      }
    } catch (error, stackTrace) {
      _recordError(
        error,
        phase: 'while initializing the LOVE harness',
        runtimeOverride: runtimeForError,
        stackTrace: stackTrace,
      );
    }
  }

  void onFrame(double dt) {
    final hasErrorLoop = _errorLoop != null;
    if ((!_initialized && !hasErrorLoop) ||
        _updateInFlight ||
        _runtime == null ||
        _quitRequested ||
        (_errorMessage != null && !hasErrorLoop)) {
      return;
    }

    _updateInFlight = true;
    if (hasErrorLoop) {
      unawaited(_runErrorFrame());
      return;
    }

    unawaited(_runFrame(dt));
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    final visible = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
      AppLifecycleState.inactive => null,
    };
    if (visible == null || _visible == visible) {
      return;
    }

    _visible = visible;
    game.host.windowMetrics = game.host.windowMetrics.copyWith(
      visible: visible,
    );
    input.handleVisibilityChanged(visible);
    _pendingVisibleState = visible;
    _dispatchPendingRuntimeSignalsIfIdle();
  }

  void reportLowMemoryPressure() {
    _lowMemoryPending = true;
    _dispatchPendingRuntimeSignalsIfIdle();
  }

  void reportViewportSize(Size size) {
    if (size.width <= 0 || size.height <= 0 || _viewportSize == size) {
      return;
    }

    _viewportSize = size;
    _syncHostMetrics(size);
    if (_initialized && _lastDispatchedViewportSize == null) {
      _lastDispatchedViewportSize = size;
    }
    if (!_initialized ||
        _updateInFlight ||
        _runtime == null ||
        _errorMessage != null) {
      return;
    }

    _updateInFlight = true;
    unawaited(_redrawForViewportResize());
  }

  Future<void> _runFrame(double dt) async {
    final frameTraceStopwatch = _loveTraceFrameThresholdMilliseconds > 0
        ? (Stopwatch()..start())
        : null;
    final frameTracePhases = frameTraceStopwatch == null
        ? null
        : <String, int>{};

    Future<T> tracePhase<T>(String name, Future<T> Function() body) async {
      if (frameTraceStopwatch == null || frameTracePhases == null) {
        return body();
      }

      final phaseStopwatch = Stopwatch()..start();
      try {
        return await body();
      } finally {
        phaseStopwatch.stop();
        frameTracePhases[name] = phaseStopwatch.elapsedMicroseconds;
      }
    }

    try {
      await tracePhase('resize', _dispatchResizeIfNeeded);
      final runtime = _runtime;
      if (runtime == null) {
        return;
      }

      await tracePhase('profileStart', _startMainLoopProfileRegionIfNeeded);
      await tracePhase('signals', () => _flushPendingRuntimeSignals(runtime));
      final exitAfterEvents = await tracePhase(
        'events',
        runtime.processMainLoopEvents,
      );
      if (await tracePhase(
        'exitEvents',
        () => _handleMainLoopExitStatus(exitAfterEvents),
      )) {
        await _restartIfRequested();
        return;
      }
      final steppedDt = runtime.context.stepExternal(dt);
      if (steppedDt > 0) {
        await tracePhase(
          'update',
          () => runtime.callUpdateIfDefined(steppedDt),
        );
      }
      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await tracePhase('draw', runtime.callDrawIfDefined);
      await tracePhase('commit', () => _commitPresentedFrame(runtime));
      if (await tracePhase('restart', _restartIfRequested)) {
        return;
      }
    } catch (error, stackTrace) {
      _recordError(
        error,
        phase: 'while running love.update/love.draw',
        stackTrace: stackTrace,
      );
    } finally {
      await tracePhase('profileAdvance', _advanceMainLoopProfileRegion);
      frameTraceStopwatch?.stop();
      if (frameTraceStopwatch != null &&
          frameTracePhases != null &&
          frameTraceStopwatch.elapsedMilliseconds >=
              _loveTraceFrameThresholdMilliseconds) {
        _frameTraceIndex += 1;
        final phases = frameTracePhases.entries
            .map(
              (entry) =>
                  '${entry.key}=${(entry.value / 1000).toStringAsFixed(2)}ms',
            )
            .join(' ');
        debugPrint(
          'love2d-frame-trace '
          'frame=$_frameTraceIndex '
          'dtMs=${(dt * 1000).toStringAsFixed(2)} '
          'totalMs=${frameTraceStopwatch.elapsedMicroseconds / 1000} '
          '$phases',
        );
      }
      _updateInFlight = false;
    }
  }

  Future<void> _redrawForViewportResize() async {
    try {
      await _dispatchResizeIfNeeded();
      final runtime = _runtime;
      if (runtime == null) {
        return;
      }

      await _flushPendingRuntimeSignals(runtime);
      if (await _handleMainLoopExitStatus(
        await runtime.processMainLoopEvents(),
      )) {
        await _restartIfRequested();
        return;
      }
      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      await runtime.callDrawIfDefined();
      await _commitPresentedFrame(runtime);
      if (await _restartIfRequested()) {
        return;
      }
    } catch (error, stackTrace) {
      _recordError(
        error,
        phase: 'while redrawing after a viewport resize',
        stackTrace: stackTrace,
      );
    } finally {
      _updateInFlight = false;
    }
  }

  Future<void> _awaitStartupWarmups({
    required Future<void> imageWarmup,
    required LoveGraphicsSurfaceSnapshot surfaceSnapshot,
  }) async {
    if (!_startupWarmupPending) {
      _startupWarmupPending = true;
      if (!_disposed) {
        notifyListeners();
      }
    }

    try {
      await imageWarmup;
      await game.images.ready();
      await loveFlameRegisteredFragmentShaderCache.readyForAssets(
        loveRegisteredFragmentShaderAssetsInSurface(surfaceSnapshot),
      );
    } finally {
      if (_startupWarmupPending) {
        _startupWarmupPending = false;
        if (!_disposed) {
          notifyListeners();
        }
      }
    }
  }

  Future<void> _prewarmBundleSourceImages(
    LoveFilesystemState filesystem,
  ) async {
    final assetAdapter = switch (filesystem.adapter) {
      final LoveAssetBundleFilesystemAdapter adapter => adapter,
      _ => null,
    };
    if (assetAdapter == null) {
      return;
    }

    final sourceBaseDirectory = filesystem.getSourceBaseDirectory();
    if (sourceBaseDirectory.isEmpty) {
      return;
    }

    final assetKeys = assetAdapter
        .assetKeysUnder(sourceBaseDirectory)
        .where(_loveFlamePrewarmableImageAssetPattern.hasMatch)
        .toList(growable: false);
    if (assetKeys.isEmpty) {
      return;
    }

    await _prewarmBundledImageAssets(assetKeys);
  }

  Future<void> _startupImageWarmup(LoveFilesystemState filesystem) {
    final debugOverride = debugImageWarmupOverride;
    if (debugOverride != null) {
      return debugOverride(game, filesystem);
    }

    final explicitAssetKeys = imageWarmupAssetKeys;
    if (explicitAssetKeys != null) {
      return _prewarmBundledImageAssets(explicitAssetKeys);
    }

    return _prewarmBundleSourceImages(filesystem);
  }

  Future<void> _prewarmBundledImageAssets(Iterable<String> assetKeys) async {
    final keys = assetKeys.toList(growable: false);
    if (keys.isEmpty) {
      return;
    }

    const workerLimit = 8;
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex;
        if (index >= keys.length) {
          return;
        }
        nextIndex = index + 1;
        await _prewarmBundledImageAsset(keys[index]);
      }
    }

    final workerCount = keys.length < workerLimit ? keys.length : workerLimit;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
      eagerError: false,
    );
  }

  Future<void> _prewarmBundledImageAsset(String assetKey) async {
    try {
      await game.host.prewarmImageAsset(assetKey);
    } catch (error, stackTrace) {
      game.images.clear(assetKey);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'love2d',
          context: ErrorDescription(
            'while prewarming the bundled LOVE image asset "$assetKey"',
          ),
          informationCollector: () sync* {
            yield ErrorDescription('Entry asset: $entryAsset');
          },
        ),
      );
    }
  }

  Future<void> _runErrorFrame() async {
    try {
      final runtime = _runtime;
      final errorLoop = _errorLoop;
      if (runtime == null || errorLoop == null) {
        return;
      }

      await _flushPendingRuntimeSignals(runtime);
      runtime.context.beginDrawFrame();
      runtime.context.graphics.origin();
      final result = await runtime.callErrorHandlerLoop(errorLoop);
      await _commitPresentedFrame(runtime);
      if (result != null) {
        _errorLoop = null;
        _errorMessage = null;
        _quitRequested = true;
        if (!_disposed) {
          notifyListeners();
        }
        await onQuitRequested();
      }
    } catch (error, stackTrace) {
      _errorLoop = null;
      _recordError(
        error,
        phase: 'while running love.errorhandler',
        stackTrace: stackTrace,
        invokeErrorHandler: false,
      );
    } finally {
      _updateInFlight = false;
    }
  }

  Future<void> _commitPresentedFrame(LoveScriptRuntime runtime) async {
    final snapshot = runtime.context.graphics.snapshotScreenSurface();
    game.presentFrame(snapshot);
    loveFlameRegisteredFragmentShaderCache.markSurfaceAssetsRequested(snapshot);
    await runtime.context.graphics.dispatchPendingScreenshots(
      snapshot: snapshot,
      pixelWidth:
          (runtime.context.windowMetrics.width *
                  runtime.context.windowMetrics.dpiScale)
              .round(),
      pixelHeight:
          (runtime.context.windowMetrics.height *
                  runtime.context.windowMetrics.dpiScale)
              .round(),
    );
  }

  Future<void> _dispatchResizeIfNeeded() async {
    final runtime = _runtime;
    final currentSize = _viewportSize;
    if (runtime == null || currentSize == null) {
      return;
    }

    final previousSize = _lastDispatchedViewportSize;
    _lastDispatchedViewportSize = currentSize;
    if (previousSize == null || previousSize == currentSize) {
      return;
    }

    await runtime.queueResize(
      currentSize.width.round(),
      currentSize.height.round(),
    );
  }

  void _dispatchPendingRuntimeSignalsIfIdle() {
    if (!_initialized ||
        _updateInFlight ||
        _runtime == null ||
        _quitRequested ||
        _errorMessage != null) {
      return;
    }

    _updateInFlight = true;
    unawaited(_dispatchPendingRuntimeSignals());
  }

  Future<void> _dispatchPendingRuntimeSignals() async {
    try {
      final runtime = _runtime;
      if (runtime == null) {
        return;
      }

      await _flushPendingRuntimeSignals(runtime);
      await _handleMainLoopExitStatus(await runtime.processMainLoopEvents());
      if (await _restartIfRequested()) {
        return;
      }
    } catch (error, stackTrace) {
      _recordError(
        error,
        phase: 'while dispatching LOVE lifecycle callbacks',
        stackTrace: stackTrace,
      );
    } finally {
      _updateInFlight = false;
    }
  }

  Future<void> _flushPendingRuntimeSignals(LoveScriptRuntime runtime) async {
    await input.flush();
    await joystickInput.flush();
    while (true) {
      final visible = _pendingVisibleState;
      if (visible != null) {
        _pendingVisibleState = null;
        if (_lastDispatchedVisibleState != visible) {
          _lastDispatchedVisibleState = visible;
          await runtime.queueVisible(visible);
        }
        continue;
      }

      if (_lowMemoryPending) {
        _lowMemoryPending = false;
        await runtime.queueLowMemory();
        continue;
      }

      break;
    }
  }

  Future<bool> _handleMainLoopExitStatus(Object? status) async {
    if (status == null || _quitRequested) {
      return false;
    }
    if (status == 'restart') {
      _restartRequested = true;
      return true;
    }

    _quitRequested = true;
    if (!_disposed) {
      notifyListeners();
    }
    await onQuitRequested();
    return true;
  }

  Future<bool> _restartIfRequested() async {
    if (!_restartRequested || _disposed) {
      return false;
    }

    _restartRequested = false;
    await initialize();
    return true;
  }

  void _syncHostMetrics(Size size) {
    game.host.updateHostViewportSize(size);
  }

  void _recordError(
    Object error, {
    StackTrace? stackTrace,
    String phase = 'while executing LOVE callbacks',
    LoveScriptRuntime? runtimeOverride,
    bool invokeErrorHandler = true,
  }) {
    var nextMessage = error.toString();
    final previousMessage = _errorMessage;
    final runtime = runtimeOverride ?? _runtime;
    if (runtime != null) {
      final luaError = error is LuaError ? error : null;
      try {
        runtime.runtime.reportError(
          luaError?.message ?? nextMessage,
          trace: stackTrace ?? luaError?.stackTrace,
          error: error,
          node: luaError?.node,
        );
        nextMessage = luaError?.formatError() ?? error.toString();
      } catch (_) {
        _reportFallbackError(error, stackTrace, phase);
      }
    } else {
      _reportFallbackError(error, stackTrace, phase);
    }

    if (previousMessage == nextMessage) {
      return;
    }

    _errorLoop = null;
    _errorMessage = nextMessage;
    if (runtime != null && invokeErrorHandler) {
      unawaited(_activateRuntimeErrorHandler(runtime, nextMessage));
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _activateRuntimeErrorHandler(
    LoveScriptRuntime runtime,
    String message,
  ) async {
    try {
      final loop = await runtime.createErrorHandlerLoop(message);
      if (loop == null || _disposed || _errorMessage != message) {
        return;
      }

      _runtime = runtime;
      _errorLoop = loop;
      if (!_disposed) {
        notifyListeners();
      }
    } catch (error, stackTrace) {
      _errorLoop = null;
      _reportFallbackError(
        error,
        stackTrace,
        'while activating love.errorhandler',
      );
    }
  }

  void _reportFallbackError(
    Object error,
    StackTrace? stackTrace,
    String phase,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'love2d',
        context: ErrorDescription(phase),
        informationCollector: () sync* {
          yield ErrorDescription('Entry asset: $entryAsset');
        },
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _discardMainLoopProfileRegion();
    super.dispose();
  }
}

String _registeredShaderDiagnosticLabel<TProgram, TShader>(
  LoveRegisteredFragmentShaderStatus<TProgram, TShader> status,
) {
  final label = status.shortLabel;
  return switch (status.state) {
    LoveRegisteredFragmentShaderLoadState.pending => 'Compiling shader: $label',
    LoveRegisteredFragmentShaderLoadState.error =>
      'Shader failed: $label\n${status.error}',
    _ => label,
  };
}

class _LoveHarnessViewport extends StatefulWidget {
  const _LoveHarnessViewport({
    required this.game,
    required this.controller,
    required this.onViewportSizeChanged,
  });

  final LoveFlameHarnessGame game;
  final _LoveFlameHarnessController controller;
  final ValueChanged<Size> onViewportSizeChanged;

  @override
  State<_LoveHarnessViewport> createState() => _LoveHarnessViewportState();
}

class _LoveHarnessViewportState extends State<_LoveHarnessViewport> {
  late final FocusNode _focusNode = FocusNode(debugLabel: 'love-harness');
  late final LoveFlameMouseCursorBridge _mouseCursorBridge =
      LoveFlameMouseCursorBridge(mouse: widget.controller.game.host.mouse);
  late final LoveFlameTextInputBridge _textInputBridge =
      LoveFlameTextInputBridge(
        focusNode: _focusNode,
        keyboard: widget.controller.game.host.keyboard,
        input: widget.controller.input,
        contextProvider: () => context,
      );
  late MouseCursor _mouseCursor = _mouseCursorBridge.sync();
  LoveMouseCursor? _imageCursor;
  String? _systemCursorType;
  double _imageCursorX = 0;
  double _imageCursorY = 0;
  bool _textInputSyncScheduled = false;
  bool _cursorSyncScheduled = false;

  LoveMouseState get _mouseState => widget.controller.game.host.mouse;
  LoveKeyboardState get _keyboardState => widget.controller.game.host.keyboard;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusNodeChanged);
    _mouseState.addListener(_handleMouseStateChanged);
    _keyboardState.addListener(_handleKeyboardStateChanged);
    _scheduleViewportSync(syncTextInput: true, syncCursor: true);
  }

  @override
  void didUpdateWidget(covariant _LoveHarnessViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMouse = oldWidget.controller.game.host.mouse;
    final oldKeyboard = oldWidget.controller.game.host.keyboard;
    if (!identical(oldMouse, _mouseState)) {
      oldMouse.removeListener(_handleMouseStateChanged);
      _mouseState.addListener(_handleMouseStateChanged);
    }
    if (!identical(oldKeyboard, _keyboardState)) {
      oldKeyboard.removeListener(_handleKeyboardStateChanged);
      _keyboardState.addListener(_handleKeyboardStateChanged);
    }
    _syncCursorState(markNeedsBuild: false);
    _scheduleViewportSync(syncTextInput: true, syncCursor: true);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusNodeChanged);
    _mouseState.removeListener(_handleMouseStateChanged);
    _keyboardState.removeListener(_handleKeyboardStateChanged);
    _textInputBridge.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _mouseCursor,
      onEnter: widget.controller.input.handlePointerEnter,
      onExit: widget.controller.input.handlePointerExit,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _focusNode.requestFocus();
          widget.controller.input.handlePointerDown(event);
        },
        onPointerMove: widget.controller.input.handlePointerMove,
        onPointerHover: widget.controller.input.handlePointerHover,
        onPointerUp: widget.controller.input.handlePointerUp,
        onPointerCancel: widget.controller.input.handlePointerCancel,
        onPointerSignal: widget.controller.input.handlePointerSignal,
        child: _ViewportSizeReporter(
          onSizeChanged: _handleViewportSizeChanged,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : (widget.controller.game.host.windowMetrics.width
                        .toDouble());
              final height = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : (widget.controller.game.host.windowMetrics.height
                        .toDouble());
              final viewportSize = Size(width, height);
              final presentation = loveFlamePresentationGeometry(
                windowMetrics: widget.controller.game.host.windowMetrics,
                viewportSize: viewportSize,
              );
              return DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF050816), Color(0xFF101827)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _LoveHarnessBackdropPainter(
                            presentation: presentation,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GameWidget<LoveFlameHarnessGame>(
                        game: widget.game,
                        focusNode: _focusNode,
                        autofocus: true,
                        overlayBuilderMap: {
                          _loveFlameLiveVideoOverlayKey: (context, game) {
                            return LoveFlameLiveVideoOverlay(
                              presentedFrameListenable:
                                  game.presentedFrameListenable,
                              windowMetricsProvider: () =>
                                  game.host.windowMetrics,
                              cameraProvider: () => game.camera,
                            );
                          },
                        },
                        initialActiveOverlays: const <String>[
                          _loveFlameLiveVideoOverlayKey,
                        ],
                      ),
                    ),
                    if (_imageCursor case final imageCursor?)
                      Positioned(
                        key: const Key('love-image-cursor'),
                        left: _imageCursorX - imageCursor.hotspotX,
                        top: _imageCursorY - imageCursor.hotspotY,
                        child: IgnorePointer(
                          child: _LoveImageCursorOverlay(cursor: imageCursor),
                        ),
                      ),
                    if (_systemCursorType case final systemCursorType?)
                      Positioned(
                        key: const Key('love-system-cursor'),
                        left:
                            _imageCursorX -
                            _loveSystemCursorOverlayForType(
                              systemCursorType,
                            ).hotspotX,
                        top:
                            _imageCursorY -
                            _loveSystemCursorOverlayForType(
                              systemCursorType,
                            ).hotspotY,
                        child: IgnorePointer(
                          child: _LoveSystemCursorOverlay(
                            type: systemCursorType,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleFocusNodeChanged() {
    widget.controller.input.handleFocusChanged(_focusNode.hasFocus);
    _scheduleViewportSync(syncTextInput: true, syncCursor: true);
  }

  void _handleKeyboardStateChanged() {
    _scheduleTextInputSync();
  }

  void _handleMouseStateChanged() {
    if (_canSyncCursorImmediately) {
      _syncCursorState();
      return;
    }

    _scheduleCursorSync();
  }

  bool get _canSyncCursorImmediately =>
      mounted &&
      WidgetsBinding.instance.schedulerPhase !=
          SchedulerPhase.persistentCallbacks;

  void _handleViewportSizeChanged(Size size) {
    widget.onViewportSizeChanged(size);
    _scheduleViewportSync(syncTextInput: true, syncCursor: true);
  }

  void _scheduleViewportSync({
    bool syncTextInput = false,
    bool syncCursor = false,
  }) {
    if (syncTextInput) {
      _scheduleTextInputSync();
    }
    if (syncCursor) {
      _scheduleCursorSync();
    }
  }

  void _scheduleTextInputSync() {
    if (_textInputSyncScheduled) {
      return;
    }

    _textInputSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textInputSyncScheduled = false;
      if (!mounted) {
        return;
      }

      _textInputBridge.sync();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _scheduleCursorSync() {
    if (_cursorSyncScheduled) {
      return;
    }

    _cursorSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cursorSyncScheduled = false;
      if (!mounted) {
        return;
      }

      _syncCursorState();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _syncCursorState({bool markNeedsBuild = true}) {
    final cursor = _mouseCursorBridge.sync();
    final mouse = widget.controller.game.host.mouse;
    final renderObject = context.findRenderObject();
    final viewportSize = switch (renderObject) {
      final RenderBox box when box.hasSize => box.size,
      _ => null,
    };
    final viewportCursorPosition = switch (viewportSize) {
      null => Offset(mouse.x, mouse.y),
      final size => loveFlamePresentationGeometry(
        windowMetrics: widget.controller.game.host.windowMetrics,
        viewportSize: size,
        camera: widget.game.camera,
      ).logicalToViewportPoint(Offset(mouse.x, mouse.y)),
    };
    final cursorValue = mouse.cursor;
    final overlayActive =
        mouse.visible &&
        (mouse.programmaticPositionActive ||
            (cursorValue != null &&
                !cursorValue.isSystemCursor &&
                cursorValue.imageData != null));
    final imageCursor = switch (cursorValue) {
      final LoveMouseCursor cursor
          when overlayActive &&
              !cursor.isSystemCursor &&
              cursor.imageData != null =>
        cursor,
      _ => null,
    };
    final systemCursorType = overlayActive && imageCursor == null
        ? cursorValue?.systemType ?? 'arrow'
        : null;
    final trackPosition =
        imageCursor != null ||
        systemCursorType != null ||
        _imageCursor != null ||
        _systemCursorType != null;
    final cursorX = viewportCursorPosition.dx;
    final cursorY = viewportCursorPosition.dy;
    if (cursor == _mouseCursor &&
        identical(imageCursor, _imageCursor) &&
        systemCursorType == _systemCursorType &&
        (!trackPosition ||
            (cursorX == _imageCursorX && cursorY == _imageCursorY))) {
      return;
    }

    final canMarkNeedsBuild =
        markNeedsBuild &&
        mounted &&
        WidgetsBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks;
    if (!canMarkNeedsBuild) {
      _mouseCursor = cursor;
      _imageCursor = imageCursor;
      _systemCursorType = systemCursorType;
      _imageCursorX = cursorX;
      _imageCursorY = cursorY;
      return;
    }

    setState(() {
      _mouseCursor = cursor;
      _imageCursor = imageCursor;
      _systemCursorType = systemCursorType;
      _imageCursorX = cursorX;
      _imageCursorY = cursorY;
    });
  }
}

class _ViewportSizeReporter extends StatefulWidget {
  const _ViewportSizeReporter({
    required this.onSizeChanged,
    required this.child,
  });

  final ValueChanged<Size> onSizeChanged;
  final Widget child;

  @override
  State<_ViewportSizeReporter> createState() => _ViewportSizeReporterState();
}

class _ViewportSizeReporterState extends State<_ViewportSizeReporter> {
  Size? _lastReportedSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width > 0 && size.height > 0 && _lastReportedSize != size) {
          _lastReportedSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onSizeChanged(size);
            }
          });
        }

        return widget.child;
      },
    );
  }
}

class _LoveHarnessBackdropPainter extends CustomPainter {
  const _LoveHarnessBackdropPainter({required this.presentation});

  final LoveFlamePresentationGeometry presentation;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF050816), Color(0xFF0D1322), Color(0xFF111C2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );

    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.22),
      size.shortestSide * 0.18,
      Paint()..color = const Color(0x1438BDF8),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.78),
      size.shortestSide * 0.16,
      Paint()..color = const Color(0x12F59E0B),
    );

    final destinationRect = presentation.destinationRect;
    for (double y = 28; y < size.height; y += 28) {
      if (destinationRect.height > 0 &&
          y > destinationRect.top - 12 &&
          y < destinationRect.bottom + 12) {
        continue;
      }
      canvas.drawLine(
        Offset(24, y),
        Offset(size.width - 24, y),
        Paint()
          ..color = const Color(0x112B4269)
          ..strokeWidth = 1,
      );
    }

    if (destinationRect.width <= 0 || destinationRect.height <= 0) {
      return;
    }

    final shadowRect = destinationRect.inflate(18);
    final frameRect = destinationRect.inflate(10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shadowRect, const Radius.circular(28)),
      Paint()..color = const Color(0x55030A16),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x2A86EFAC),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(destinationRect, const Radius.circular(16)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x40E2E8F0),
    );

    _drawCornerMarker(
      canvas,
      destinationRect.topLeft,
      horizontal: 20,
      vertical: 14,
    );
    _drawCornerMarker(
      canvas,
      destinationRect.topRight,
      horizontal: -20,
      vertical: 14,
    );
    _drawCornerMarker(
      canvas,
      destinationRect.bottomLeft,
      horizontal: 20,
      vertical: -14,
    );
    _drawCornerMarker(
      canvas,
      destinationRect.bottomRight,
      horizontal: -20,
      vertical: -14,
    );
  }

  void _drawCornerMarker(
    Canvas canvas,
    Offset anchor, {
    required double horizontal,
    required double vertical,
  }) {
    final paint = Paint()
      ..color = const Color(0x66F8FAFC)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(anchor, Offset(anchor.dx + horizontal, anchor.dy), paint);
    canvas.drawLine(anchor, Offset(anchor.dx, anchor.dy + vertical), paint);
  }

  @override
  bool shouldRepaint(covariant _LoveHarnessBackdropPainter oldDelegate) {
    return oldDelegate.presentation.destinationRect !=
            presentation.destinationRect ||
        oldDelegate.presentation.viewportSize != presentation.viewportSize ||
        oldDelegate.presentation.logicalSize != presentation.logicalSize;
  }
}

class _LoveImageCursorOverlay extends StatelessWidget {
  const _LoveImageCursorOverlay({required this.cursor});

  final LoveMouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    final imageData = cursor.imageData;
    if (imageData == null) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      size: Size(imageData.width.toDouble(), imageData.height.toDouble()),
      painter: _LoveImageCursorPainter(imageData),
    );
  }
}

class _LoveImageCursorPainter extends CustomPainter {
  const _LoveImageCursorPainter(this.imageData);

  final LoveImageData imageData;

  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0; y < imageData.height; y++) {
      for (var x = 0; x < imageData.width; x++) {
        final color = imageData.getPixel(x, y);
        if (color.a <= 0) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()
            ..color = Color.fromRGBO(
              (color.r * 255).round().clamp(0, 255),
              (color.g * 255).round().clamp(0, 255),
              (color.b * 255).round().clamp(0, 255),
              color.a.clamp(0.0, 1.0),
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoveImageCursorPainter oldDelegate) {
    return !identical(imageData, oldDelegate.imageData);
  }
}

class _LoveSystemCursorOverlay extends StatelessWidget {
  const _LoveSystemCursorOverlay({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final overlay = _loveSystemCursorOverlayForType(type);
    return CustomPaint(
      size: Size(overlay.width, overlay.height),
      painter: _LoveSystemCursorPainter(type: overlay.type),
    );
  }
}

class _LoveSystemCursorPainter extends CustomPainter {
  const _LoveSystemCursorPainter({required this.type});

  final _LoveSystemCursorOverlayType type;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;

    switch (type) {
      case _LoveSystemCursorOverlayType.crosshair:
        final center = Offset(size.width / 2, size.height / 2);
        canvas.drawLine(
          Offset(center.dx, 0),
          Offset(center.dx, size.height),
          stroke,
        );
        canvas.drawLine(
          Offset(0, center.dy),
          Offset(size.width, center.dy),
          stroke,
        );
        canvas.drawCircle(center, 3, fill);
        canvas.drawCircle(center, 3, stroke);
      case _LoveSystemCursorOverlayType.ibeam:
        final x = size.width / 2;
        canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), stroke);
        canvas.drawLine(Offset(2, 2), Offset(size.width - 2, 2), stroke);
        canvas.drawLine(
          Offset(2, size.height - 2),
          Offset(size.width - 2, size.height - 2),
          stroke,
        );
      case _LoveSystemCursorOverlayType.hand:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(3, 4, size.width - 6, size.height - 8),
          const Radius.circular(6),
        );
        canvas.drawRRect(rect, fill);
        canvas.drawRRect(rect, stroke);
      case _LoveSystemCursorOverlayType.forbidden:
        final center = Offset(size.width / 2, size.height / 2);
        final radius = size.width / 2 - 2;
        canvas.drawCircle(center, radius, fill);
        canvas.drawCircle(center, radius, stroke);
        canvas.drawLine(
          Offset(4, size.height - 4),
          Offset(size.width - 4, 4),
          stroke,
        );
      case _LoveSystemCursorOverlayType.arrow:
        final path = Path()
          ..moveTo(0, 0)
          ..lineTo(0, size.height - 7)
          ..lineTo(4.5, size.height - 11)
          ..lineTo(8.5, size.height - 1)
          ..lineTo(12, size.height - 2.5)
          ..lineTo(7.5, size.height - 12.5)
          ..lineTo(size.width - 1, size.height - 12)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LoveSystemCursorPainter oldDelegate) {
    return type != oldDelegate.type;
  }
}

enum _LoveSystemCursorOverlayType { arrow, crosshair, ibeam, hand, forbidden }

({
  _LoveSystemCursorOverlayType type,
  double width,
  double height,
  double hotspotX,
  double hotspotY,
})
_loveSystemCursorOverlayForType(String type) {
  return switch (type) {
    'crosshair' => (
      type: _LoveSystemCursorOverlayType.crosshair,
      width: 21,
      height: 21,
      hotspotX: 10,
      hotspotY: 10,
    ),
    'ibeam' => (
      type: _LoveSystemCursorOverlayType.ibeam,
      width: 12,
      height: 24,
      hotspotX: 6,
      hotspotY: 12,
    ),
    'hand' => (
      type: _LoveSystemCursorOverlayType.hand,
      width: 18,
      height: 22,
      hotspotX: 2,
      hotspotY: 2,
    ),
    'no' => (
      type: _LoveSystemCursorOverlayType.forbidden,
      width: 18,
      height: 18,
      hotspotX: 9,
      hotspotY: 9,
    ),
    _ => (
      type: _LoveSystemCursorOverlayType.arrow,
      width: 16,
      height: 24,
      hotspotX: 0,
      hotspotY: 0,
    ),
  };
}

class _HarnessBadge extends StatelessWidget {
  const _HarnessBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xC0111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: child,
      ),
    );
  }
}
