import 'dart:convert' as convert;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:love2d/love2d.dart' hide LoveGpuRenderBackend;
import 'package:love2d_gpu/love2d_gpu.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

const String love2dDiagnosticsStream = 'Love2D';
const bool _love2dDtdFrameEvents = bool.fromEnvironment(
  'LOVE2D_DTD_FRAME_EVENTS',
  defaultValue: false,
);

/// Owns deterministic renderer controls and low-overhead diagnostics for the
/// GPU demo. The same state is exposed through Marionette and VM extension
/// events so an automation client can wait for a specific frame instead of
/// guessing from elapsed time.
final class Love2dDemoDiagnostics {
  Love2dDemoDiagnostics({
    required this.entryAsset,
    required this.gpuBackend,
    required this.engineMode,
    required String initialMode,
  }) : mode = ValueNotifier<String>(initialMode);

  final String entryAsset;
  final LoveGpuRenderBackend? gpuBackend;
  final String engineMode;
  final ValueNotifier<String> mode;

  LoveFlameHarnessGame? _game;
  LoveFlameInputAdapter? _input;
  void Function()? _gameFrameListener;
  int _presentedFrameCount = 0;

  bool get gpuAvailable => gpuBackend != null;

  void attachGame(LoveFlameHarnessGame game) {
    final previous = _game;
    final previousListener = _gameFrameListener;
    if (previous != null && previousListener != null) {
      previous.presentedFrameListenable.removeListener(previousListener);
    }
    _game = game;
    _input = null;
    _presentedFrameCount = 0;
    void listener() => _handlePresentedFrame(game);

    _gameFrameListener = listener;
    game.presentedFrameListenable.addListener(listener);
    _emit('harness_attached', state());
  }

  /// Attaches the input adapter for the currently mounted harness.
  void attachInput(LoveFlameInputAdapter input, LoveJoystickInputAdapter _) {
    _input = input;
  }

  /// Drives a LOVE virtual key for deterministic debug automation.
  String? setVirtualKey(String key, {required bool down}) {
    final input = _input;
    if (input == null) {
      return 'LOVE input adapter is not ready';
    }
    input.setVirtualKeyDown(key, down: down);
    return null;
  }

  /// Moves the LOVE pointer to a logical window coordinate for automation.
  String? setVirtualPointer(double x, double y) {
    final input = _input;
    if (input == null) {
      return 'LOVE input adapter is not ready';
    }
    if (!x.isFinite || !y.isFinite) {
      return 'x and y must be finite numbers';
    }
    input.setVirtualPointerPosition(x, y);
    return null;
  }

  String? resetInputState() {
    final input = _input;
    if (input == null) {
      return 'LOVE input adapter is not ready';
    }
    input.resetInputState();
    return null;
  }

  String? setMode(String requestedMode) {
    const allowedModes = <String>{'comparison', 'gpu', 'canvas'};
    if (!allowedModes.contains(requestedMode)) {
      return 'mode must be one of: comparison, gpu, canvas';
    }
    if (requestedMode == 'gpu' && !gpuAvailable) {
      return 'GPU backend is unavailable';
    }
    if (mode.value == requestedMode) {
      return null;
    }
    _presentedFrameCount = 0;
    mode.value = requestedMode;
    _emit('render_mode_changed', state());
    return null;
  }

  void resetFrameTiming() {
    _game?.resetFrameTimingStats();
    _emit('frame_timing_reset', state());
  }

