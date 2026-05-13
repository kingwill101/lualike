part of '../love_api_bindings.dart';

final Expando<Future<ui.Image>> _videoSnapshotUiImageCache =
    Expando<Future<ui.Image>>('love2dVideoSnapshotUiImage');
final Expando<LoveVideoFrameSnapshot> _videoDrawableSnapshotCache =
    Expando<LoveVideoFrameSnapshot>('love2dVideoDrawableSnapshot');
final Expando<LoveImage> _videoDrawableImageCache = Expando<LoveImage>(
  'love2dVideoDrawableImage',
);

bool _canUseLiveVideoCommand(
  LoveRuntimeContext runtime,
  LoveVideo video, {
  required LoveQuad? quad,
}) {
  if (!video.hasLivePresentation) {
    return false;
  }

  final color = runtime.graphics.color.clamped();
  final blendMode = runtime.graphics.blendMode;
  final blendAlphaMode = runtime.graphics.blendAlphaMode;
  // Live video is presented through a host texture overlay instead of the
  // canvas-backed image path. Shader-bound and destination-aware states still
  // need the sampled-frame fallback because the current Flutter shader bridge
  // binds ui.Image samplers, not external video textures.
  return runtime.graphics.shader == null &&
      ((blendMode == LoveGraphicsBlendMode.alpha &&
              (blendAlphaMode == LoveGraphicsBlendAlphaMode.alphaMultiply ||
                  blendAlphaMode ==
                      LoveGraphicsBlendAlphaMode.premultiplied)) ||
          ((blendMode == LoveGraphicsBlendMode.replace ||
                  blendMode == LoveGraphicsBlendMode.none) &&
              color.a == 1.0)) &&
      runtime.graphics.colorMask.allEnabled &&
      (quad == null || quad.layer == 0);
}

Future<LoveImage?> _snapshotDrawableImageForVideo(
  LoveRuntimeContext runtime,
  LoveVideo video,
) async {
  if (!video.hasFrameProvider) {
    throw LuaError(
      'love.graphics.draw does not yet support drawing Video objects in the current runtime',
    );
  }

  final snapshot = await video.snapshotFrame();
  if (snapshot == null) {
    return null;
  }

  final cachedSnapshot = _videoDrawableSnapshotCache[video];
  final cachedImage = _videoDrawableImageCache[video];
  if (identical(cachedSnapshot, snapshot) && cachedImage != null) {
    if (cachedImage.filter == video.filter) {
      return cachedImage;
    }

    final updatedImage = cachedImage.copyWith(filter: video.filter);
    _videoDrawableImageCache[video] = updatedImage;
    return updatedImage;
  }

  final resolvedImage = await _buildDrawableImageForVideo(video, snapshot);
  _videoDrawableSnapshotCache[video] = snapshot;
  _videoDrawableImageCache[video] = resolvedImage;
  _scheduleVideoDrawableImageDisposal(runtime, cachedImage, resolvedImage);
  return resolvedImage;
}

Future<ui.Image> _videoSnapshotToUiImage(LoveVideoFrameSnapshot snapshot) {
  final cached = _videoSnapshotUiImageCache[snapshot];
  if (cached != null) {
    return cached;
  }

  final completer = Completer<ui.Image>();
  final pixelFormat = switch (snapshot.pixelFormat) {
    LoveVideoFramePixelFormat.bgra8888 => ui.PixelFormat.bgra8888,
    LoveVideoFramePixelFormat.rgba8888 => ui.PixelFormat.rgba8888,
  };
  ui.decodeImageFromPixels(
    snapshot.bytes,
    snapshot.width,
    snapshot.height,
    pixelFormat,
    completer.complete,
    rowBytes: snapshot.rowBytes,
  );

  late final Future<ui.Image> future;
  future = completer.future.then(
    (image) => image,
    onError: (Object error, StackTrace stackTrace) {
      if (identical(_videoSnapshotUiImageCache[snapshot], future)) {
        _videoSnapshotUiImageCache[snapshot] = null;
      }
      return Future<ui.Image>.error(error, stackTrace);
    },
  );
  _videoSnapshotUiImageCache[snapshot] = future;
  return future;
}

Uint8List _videoSnapshotToRgba(LoveVideoFrameSnapshot snapshot) {
  return switch (snapshot.pixelFormat) {
    LoveVideoFramePixelFormat.bgra8888 => _bgraBytesToRgba(snapshot),
    LoveVideoFramePixelFormat.rgba8888 => _rgbaBytesWithTightRows(snapshot),
  };
}

