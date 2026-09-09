import 'dart:typed_data';

import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const List<int> _triangleVertexOrder = <int>[0, 1, 2, 1, 3, 2];
const List<double> _quadX = <double>[0, 1, 0, 1];
const List<double> _quadY = <double>[0, 0, 1, 1];

/// Reusable CPU-side vertex expansion for sprites and particles.
///
/// LOVE supplies 2D affine matrices. Expanding their six meaningful
/// coefficients directly avoids allocating a Matrix4, Offset, LoveColor, and
/// Float32List for every sprite-batch render. The returned list is scratch
/// storage; callers must upload [floatLength] values before invoking another
/// build method.
final class GpuSpriteGeometryBuilder {
  Float32List _vertices = Float32List(0);

  /// Number of meaningful floats in the most recently returned buffer.
  int floatLength = 0;

  Float32List buildSprites({
    required List<LoveSpriteBatchSprite> sprites,
    required LoveImage image,
    required vm.Matrix4 commandTransform,
    required vm.Matrix4 drawTransform,
    required LoveColor commandColor,
  }) {
    final vertices = _prepare(sprites.length * 6 * 8);
    final left = commandTransform.storage;
    final right = drawTransform.storage;
    final base00 = (left[0] * right[0]) + (left[4] * right[1]);
    final base10 = (left[1] * right[0]) + (left[5] * right[1]);
    final base01 = (left[0] * right[4]) + (left[4] * right[5]);
    final base11 = (left[1] * right[4]) + (left[5] * right[5]);
    final baseTx = (left[0] * right[12]) + (left[4] * right[13]) + left[12];
    final baseTy = (left[1] * right[12]) + (left[5] * right[13]) + left[13];
    var offset = 0;

    for (final sprite in sprites) {
      final quad = sprite.quad;
      final imageWidth = quad?.textureWidth ?? image.width.toDouble();
      final imageHeight = quad?.textureHeight ?? image.height.toDouble();
      final quadWidth = quad?.width ?? imageWidth;
      final quadHeight = quad?.height ?? imageHeight;
      final uvX = (quad?.x ?? 0.0) / imageWidth;
      final uvY = (quad?.y ?? 0.0) / imageHeight;
      final uvScaleX = quadWidth / imageWidth;
      final uvScaleY = quadHeight / imageHeight;
      final transform = sprite.transform.storage;
      final m00 = (base00 * transform[0]) + (base01 * transform[1]);
      final m10 = (base10 * transform[0]) + (base11 * transform[1]);
      final m01 = (base00 * transform[4]) + (base01 * transform[5]);
      final m11 = (base10 * transform[4]) + (base11 * transform[5]);
      final tx = (base00 * transform[12]) + (base01 * transform[13]) + baseTx;
      final ty = (base10 * transform[12]) + (base11 * transform[13]) + baseTy;
      final spriteColor = sprite.color;
      final r = commandColor.r * (spriteColor?.r ?? 1.0);
      final g = commandColor.g * (spriteColor?.g ?? 1.0);
      final b = commandColor.b * (spriteColor?.b ?? 1.0);
      final a = commandColor.a * (spriteColor?.a ?? 1.0);

      offset = _writeQuad(
        vertices,
        offset,
        m00,
        m10,
        m01,
        m11,
        tx,
        ty,
        quadWidth,
        quadHeight,
        uvX,
        uvY,
        uvScaleX,
        uvScaleY,
        r,
        g,
        b,
        a,
      );
    }

    floatLength = offset;
    return vertices;
  }

  Float32List buildParticles({
    required List<LoveParticleDrawEntry> particles,
    required LoveImage image,
    required vm.Matrix4 commandTransform,
    required vm.Matrix4 drawTransform,
    required LoveColor commandColor,
  }) {
    final vertices = _prepare(particles.length * 6 * 8);
    final left = commandTransform.storage;
    final right = drawTransform.storage;
    final base00 = (left[0] * right[0]) + (left[4] * right[1]);
    final base10 = (left[1] * right[0]) + (left[5] * right[1]);
    final base01 = (left[0] * right[4]) + (left[4] * right[5]);
    final base11 = (left[1] * right[4]) + (left[5] * right[5]);
    final baseTx = (left[0] * right[12]) + (left[4] * right[13]) + left[12];
    final baseTy = (left[1] * right[12]) + (left[5] * right[13]) + left[13];
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    var offset = 0;

    for (final particle in particles) {
      final quad = particle.quad;
      final quadWidth = quad?.width ?? imageWidth;
      final quadHeight = quad?.height ?? imageHeight;
      final uvX = (quad?.x ?? 0.0) / imageWidth;
      final uvY = (quad?.y ?? 0.0) / imageHeight;
      final uvScaleX = quadWidth / imageWidth;
      final uvScaleY = quadHeight / imageHeight;
      final transform = particle.transform.storage;
      final m00 = (base00 * transform[0]) + (base01 * transform[1]);
      final m10 = (base10 * transform[0]) + (base11 * transform[1]);
      final m01 = (base00 * transform[4]) + (base01 * transform[5]);
      final m11 = (base10 * transform[4]) + (base11 * transform[5]);
      final tx = (base00 * transform[12]) + (base01 * transform[13]) + baseTx;
      final ty = (base10 * transform[12]) + (base11 * transform[13]) + baseTy;
      final color = particle.color;

      offset = _writeQuad(
        vertices,
        offset,
        m00,
        m10,
        m01,
        m11,
        tx,
        ty,
        quadWidth,
        quadHeight,
        uvX,
        uvY,
        uvScaleX,
        uvScaleY,
        commandColor.r * color.r,
        commandColor.g * color.g,
        commandColor.b * color.b,
        commandColor.a * color.a,
      );
    }

    floatLength = offset;
    return vertices;
  }

