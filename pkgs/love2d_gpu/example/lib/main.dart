import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:love2d/love2d.dart' hide LoveGpuRenderBackend;
import 'package:love2d_gpu/love2d_gpu.dart';

const String _entryAsset = String.fromEnvironment(
  'LOVE_ENTRY_ASSET',
  defaultValue: 'assets/main.lua',
);

void main() async {
  enableFlutterDriverExtension();
  debugPrint('[love2d_gpu_demo] initializing...');
  debugPrint('[love2d_gpu_demo] trying gpu.gpuContext...');
  WidgetsFlutterBinding.ensureInitialized();

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
  runApp(Love2dGpuDemo(gpuBackend: gpuBackend));
}

class Love2dGpuDemo extends StatefulWidget {
  const Love2dGpuDemo({super.key, required this.gpuBackend});

  final LoveGpuRenderBackend? gpuBackend;

  @override
  State<Love2dGpuDemo> createState() => _Love2dGpuDemoState();
}

class _Love2dGpuDemoState extends State<Love2dGpuDemo> {
  final LoveRenderBackend _canvasBackend = LoveCanvasRenderBackend();
  bool _useGpu = true;

  LoveRenderBackend get _activeBackend {
    if (_useGpu && widget.gpuBackend != null) {
      return widget.gpuBackend!;
    }
    return _canvasBackend;
  }

  bool get _gpuAvailable => widget.gpuBackend != null;

  void _toggleRenderer() {
    if (!_gpuAvailable && !_useGpu) return;
    setState(() => _useGpu = !_useGpu);
  }

  @override
  void initState() {
    super.initState();
    _useGpu = _gpuAvailable;
  }

  @override
  Widget build(BuildContext context) {
    final backend = _activeBackend;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'love2d_gpu demo',
      home: Scaffold(
        appBar: AppBar(
          title: Text('love2d — ${backend.name}'),
          backgroundColor: const Color(0xFF0D0D1A),
          foregroundColor: Colors.white70,
        ),
        body: Stack(
          children: [
            LoveFlameHarness(
              key: ValueKey('${backend.runtimeType}:$_entryAsset'),
              entryAsset: _entryAsset,
              renderBackend: backend,
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
                    borderRadius: BorderRadius.circular(999),
                    onTap: _gpuAvailable ? _toggleRenderer : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _useGpu ? Icons.speed : Icons.layers,
                            size: 18,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _useGpu ? 'Switch to Canvas' : 'Switch to GPU',
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
