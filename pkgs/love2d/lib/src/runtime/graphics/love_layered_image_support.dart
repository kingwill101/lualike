part of '../love_runtime.dart';

LoveImage? resolveDrawableImageForLayer(LoveImage image, {int? layer}) {
  if (layer == null) {
    return image;
  }

  return image.sliceImageAt(layer);
}
