// Experimental Flutter GPU rendering backend for [package:love2d].
//
// This package provides [LoveGpuRenderBackend] which renders LOVE2D draw
// commands through [package:flutter_gpu] instead of the standard Flutter
// Canvas 2D pipeline.
//
// ## Requirements
//
// - Flutter **master** channel
// - Impeller enabled (`--enable-impeller`)
// - Native assets enabled (`flutter config --enable-native-assets`)
//
// ## Usage
//
// ```dart
// import 'package:love2d_gpu/love2d_gpu.dart';
// ```

export 'src/love2d_gpu_render_backend.dart';
