import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:love2d/love2d.dart';

const LoveGraphicsDefaultFilter nearestLoveGraphicsDefaultFilter =
    LoveGraphicsDefaultFilter(
      min: LoveGraphicsFilterMode.nearest,
      mag: LoveGraphicsFilterMode.nearest,
    );

Future<LoveImage> loveImageFromRgbaPixels({
  required String source,
  required int width,
  required int height,
  required Uint8List pixels,
  LoveGraphicsDefaultFilter filter = nearestLoveGraphicsDefaultFilter,
  bool preferImageDataRendering = false,
}) async {
  return LoveImage(
    source: source,
    width: width,
    height: height,
    filter: filter,
    imageData: _loveImageDataFromRgbaPixels(pixels, width, height),
    preferImageDataRendering: preferImageDataRendering,
    nativeImage: await uiImageFromRgbaPixels(pixels, width, height),
  );
}

Future<ui.Image> uiImageFromRgbaPixels(
  Uint8List pixels,
  int width,
  int height,
) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

({int r, int g, int b, int a}) rgbaPixelAt(
  Uint8List pixels,
  int width,
  int x,
  int y,
) {
  final offset = ((y * width) + x) * 4;
  return (
    r: pixels[offset],
    g: pixels[offset + 1],
    b: pixels[offset + 2],
    a: pixels[offset + 3],
  );
}

LoveImageData _loveImageDataFromRgbaPixels(
  Uint8List pixels,
  int width,
  int height,
) {
  if (pixels.length != width * height * 4) {
    throw ArgumentError.value(
      pixels.length,
      'pixels.length',
      'Expected width * height * 4 RGBA bytes.',
    );
  }

  final imageData = LoveImageData(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = ((y * width) + x) * 4;
      imageData.setPixel(
        x,
        y,
        LoveColor(
          pixels[offset] / 255,
          pixels[offset + 1] / 255,
          pixels[offset + 2] / 255,
          pixels[offset + 3] / 255,
        ),
      );
    }
  }
  return imageData;
}
