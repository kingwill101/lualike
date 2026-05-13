part of '../love_runtime.dart';

/// Error message for snapshots that include Flutter fragment-asset shaders.
const String _loveSoftwareReadbackFlutterFragmentShaderUnsupportedMessage =
    'does not yet support software readback of Flutter fragment-asset shaders';

/// Returns the first reason [snapshot] cannot be read back in software, if any.
String? loveSoftwareReadbackUnsupportedReasonForSnapshot(
  LoveGraphicsSurfaceSnapshot snapshot,
) {
  return _loveSoftwareReadbackUnsupportedReasonForSnapshot(
    snapshot,
    visitedSurfaces: HashSet<LoveGraphicsSurfaceSnapshot>.identity(),
    visitedImages: HashSet<LoveImage>.identity(),
  );
}

/// Recursively checks [snapshot] and nested drawables for readback blockers.
String? _loveSoftwareReadbackUnsupportedReasonForSnapshot(
  LoveGraphicsSurfaceSnapshot snapshot, {
  required Set<LoveGraphicsSurfaceSnapshot> visitedSurfaces,
  required Set<LoveImage> visitedImages,
}) {
  if (!visitedSurfaces.add(snapshot)) {
    return null;
  }

  for (final command in snapshot.commands) {
    final shader = command.shader;
    if (shader != null && loveShaderUsesFlutterFragmentAsset(shader)) {
      return _loveSoftwareReadbackFlutterFragmentShaderUnsupportedMessage;
    }

    final nestedReason = switch (command) {
      final LoveImageCommand image =>
        _loveSoftwareReadbackUnsupportedReasonForImage(
          resolveDrawableImageForLayer(image.image, layer: image.layer),
          visitedSurfaces: visitedSurfaces,
          visitedImages: visitedImages,
        ),
      final LoveSpriteBatchCommand spriteBatch =>
        _loveSoftwareReadbackUnsupportedReasonForSpriteBatch(
          spriteBatch.spriteBatch,
          visitedSurfaces: visitedSurfaces,
          visitedImages: visitedImages,
        ),
      final LoveParticleSystemCommand particleSystem =>
        _loveSoftwareReadbackUnsupportedReasonForImage(
          particleSystem.particleSystem.texture,
          visitedSurfaces: visitedSurfaces,
          visitedImages: visitedImages,
        ),
      final LoveMeshCommand mesh =>
        _loveSoftwareReadbackUnsupportedReasonForImage(
          _loveSoftwareReadbackMeshTextureImage(mesh.mesh),
          visitedSurfaces: visitedSurfaces,
          visitedImages: visitedImages,
        ),
      _ => null,
    };
    if (nestedReason != null) {
      return nestedReason;
    }
  }

  return null;
}

/// Returns the first readback blocker reachable from [spriteBatch], if any.
String? _loveSoftwareReadbackUnsupportedReasonForSpriteBatch(
  LoveSpriteBatch spriteBatch, {
  required Set<LoveGraphicsSurfaceSnapshot> visitedSurfaces,
  required Set<LoveImage> visitedImages,
}) {
  for (final sprite in spriteBatch.spritesToDraw()) {
    final reason = _loveSoftwareReadbackUnsupportedReasonForImage(
      resolveDrawableImageForLayer(spriteBatch.texture, layer: sprite.layer),
      visitedSurfaces: visitedSurfaces,
      visitedImages: visitedImages,
    );
    if (reason != null) {
      return reason;
    }
  }

  return null;
}

/// Returns the first readback blocker reachable from [image], if any.
String? _loveSoftwareReadbackUnsupportedReasonForImage(
  LoveImage? image, {
  required Set<LoveGraphicsSurfaceSnapshot> visitedSurfaces,
  required Set<LoveImage> visitedImages,
}) {
  if (image == null || !visitedImages.add(image)) {
    return null;
  }

  if (image case final LoveCanvasSnapshot snapshot) {
    return _loveSoftwareReadbackUnsupportedReasonForSnapshot(
      snapshot.surface,
      visitedSurfaces: visitedSurfaces,
      visitedImages: visitedImages,
    );
  }

  if (image.sliceImages case final List<LoveImage> slices?) {
    for (final slice in slices) {
      final reason = _loveSoftwareReadbackUnsupportedReasonForImage(
        slice,
        visitedSurfaces: visitedSurfaces,
        visitedImages: visitedImages,
      );
      if (reason != null) {
        return reason;
      }
    }
  }

  return null;
}

/// Returns the texture image currently referenced by [mesh], if one exists.
LoveImage? _loveSoftwareReadbackMeshTextureImage(LoveMesh mesh) {
  return switch (mesh.textureObject) {
    final LoveCanvas canvas => canvas.snapshot(),
    final LoveImage image => image,
    _ => null,
  };
}
