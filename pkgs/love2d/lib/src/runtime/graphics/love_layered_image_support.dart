part of '../love_runtime.dart';

/// Resolves the drawable image slice for [image] and an optional [layer].
///
/// When [layer] is omitted, this returns [image] unchanged. Otherwise it
/// returns the indexed layer image when one exists.
LoveImage? resolveDrawableImageForLayer(LoveImage image, {int? layer}) {
  if (layer == null) {
    return image;
  }

  return image.sliceImageAt(layer);
}