  Map<String, Object?> state() {
    final game = _game;
    final frameTiming = game?.frameTimingStats;
    final snapshot = game?.presentedFrame;
    final lastFrame = frameTiming?.lastFrame;
    final mouse = game?.host.mouse;
    final windowMetrics = game?.host.windowMetrics;
    final presentation = game?.presentationGeometry;
    final comparisonStats = switch (game?.renderBackend) {
      final LoveSideBySideRenderBackend backend => <String, Object?>{
        'canvas': _renderStatsMap(backend.lastLeftStats),
        'gpu': _renderStatsMap(backend.lastRightStats),
      },
      _ => null,
    };
    final result = <String, Object?>{
      'schemaVersion': 2,
      'entryAsset': entryAsset,
      'engineMode': engineMode,
      'mode': mode.value,
      'gpuAvailable': gpuAvailable,
      'gpuMsaa': gpuBackend?.usesMultisampleAntialiasing ?? false,
      'gpuSampleCount': gpuBackend?.renderSampleCount ?? 1,
      'ready': _presentedFrameCount > 0,
      'presentedFrame': _presentedFrameCount,
      'commandCount': snapshot?.commands.length ?? 0,
      'input': <String, Object?>{
        'mouseX': mouse?.x ?? 0,
        'mouseY': mouse?.y ?? 0,
        'buttonsDown':
            mouse?.buttonsDown.toList(growable: false) ?? const <int>[],
        'pressedScancodes':
            game?.host.keyboard.pressedScancodes.toList(growable: false) ??
            const <String>[],
      },
      'window': <String, Object?>{
        'width': windowMetrics?.width ?? 0,
        'height': windowMetrics?.height ?? 0,
      },
      'presentation': <String, Object?>{
        'logicalWidth': presentation?.logicalSize.width ?? 0,
        'logicalHeight': presentation?.logicalSize.height ?? 0,
        'destinationLeft': presentation?.destinationRect.left ?? 0,
        'destinationTop': presentation?.destinationRect.top ?? 0,
        'destinationWidth': presentation?.destinationRect.width ?? 0,
        'destinationHeight': presentation?.destinationRect.height ?? 0,
      },
      'frameTiming': <String, Object?>{
        'sampleCount': frameTiming?.sampleCount ?? 0,
        'p95UpdateMicros': frameTiming?.p95UpdateDuration.inMicroseconds ?? 0,
        'maxUpdateMicros': frameTiming?.maxUpdateDuration.inMicroseconds ?? 0,
        'p95CpuFrameMicros':
            frameTiming?.p95CpuFrameDuration.inMicroseconds ?? 0,
        'p95RenderMicros': frameTiming?.p95RenderDuration.inMicroseconds ?? 0,
        'maxCpuFrameMicros':
            frameTiming?.maxCpuFrameDuration.inMicroseconds ?? 0,
        'lastRenderedCommands': lastFrame?.renderStats.renderedCommands ?? 0,
        'averageRenderedCommands': frameTiming?.averageRenderedCommands ?? 0,
        'averageSoftwareSurfaceFallbacks':
            frameTiming?.averageSoftwareSurfaceFallbacks ?? 0,
        'maxSoftwareSurfaceFallbacks':
            frameTiming?.maxSoftwareSurfaceFallbacks ?? 0,
      },
    };
    if (comparisonStats != null) {
      result['comparisonStats'] = comparisonStats;
    }
    return result;
  }

  Map<String, Object?> _renderStatsMap(LoveRenderStats stats) {
    return <String, Object?>{
      'renderedCommands': stats.renderedCommands,
      'softwareSurfaceFallbacks': stats.softwareSurfaceFallbacks,
      'atlasBatchCommands': stats.atlasBatchCommands,
      'atlasBatchItems': stats.atlasBatchItems,
      'textPainterCacheHits': stats.textPainterCacheHits,
      'textPainterCacheMisses': stats.textPainterCacheMisses,
      'textLayoutMicros': stats.textLayoutDuration.inMicroseconds,
      'totalSaveLayers': stats.totalSaveLayers,
    };
  }

  void _handlePresentedFrame(LoveFlameHarnessGame game) {
    // A mode change replaces the harness widget. A queued callback from the
    // previous harness must not consume the new harness's frame-1 marker or
    // publish a misleading ready event with an empty snapshot.
    if (!identical(_game, game)) {
      return;
    }
    _presentedFrameCount++;
    final frameId = _presentedFrameCount;
    final shouldEmitReady = frameId == 1;
    final shouldEmitSample =
        _love2dDtdFrameEvents && frameId > 1 && frameId % 30 == 0;
    if (!shouldEmitReady && !shouldEmitSample) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_game, game)) {
        return;
      }
      _emit(shouldEmitReady ? 'frame_ready' : 'frame_sample', <String, Object?>{
        'readyFrame': frameId,
        ...state(),
      });
    });
  }

  void _emit(String eventKind, Map<String, Object?> data) {
    if (!kDebugMode) {
      return;
    }
    developer.postEvent(eventKind, <String, Object?>{
      'schemaVersion': 2,
      'source': 'love2d_gpu_demo',
      'timestampMicros': DateTime.now().microsecondsSinceEpoch,
      ...data,
    }, stream: love2dDiagnosticsStream);
  }
}

