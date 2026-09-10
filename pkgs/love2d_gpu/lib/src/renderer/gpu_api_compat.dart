import 'package:flutter_gpu/gpu.dart' as gpu;

void bindVertexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView, {
  int slot = 0,
}) {
  // flutter_gpu's current API makes slot a named argument. The previous
  // compatibility probe tried the old positional form first, which raised a
  // NoSuchMethodError on every draw before retrying the correct call.
  pass.bindVertexBuffer(bufferView, slot: slot);
}

void bindIndexBufferCompat(
  gpu.RenderPass pass,
  gpu.BufferView bufferView, {
  required gpu.IndexType indexType,
}) {
  // Index count is supplied to drawIndexed, not to bindIndexBuffer.
  pass.bindIndexBuffer(bufferView, indexType);
}

void drawVerticesCompat(
  gpu.RenderPass pass,
  int vertexCount, {
  int instanceCount = 1,
}) {
  pass.draw(vertexCount, instanceCount: instanceCount);
}

void drawIndexedCompat(
  gpu.RenderPass pass,
  int indexCount, {
  int instanceCount = 1,
}) {
  pass.drawIndexed(indexCount, instanceCount: instanceCount);
}
