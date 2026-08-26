import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_lualike/flutter_lualike.dart';
import 'package:love2d/love2d.dart' hide LoveGpuRenderBackend;
import 'package:love2d_gpu/love2d_gpu.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'love2d_demo_diagnostics.dart';

const String _entryAsset = String.fromEnvironment(
  'LOVE_ENTRY_ASSET',
  defaultValue: 'assets/main.lua',
);
const String _engineModeName = String.fromEnvironment(
  'LOVE_ENGINE_MODE',
  defaultValue: 'ast',
);

enum _DemoRenderMode { comparison, gpu, canvas }

const bool _enableFlutterDriver = bool.fromEnvironment(
  'ENABLE_FLUTTER_DRIVER',
  defaultValue: false,
);

void main() async {
  final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
  final useMarionette = kDebugMode && !_enableFlutterDriver && !isFlutterTest;
  if (_enableFlutterDriver) {
    enableFlutterDriverExtension();
  } else if (useMarionette) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  final usesHostFilesystem = _isAbsolutePath(_entryAsset);
  final engineMode = _engineModeFromName(_engineModeName);
  // Keep the standalone lualike file APIs pointed at the same packaged
  // source tree that LOVE mounts. Host-source mode deliberately leaves the
  // native lualike IO backend installed so absolute checkout paths remain
  // readable; LOVE still receives its explicit adapter below.
  if (!usesHostFilesystem) {
    await useAssetBundle(rootBundle, assetRoot: 'assets');
  }
  final LoveFilesystemAdapter? filesystemAdapter = usesHostFilesystem
      ? LoveLualikeFilesystemAdapter()
      : null;
  if (filesystemAdapter case final adapter?) {
    debugPrint(
      '[love2d_gpu_demo] host source exists='
      '${await adapter.fileExists(_entryAsset)} '
      'bytes=${(await adapter.fileSize(_entryAsset)) ?? -1}',
    );
  }
  late final List<String> imageWarmupAssetKeys;
  if (usesHostFilesystem) {
    imageWarmupAssetKeys = const <String>[];
  } else {
    final lualikeAssetBackend = AssetBundleFileSystemBackend(
      rootBundle,
      assetRoot: 'assets',
    );
    await lualikeAssetBackend.prewarm();
    imageWarmupAssetKeys = (await lualikeAssetBackend.listDirectory(
      'art',
    )).where((key) => key.endsWith('.png')).toList(growable: false);
  }
  debugPrint(
    '[love2d_gpu_demo] flutter_lualike indexed '
    '${imageWarmupAssetKeys.length} art assets for LOVE warmup'
    '${usesHostFilesystem ? ' (host-source mode)' : ''}',
  );

  debugPrint('[love2d_gpu_demo] initializing...');
  debugPrint('[love2d_gpu_demo] trying gpu.gpuContext...');

  LoveGpuRenderBackend? gpuBackend;
  try {
    gpuBackend = await LoveGpuRenderBackend.create();
    if (gpuBackend != null) {
      debugPrint('[love2d_gpu_demo] USING FLUTTER GPU BACKEND');
    } else {
      debugPrint(
        '[love2d_gpu_demo] GPU backend returned null, falling back to Canvas',
      );
    }
  } catch (e, stack) {
    debugPrint('[love2d_gpu_demo] GPU backend FAILED: $e');
    debugPrint('[love2d_gpu_demo] stack: $stack');
  }

  final backend = gpuBackend ?? LoveCanvasRenderBackend();
  debugPrint('[love2d_gpu_demo] backend.name = ${backend.name}');
  final diagnostics = Love2dDemoDiagnostics(
    entryAsset: _entryAsset,
    gpuBackend: gpuBackend,
    engineMode: engineMode.name,
    initialMode: gpuBackend == null ? 'canvas' : 'comparison',
  );
  if (useMarionette) {
    registerLove2dMarionetteExtensions(diagnostics);
  } else if (!_enableFlutterDriver && !isFlutterTest) {
    // Profile builds do not initialize Marionette, but they still expose the
    // VM service used by the repeatable renderer benchmark.
    registerLove2dVmExtensions(diagnostics);
  }
  runApp(
    Love2dGpuDemo(
      gpuBackend: gpuBackend,
      diagnostics: diagnostics,
      engineMode: engineMode,
      imageWarmupAssetKeys: imageWarmupAssetKeys,
      filesystemAdapter: filesystemAdapter,
    ),
  );
}

EngineMode _engineModeFromName(String value) {
  return switch (value) {
    'ir' => EngineMode.ir,
    'luaBytecode' => EngineMode.luaBytecode,
    _ => EngineMode.ast,
  };
}

bool _isAbsolutePath(String value) {
  return value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}