  Float32List _prepare(int requiredLength) {
    if (_vertices.length < requiredLength) {
      var capacity = _vertices.isEmpty ? 256 : _vertices.length;
      while (capacity < requiredLength) {
        capacity *= 2;
      }
      _vertices = Float32List(capacity);
    }
    floatLength = 0;
    return _vertices;
  }
}

int _writeQuad(
  Float32List vertices,
  int offset,
  double m00,
  double m10,
  double m01,
  double m11,
  double tx,
  double ty,
  double width,
  double height,
  double uvX,
  double uvY,
  double uvScaleX,
  double uvScaleY,
  double r,
  double g,
  double b,
  double a,
) {
  for (final index in _triangleVertexOrder) {
    final x = _quadX[index];
    final y = _quadY[index];
    vertices[offset++] = (m00 * width * x) + (m01 * height * y) + tx;
    vertices[offset++] = (m10 * width * x) + (m11 * height * y) + ty;
    vertices[offset++] = (x * uvScaleX) + uvX;
    vertices[offset++] = (y * uvScaleY) + uvY;
    vertices[offset++] = r;
    vertices[offset++] = g;
    vertices[offset++] = b;
    vertices[offset++] = a;
  }
  return offset;
}

/// Legacy allocation-heavy expansion retained for explicit A/B builds.
Float32List buildLegacySpriteVertices({
  required List<LoveSpriteBatchSprite> sprites,
  required LoveImage image,
  required vm.Matrix4 commandTransform,
  required vm.Matrix4 drawTransform,
  required LoveColor commandColor,
}) {
  final base = vm.Matrix4.copy(commandTransform)..multiply(drawTransform);
  final vertices = Float32List(sprites.length * 6 * 8);
  var offset = 0;
  for (final sprite in sprites) {
    final quad = sprite.quad;
    final imageWidth = quad?.textureWidth ?? image.width.toDouble();
    final imageHeight = quad?.textureHeight ?? image.height.toDouble();
    final quadWidth = quad?.width ?? imageWidth;
    final quadHeight = quad?.height ?? imageHeight;
    final uvX = (quad?.x ?? 0.0) / imageWidth;
    final uvY = (quad?.y ?? 0.0) / imageHeight;
    final uvScaleX = quadWidth / imageWidth;
    final uvScaleY = quadHeight / imageHeight;
    final scale = vm.Matrix4.diagonal3Values(quadWidth, quadHeight, 1);
    final transform = vm.Matrix4.copy(base)
      ..multiply(sprite.transform)
      ..multiply(scale);
    final color = sprite.color;
    final r = commandColor.r * (color?.r ?? 1);
    final g = commandColor.g * (color?.g ?? 1);
    final b = commandColor.b * (color?.b ?? 1);
    final a = commandColor.a * (color?.a ?? 1);
    offset = _writeLegacyQuad(
      vertices,
      offset,
      transform,
      uvX,
      uvY,
      uvScaleX,
      uvScaleY,
      r,
      g,
      b,
      a,
    );
  }
  return vertices;
}

/// Legacy particle expansion retained for explicit A/B builds.
Float32List buildLegacyParticleVertices({
  required List<LoveParticleDrawEntry> particles,
  required LoveImage image,
  required vm.Matrix4 commandTransform,
  required vm.Matrix4 drawTransform,
  required LoveColor commandColor,
}) {
  final base = vm.Matrix4.copy(commandTransform)..multiply(drawTransform);
  final imageWidth = image.width.toDouble();
  final imageHeight = image.height.toDouble();
  final vertices = Float32List(particles.length * 6 * 8);
  var offset = 0;
  for (final particle in particles) {
    final quad = particle.quad;
    final quadWidth = quad?.width ?? imageWidth;
    final quadHeight = quad?.height ?? imageHeight;
    final uvX = (quad?.x ?? 0.0) / imageWidth;
    final uvY = (quad?.y ?? 0.0) / imageHeight;
    final uvScaleX = quadWidth / imageWidth;
    final uvScaleY = quadHeight / imageHeight;
    final scale = vm.Matrix4.diagonal3Values(quadWidth, quadHeight, 1);
    final transform = vm.Matrix4.copy(base)
      ..multiply(particle.transform)
      ..multiply(scale);
    final color = particle.color;
    offset = _writeLegacyQuad(
      vertices,
      offset,
      transform,
      uvX,
      uvY,
      uvScaleX,
      uvScaleY,
      commandColor.r * color.r,
      commandColor.g * color.g,
      commandColor.b * color.b,
      commandColor.a * color.a,
    );
  }
  return vertices;
}

int _writeLegacyQuad(
  Float32List vertices,
  int offset,
  vm.Matrix4 transform,
  double uvX,
  double uvY,
  double uvScaleX,
  double uvScaleY,
  double r,
  double g,
  double b,
  double a,
) {
  final storage = transform.storage;
  for (final index in _triangleVertexOrder) {
    final x = _quadX[index];
    final y = _quadY[index];
    vertices[offset++] = (storage[0] * x) + (storage[4] * y) + storage[12];
    vertices[offset++] = (storage[1] * x) + (storage[5] * y) + storage[13];
    vertices[offset++] = (x * uvScaleX) + uvX;
    vertices[offset++] = (y * uvScaleY) + uvY;
    vertices[offset++] = r;
    vertices[offset++] = g;
    vertices[offset++] = b;
    vertices[offset++] = a;
  }
  return offset;
}
