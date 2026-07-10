import 'package:flutter_gpu/gpu.dart' as gpu;

void bindVertexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView, {
  int slot = 0,
}) {
  final dynamic rp = pass;
  try {
    rp.bindVertexBuffer(bufferView, slot);
  } catch (_) {
    rp.bindVertexBuffer(bufferView);
  }
}

void bindIndexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView, {
  required gpu.IndexType indexType,
  int? indexCount,
}) {
  final dynamic rp = pass;
  if (indexCount != null) {
    try {
      rp.bindIndexBuffer(bufferView, indexType, indexCount);
      return;
    } catch (_) {
      // fall through
    }
  }
  try {
    rp.bindIndexBuffer(bufferView, indexType);
  } catch (_) {
    if (indexCount != null) {
      rp.bindIndexBuffer(bufferView, indexType, indexCount);
    } else {
      rp.bindIndexBuffer(bufferView, indexType, 0);
    }
  }
}

void drawVerticesCompat(
  gpu.RenderPass pass,
  int vertexCount, {
  int instanceCount = 1,
}) {
  final dynamic rp = pass;
  try {
    rp.draw(vertexCount, instanceCount: instanceCount);
  } catch (_) {
    try {
      rp.draw(vertexCount);
    } catch (_) {
      rp.draw();
    }
  }
}

void drawIndexedCompat(
  gpu.RenderPass pass,
  int indexCount, {
  int instanceCount = 1,
}) {
  final dynamic rp = pass;
  try {
    rp.drawIndexed(indexCount, instanceCount: instanceCount);
  } catch (_) {
    try {
      rp.draw(indexCount, instanceCount: instanceCount);
    } catch (_) {
      try {
        rp.draw(indexCount);
      } catch (_) {
        rp.draw();
      }
    }
  }
}