class Love2dGpuDemo extends StatefulWidget {
  const Love2dGpuDemo({
    super.key,
    required this.gpuBackend,
    required this.diagnostics,
    required this.engineMode,
    required this.imageWarmupAssetKeys,
    this.filesystemAdapter,
  });

  final LoveGpuRenderBackend? gpuBackend;
  final Love2dDemoDiagnostics diagnostics;
  final EngineMode engineMode;
  final List<String> imageWarmupAssetKeys;
  final LoveFilesystemAdapter? filesystemAdapter;

  @override
  State<Love2dGpuDemo> createState() => _Love2dGpuDemoState();
}

class _Love2dGpuDemoState extends State<Love2dGpuDemo> {
  final LoveRenderBackend _canvasBackend = LoveCanvasRenderBackend();
  late final LoveSideBySideRenderBackend? _comparisonBackend =
      widget.gpuBackend == null
      ? null
      : LoveSideBySideRenderBackend(
          left: _canvasBackend,
          right: widget.gpuBackend!,
        );
  late _DemoRenderMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = _modeFromName(widget.diagnostics.mode.value);
    widget.diagnostics.mode.addListener(_handleRequestedModeChanged);
  }

  @override
  void dispose() {
    widget.diagnostics.mode.removeListener(_handleRequestedModeChanged);
    super.dispose();
  }

  void _handleRequestedModeChanged() {
    if (!mounted) return;
    final requestedMode = _modeFromName(widget.diagnostics.mode.value);
    if (requestedMode == _mode) return;
    setState(() => _mode = requestedMode);
  }

  LoveRenderBackend get _activeBackend {
    return switch (_mode) {
      _DemoRenderMode.comparison => _comparisonBackend ?? _canvasBackend,
      _DemoRenderMode.gpu => widget.gpuBackend ?? _canvasBackend,
      _DemoRenderMode.canvas => _canvasBackend,
    };
  }

  String get _modeActionLabel {
    return switch (_mode) {
      _DemoRenderMode.comparison => 'Show GPU only',
      _DemoRenderMode.gpu => 'Show Canvas only',
      _DemoRenderMode.canvas => 'Compare side by side',
    };
  }

  IconData get _modeIcon {
    return switch (_mode) {
      _DemoRenderMode.comparison => Icons.speed,
      _DemoRenderMode.gpu => Icons.layers,
      _DemoRenderMode.canvas => Icons.compare,
    };
  }

  void _cycleRendererMode() {
    if (!_gpuAvailable) return;
    final nextMode = switch (_mode) {
      _DemoRenderMode.comparison => 'gpu',
      _DemoRenderMode.gpu => 'canvas',
      _DemoRenderMode.canvas => 'comparison',
    };
    widget.diagnostics.setMode(nextMode);
  }

  bool get _gpuAvailable => widget.gpuBackend != null;

  @override
  Widget build(BuildContext context) {
    final backend = _activeBackend;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'love2d_gpu demo',
      home: Scaffold(
        key: const ValueKey('love2d-gpu-demo'),
        appBar: AppBar(
          title: Text(
            key: const ValueKey('love2d-render-mode'),
            'love2d — ${backend.name}',
          ),
          backgroundColor: const Color(0xFF0D0D1A),
          foregroundColor: Colors.white70,
        ),
        body: Stack(
          children: [
            LoveFlameHarness(
              key: ValueKey('${_mode.name}:$_entryAsset'),
              entryAsset: _entryAsset,
              engineMode: widget.engineMode,
              filesystemAdapter: widget.filesystemAdapter,
              renderBackend: backend,
              imageWarmupAssetKeys: widget.imageWarmupAssetKeys,
              onInputAdaptersReady: widget.diagnostics.attachInput,
              debugOnGameCreated: widget.diagnostics.attachGame,
              inputPointTransform: _mode == _DemoRenderMode.comparison
                  ? (point, geometry) {
                      final comparison = _comparisonBackend;
                      if (comparison == null) return point;
                      return comparison.mapInputPoint(
                        point,
                        geometry.logicalSize,
                      );
                    }
                  : null,
              inputDeltaTransform: _mode == _DemoRenderMode.comparison
                  ? (delta, point, geometry) {
                      final comparison = _comparisonBackend;
                      if (comparison == null) return delta;
                      return comparison.mapInputDelta(
                        delta,
                        point,
                        geometry.logicalSize,
                      );
                    }
                  : null,
            ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: Material(
                  color: const Color(0xDD111827),
                  elevation: 6,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    key: const ValueKey('love2d-render-mode-toggle'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: _gpuAvailable ? _cycleRendererMode : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_modeIcon, size: 18, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                            _modeActionLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_DemoRenderMode _modeFromName(String name) {
  return switch (name) {
    'gpu' => _DemoRenderMode.gpu,
    'canvas' => _DemoRenderMode.canvas,
    _ => _DemoRenderMode.comparison,
  };
}
