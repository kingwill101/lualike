import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math_64.dart' as vm;

const _littleEndian = Endian.little;

/// Manages a frame-cyclic [gpu.HostBuffer] for per-frame vertex, index, and
/// uniform data uploads.
///
/// [HostBuffer] is a bump allocator that cycles through 4 internal device
/// buffers. Each frame:
///
/// 1. [reset] advances the cycle (may block if the GPU is still reading the
///    next frame's buffer).
/// 2. [emplaceFloats] appends vertex/uniform data and returns a [gpu.BufferView].
/// 3. At the end of the frame, the buffer is implicitly ready for the next cycle.
///
/// This avoids per-frame malloc/free churn for GPU-visible memory.
class GpuHostBufferPool {
  /// Creates a host buffer pool.
  ///
  /// [blockLengthInBytes] controls the initial capacity of each of the 4
  /// internal buffers. Increase this if you see frame stalls from buffer
  /// growth.
  GpuHostBufferPool(
    gpu.GpuContext gpuContext, {
    int blockLengthInBytes = gpu.HostBuffer.kDefaultBlockLengthInBytes,
  }) : _hostBuffer = gpuContext.createHostBuffer(
         blockLengthInBytes: blockLengthInBytes,
       );

  final gpu.HostBuffer _hostBuffer;

  /// Advances the host buffer to the next internal frame.
  ///
  /// Call this once at the beginning of [GpuCommandRenderer.renderFrame].
  void reset() {
    _hostBuffer.reset();
  }

  /// Appends a list of floats to the host buffer and returns a [BufferView].
  gpu.BufferView emplaceFloats(List<double> floats) {
    if (floats case final Float32List typedFloats) {
      return _hostBuffer.emplace(ByteData.sublistView(typedFloats));
    }
    return _hostBuffer.emplace(_toByteData(floats));
  }

  /// Appends a typed float list to the host buffer without per-element copies.
  gpu.BufferView emplaceFloat32List(Float32List floats) {
    return _hostBuffer.emplace(ByteData.sublistView(floats));
  }

  /// Appends raw byte data to the host buffer and returns a [BufferView].
  gpu.BufferView emplaceRaw(ByteData data) {
    return _hostBuffer.emplace(data);
  }

  /// Appends a combined MVP matrix + color uniform block.
  ///
  /// The block layout matches `VertInfo` in `love_base.vert`:
  ///   mat4 mvp;   // 16 floats = 64 bytes
  ///   vec4 color; // 4 floats = 16 bytes
  gpu.BufferView emplaceVertInfo(vm.Matrix4 mvp, vm.Vector4 color) {
    final floats = Float32List(20);
    final matrix = mvp.storage;
    for (var i = 0; i < 16; i++) {
      floats[i] = matrix[i];
    }
    floats[16] = color.x;
    floats[17] = color.y;
    floats[18] = color.z;
    floats[19] = color.w;
    return emplaceFloat32List(floats);
  }

  static ByteData _toByteData(List<double> floats) {
    final data = ByteData(floats.length * 4);
    for (var i = 0; i < floats.length; i++) {
      data.setFloat32(i * 4, floats[i], _littleEndian);
    }
    return data;
  }
}

/// Extension helpers for building [gpu.BufferView] from common LOVE types.
extension GpuBufferViewBuilder on GpuHostBufferPool {
  /// Emplaces vertex data packed as 8 floats per vertex:
  /// x, y, u, v, r, g, b, a.
  gpu.BufferView emplaceVertices(
    List<
      ({
        double x,
        double y,
        double u,
        double v,
        double r,
        double g,
        double b,
        double a,
      })
    >
    vertices,
  ) {
    final floats = Float32List(vertices.length * 8);
    var offset = 0;
    for (final v in vertices) {
      floats[offset++] = v.x;
      floats[offset++] = v.y;
      floats[offset++] = v.u;
      floats[offset++] = v.v;
      floats[offset++] = v.r;
      floats[offset++] = v.g;
      floats[offset++] = v.b;
      floats[offset++] = v.a;
    }
    return emplaceFloat32List(floats);
  }

  /// Emplaces a buffer view containing 16-bit index data.
  gpu.BufferView emplaceIndices(List<int> indices) {
    final data = ByteData(indices.length * 2);
    for (var i = 0; i < indices.length; i++) {
      data.setUint16(i * 2, indices[i], _littleEndian);
    }
    return emplaceRaw(data);
  }
}