/// Registers deterministic renderer controls as Marionette MCP extensions.
void registerLove2dMarionetteExtensions(Love2dDemoDiagnostics diagnostics) {
  registerMarionetteExtension(
    name: 'love2d.getRenderState',
    description: 'Returns the current LOVE2D renderer and frame state.',
    callback: (_) async =>
        MarionetteExtensionResult.success(diagnostics.state()),
  );
  registerMarionetteExtension(
    name: 'love2d.setRenderMode',
    description: 'Selects comparison, GPU-only, or Canvas-only rendering.',
    inputSchema: ExtensionInputSchema(
      properties: <String, ExtensionParam>{
        'mode': ExtensionParam.string(
          description: 'The renderer mode to activate.',
          enumValues: <String>['comparison', 'gpu', 'canvas'],
        ),
      },
      required: <String>['mode'],
    ),
    callback: (params) async {
      final requestedMode = params['mode'];
      if (requestedMode == null) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: mode',
        );
      }
      final error = diagnostics.setMode(requestedMode);
      if (error != null) {
        return MarionetteExtensionResult.invalidParams(error);
      }
      return MarionetteExtensionResult.success(diagnostics.state());
    },
  );
  registerMarionetteExtension(
    name: 'love2d.resetFrameTiming',
    description: 'Clears the rolling LOVE2D frame timing window.',
    callback: (_) async {
      diagnostics.resetFrameTiming();
      return MarionetteExtensionResult.success(diagnostics.state());
    },
  );
  registerMarionetteExtension(
    name: 'love2d.setVirtualKey',
    description: 'Presses or releases a LOVE key for deterministic testing.',
    callback: (params) async {
      final key = params['key'];
      final down = params['down'];
      final resolvedDown = switch (down) {
        'true' => true,
        'false' => false,
        _ => null,
      };
      if (key is! String || resolvedDown == null) {
        return MarionetteExtensionResult.invalidParams(
          'key must be a string and down must be a boolean',
        );
      }
      final error = diagnostics.setVirtualKey(key, down: resolvedDown);
      if (error != null) {
        return MarionetteExtensionResult.invalidParams(error);
      }
      return MarionetteExtensionResult.success(diagnostics.state());
    },
  );
  registerMarionetteExtension(
    name: 'love2d.resetInputState',
    description:
        'Clears transient LOVE keyboard, mouse, touch, and focus state.',
    callback: (_) async {
      final error = diagnostics.resetInputState();
      if (error != null) {
        return MarionetteExtensionResult.invalidParams(error);
      }
      return MarionetteExtensionResult.success(diagnostics.state());
    },
  );
  registerMarionetteExtension(
    name: 'love2d.setVirtualPointer',
    description:
        'Moves the LOVE pointer to a logical window coordinate for testing.',
    callback: (params) async {
      final x = double.tryParse(params['x'] ?? '');
      final y = double.tryParse(params['y'] ?? '');
      if (x == null || y == null) {
        return MarionetteExtensionResult.invalidParams(
          'x and y must be numbers',
        );
      }
      final error = diagnostics.setVirtualPointer(x, y);
      if (error != null) {
        return MarionetteExtensionResult.invalidParams(error);
      }
      return MarionetteExtensionResult.success(diagnostics.state());
    },
  );
}

/// Registers the same controls through the Dart VM service protocol.
///
/// Marionette is intentionally debug-only, but profile runs still expose the
/// VM service and are the required performance measurement mode. Keeping the
/// protocol surface identical lets the benchmark runner switch modes without
/// adding instrumentation to the frame loop.
void registerLove2dVmExtensions(Love2dDemoDiagnostics diagnostics) {
  developer.registerExtension(
    'ext.flutter.love2d.getRenderState',
    (_, _) async => developer.ServiceExtensionResponse.result(
      convert.jsonEncode(diagnostics.state()),
    ),
  );
  developer.registerExtension('ext.flutter.love2d.setRenderMode', (
    _,
    parameters,
  ) async {
    final requestedMode = parameters['mode'];
    if (requestedMode == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{
          'error': 'Missing required parameter: mode',
        }),
      );
    }
    final error = diagnostics.setMode(requestedMode);
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{'error': error}),
      );
    }
    return developer.ServiceExtensionResponse.result(
      convert.jsonEncode(diagnostics.state()),
    );
  });
  developer.registerExtension('ext.flutter.love2d.resetFrameTiming', (
    _,
    _,
  ) async {
    diagnostics.resetFrameTiming();
    return developer.ServiceExtensionResponse.result(
      convert.jsonEncode(diagnostics.state()),
    );
  });
  developer.registerExtension('ext.flutter.love2d.setVirtualKey', (
    _,
    parameters,
  ) async {
    final key = parameters['key'];
    final down = parameters['down'];
    final resolvedDown = switch (down) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    if (key == null || resolvedDown == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{
          'error': 'key and down=true|false are required',
        }),
      );
    }
    final error = diagnostics.setVirtualKey(key, down: resolvedDown);
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{'error': error}),
      );
    }
    return developer.ServiceExtensionResponse.result(
      convert.jsonEncode(diagnostics.state()),
    );
  });
  developer.registerExtension('ext.flutter.love2d.resetInputState', (
    _,
    _,
  ) async {
    final error = diagnostics.resetInputState();
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{'error': error}),
      );
    }
    return developer.ServiceExtensionResponse.result(
      convert.jsonEncode(diagnostics.state()),
    );
  });
  developer.registerExtension('ext.flutter.love2d.setVirtualPointer', (
    _,
    parameters,
  ) async {
    final x = double.tryParse(parameters['x'] ?? '');
    final y = double.tryParse(parameters['y'] ?? '');
    if (x == null || y == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{
          'error': 'x and y must be numbers',
        }),
      );
    }
    final error = diagnostics.setVirtualPointer(x, y);
    if (error != null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        convert.jsonEncode(<String, Object?>{'error': error}),
      );
    }
    return developer.ServiceExtensionResponse.result(
      convert.jsonEncode(diagnostics.state()),
    );
  });
}