Matrix4 _videoDrawTransform(
  LoveVideo video,
  List<Object?> args, {
  required int transformIndex,
  required String symbol,
}) {
  final transform = _matrixFromTransformArgumentOrStandardTransform(
    args,
    transformIndex,
    symbol,
  );
  final scaleX = video.pixelWidth <= 0 ? 1.0 : video.width / video.pixelWidth;
  final scaleY = video.pixelHeight <= 0
      ? 1.0
      : video.height / video.pixelHeight;
  if (scaleX != 1.0 || scaleY != 1.0) {
    transform.scaleByDouble(scaleX, scaleY, 1.0, 1.0);
  }
  return transform;
}

Uint8List _bgraBytesToRgba(LoveVideoFrameSnapshot snapshot) {
  final rgba = Uint8List(snapshot.width * snapshot.height * 4);
  for (var y = 0; y < snapshot.height; y++) {
    final sourceRowOffset = y * snapshot.rowBytes;
    final targetRowOffset = y * snapshot.width * 4;
    for (var x = 0; x < snapshot.width; x++) {
      final sourceOffset = sourceRowOffset + (x * 4);
      final targetOffset = targetRowOffset + (x * 4);
      rgba[targetOffset] = snapshot.bytes[sourceOffset + 2];
      rgba[targetOffset + 1] = snapshot.bytes[sourceOffset + 1];
      rgba[targetOffset + 2] = snapshot.bytes[sourceOffset];
      rgba[targetOffset + 3] = snapshot.bytes[sourceOffset + 3];
    }
  }
  return rgba;
}

Uint8List _rgbaBytesWithTightRows(LoveVideoFrameSnapshot snapshot) {
  if (snapshot.rowBytes == snapshot.width * 4) {
    return Uint8List.fromList(snapshot.bytes);
  }

  final tight = Uint8List(snapshot.width * snapshot.height * 4);
  for (var y = 0; y < snapshot.height; y++) {
    final sourceOffset = y * snapshot.rowBytes;
    final targetOffset = y * snapshot.width * 4;
    tight.setRange(
      targetOffset,
      targetOffset + (snapshot.width * 4),
      snapshot.bytes,
      sourceOffset,
    );
  }
  return tight;
}

Future<LoveImage> _buildDrawableImageForVideo(
  LoveVideo video,
  LoveVideoFrameSnapshot snapshot,
) async {
  try {
    final uiImage = await _videoSnapshotToUiImage(snapshot);
    return LoveImage(
      source: '${video.stream.filename}#frame',
      width: snapshot.width,
      height: snapshot.height,
      pixelWidth: snapshot.width,
      pixelHeight: snapshot.height,
      filter: video.filter,
      nativeImage: uiImage,
    );
  } catch (_) {}

  final rgbaBytes = _videoSnapshotToRgba(snapshot);

  return LoveImage(
    source: '${video.stream.filename}#frame',
    width: snapshot.width,
    height: snapshot.height,
    pixelWidth: snapshot.width,
    pixelHeight: snapshot.height,
    filter: video.filter,
    imageData: LoveImageData.fromRgbaBytes(
      width: snapshot.width,
      height: snapshot.height,
      bytes: rgbaBytes,
    ),
    preferImageDataRendering: true,
  );
}

void _releaseCachedDrawableImageForVideo(
  LoveRuntimeContext runtime,
  LoveVideo video,
) {
  _videoDrawableSnapshotCache[video] = null;
  final cachedImage = _videoDrawableImageCache[video];
  if (cachedImage == null) {
    return;
  }

  _videoDrawableImageCache[video] = null;
  _scheduleVideoDrawableImageDisposal(runtime, cachedImage, null);
}

void _scheduleVideoDrawableImageDisposal(
  LoveRuntimeContext runtime,
  LoveImage? previousImage,
  LoveImage? nextImage,
) {
  final previousNativeImage = previousImage?.nativeImage;
  if (previousNativeImage is! ui.Image) {
    return;
  }

  final nextNativeImage = nextImage?.nativeImage;
  if (identical(previousNativeImage, nextNativeImage)) {
    return;
  }

  runtime.graphics.scheduleBeginFrameCleanup(() {
    previousNativeImage.dispose();
  });
}
