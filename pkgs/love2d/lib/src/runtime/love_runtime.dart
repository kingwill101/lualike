library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert' as convert;
import 'dart:math' as math;
import 'dart:typed_data' show ByteData, BytesBuilder, Endian, Uint8List;

import 'package:archive/archive.dart';
import 'package:image/image.dart' as package_image;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flame_forge2d/flame_forge2d.dart' as forge2d;
import 'package:lualike/lualike.dart' show LuaRuntime, NumberUtils, Value;
import 'package:lualike/src/number_limits.dart' show NumberLimits;
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

part 'data/love_data_support.dart';
part 'data/love_data_pointer_support.dart';
part 'input/love_input_support.dart';
part 'input/love_joystick_support.dart';
part 'input/love_touch_support.dart';
part 'event/love_event_support.dart';
part 'font/love_font_support.dart';
part 'font/love_default_font_support.dart';
part 'font/love_true_type_support.dart';
part 'audio/love_audio_support.dart';
part 'audio/love_audio_effect_support.dart';
part 'audio/love_audio_recording_support.dart';
part 'graphics/love_mesh_support.dart';
part 'graphics/love_particle_system_support.dart';
part 'graphics/love_canvas_rasterizer.dart';
part 'graphics/love_shader_support.dart';
part 'graphics/love_sprite_batch_support.dart';
part 'math/love_math_support.dart';
part 'math/love_random_support.dart';
part 'physics/love_physics_callback_support.dart';
part 'physics/love_physics_contact_support.dart';
part 'physics/love_physics_contact_filter_support.dart';
part 'physics/love_physics_joint_support.dart';
part 'physics/love_physics_support.dart';
part 'sound/love_sound_support.dart';
part 'system/love_system_support.dart';
part 'thread/love_thread_support.dart';
part 'video/love_video_support.dart';
part 'window/love_window_support.dart';

const int loveVersionMajor = 11;
const int loveVersionMinor = 5;
const int loveVersionRevision = 0;
const String loveVersionCodename = 'Mysterious Mysteries';
const String loveVersionString = '11.5';
const List<String> loveCompatibleVersions = <String>[
  '11.5.0',
  '11.0.0',
  '11.1.0',
  '11.2.0',
  '11.3.0',
  '11.4.0',
];

enum LoveGraphicsDrawMode { fill, line }

enum LoveGraphicsStackType { transform, all }

enum LoveGraphicsArcMode { open, closed, pie }

enum LoveGraphicsLineStyle { smooth, rough }

enum LoveGraphicsLineJoin { none, miter, bevel }

enum LoveGraphicsBlendMode {
  alpha,
  add,
  subtract,
  multiply,
  lighten,
  darken,
  screen,
  replace,
  none,
}

enum LoveGraphicsBlendAlphaMode { alphaMultiply, premultiplied }

enum LoveGraphicsFilterMode { linear, nearest }

enum LoveGraphicsWrapMode { clamp, repeat, mirroredRepeat, clampZero }

enum LoveCanvasMipmapMode { none, auto, manual }

enum LoveGraphicsVertexWinding { ccw, cw }

enum LoveGraphicsCullMode { none, front, back }

enum LoveGraphicsCompareMode {
  equal,
  notequal,
  less,
  lequal,
  gequal,
  greater,
  never,
  always,
}

class LoveGraphicsDefaultFilter {
  const LoveGraphicsDefaultFilter({
    this.min = LoveGraphicsFilterMode.linear,
    this.mag = LoveGraphicsFilterMode.linear,
    this.anisotropy = 1.0,
  });

  static const LoveGraphicsDefaultFilter standard = LoveGraphicsDefaultFilter();

  final LoveGraphicsFilterMode min;
  final LoveGraphicsFilterMode mag;
  final double anisotropy;

  LoveGraphicsDefaultFilter copyWith({
    LoveGraphicsFilterMode? min,
    LoveGraphicsFilterMode? mag,
    double? anisotropy,
  }) {
    return LoveGraphicsDefaultFilter(
      min: min ?? this.min,
      mag: mag ?? this.mag,
      anisotropy: anisotropy ?? this.anisotropy,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LoveGraphicsDefaultFilter &&
        other.min == min &&
        other.mag == mag &&
        other.anisotropy == anisotropy;
  }

  @override
  int get hashCode => Object.hash(min, mag, anisotropy);
}

class LoveGraphicsWrap {
  const LoveGraphicsWrap({
    this.horizontal = LoveGraphicsWrapMode.clamp,
    this.vertical = LoveGraphicsWrapMode.clamp,
    this.depth = LoveGraphicsWrapMode.clamp,
  });

  static const LoveGraphicsWrap clamp = LoveGraphicsWrap();

  final LoveGraphicsWrapMode horizontal;
  final LoveGraphicsWrapMode vertical;
  final LoveGraphicsWrapMode depth;

  LoveGraphicsWrap copyWith({
    LoveGraphicsWrapMode? horizontal,
    LoveGraphicsWrapMode? vertical,
    LoveGraphicsWrapMode? depth,
  }) {
    return LoveGraphicsWrap(
      horizontal: horizontal ?? this.horizontal,
      vertical: vertical ?? this.vertical,
      depth: depth ?? this.depth,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LoveGraphicsWrap &&
        other.horizontal == horizontal &&
        other.vertical == vertical &&
        other.depth == depth;
  }

  @override
  int get hashCode => Object.hash(horizontal, vertical, depth);
}

class LoveGraphicsColorMask {
  const LoveGraphicsColorMask({
    this.red = true,
    this.green = true,
    this.blue = true,
    this.alpha = true,
  });

  static const LoveGraphicsColorMask all = LoveGraphicsColorMask();

  final bool red;
  final bool green;
  final bool blue;
  final bool alpha;

  bool get allEnabled => red && green && blue && alpha;

  @override
  bool operator ==(Object other) {
    return other is LoveGraphicsColorMask &&
        other.red == red &&
        other.green == green &&
        other.blue == blue &&
        other.alpha == alpha;
  }

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);
}

class LoveScissorRect {
  const LoveScissorRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  LoveScissorRect intersect(LoveScissorRect other) {
    final left = x > other.x ? x : other.x;
    final top = y > other.y ? y : other.y;
    final right = (x + width) < (other.x + other.width)
        ? (x + width)
        : (other.x + other.width);
    final bottom = (y + height) < (other.y + other.height)
        ? (y + height)
        : (other.y + other.height);

    return LoveScissorRect(
      x: left,
      y: top,
      width: right > left ? right - left : 0,
      height: bottom > top ? bottom - top : 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LoveScissorRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

class LoveImage {
  LoveImage({
    required this.source,
    required this.width,
    required this.height,
    int? pixelWidth,
    int? pixelHeight,
    this.dpiScale = 1.0,
    this.format = 'normal',
    this.readable = true,
    this.depth = 1,
    this.layerCount = 1,
    this.textureType = '2d',
    this.mipmapCount = 1,
    this.filter = LoveGraphicsDefaultFilter.standard,
    this.mipmapFilter,
    this.mipmapSharpness = 0.0,
    this.wrap = LoveGraphicsWrap.clamp,
    this.depthSampleMode,
    this.compressed = false,
    this.formatLinear = false,
    LoveImageData? imageData,
    List<LoveImageData>? imageDataMipmaps,
    this.preferImageDataRendering = false,
    this.nativeImage,
  }) : pixelWidth = pixelWidth ?? width,
       pixelHeight = pixelHeight ?? height,
       imageData =
           imageData ??
           (imageDataMipmaps == null || imageDataMipmaps.isEmpty
               ? null
               : imageDataMipmaps.first),
       imageDataMipmaps = imageDataMipmaps == null
           ? (imageData == null
                 ? null
                 : List<LoveImageData>.unmodifiable(<LoveImageData>[imageData]))
           : List<LoveImageData>.unmodifiable(imageDataMipmaps);

  final String source;
  final int width;
  final int height;
  final int pixelWidth;
  final int pixelHeight;
  final double dpiScale;
  final String format;
  final bool readable;
  final int depth;
  final int layerCount;
  final String textureType;
  final int mipmapCount;
  final LoveGraphicsDefaultFilter filter;
  final LoveGraphicsFilterMode? mipmapFilter;
  final double mipmapSharpness;
  final LoveGraphicsWrap wrap;
  final LoveGraphicsCompareMode? depthSampleMode;
  final bool compressed;
  final bool formatLinear;
  final LoveImageData? imageData;
  final List<LoveImageData>? imageDataMipmaps;
  final bool preferImageDataRendering;
  final Object? nativeImage;

  int pixelWidthAtMipmap([int mipmap = 1]) =>
      _mipmapDimension(pixelWidth, mipmap);

  int pixelHeightAtMipmap([int mipmap = 1]) =>
      _mipmapDimension(pixelHeight, mipmap);

  LoveImageData? imageDataAtMipmap([int mipmap = 1]) {
    final mipmaps = imageDataMipmaps;
    if (mipmaps == null || mipmap < 1 || mipmap > mipmaps.length) {
      return null;
    }
    return mipmaps[mipmap - 1];
  }

  LoveImage copyWith({
    String? source,
    int? width,
    int? height,
    int? pixelWidth,
    int? pixelHeight,
    double? dpiScale,
    String? format,
    bool? readable,
    int? depth,
    int? layerCount,
    String? textureType,
    int? mipmapCount,
    LoveGraphicsDefaultFilter? filter,
    bool clearMipmapFilter = false,
    LoveGraphicsFilterMode? mipmapFilter,
    double? mipmapSharpness,
    LoveGraphicsWrap? wrap,
    bool clearDepthSampleMode = false,
    LoveGraphicsCompareMode? depthSampleMode,
    bool? compressed,
    bool? formatLinear,
    LoveImageData? imageData,
    List<LoveImageData>? imageDataMipmaps,
    bool? preferImageDataRendering,
    Object? nativeImage,
  }) {
    return LoveImage(
      source: source ?? this.source,
      width: width ?? this.width,
      height: height ?? this.height,
      pixelWidth: pixelWidth ?? this.pixelWidth,
      pixelHeight: pixelHeight ?? this.pixelHeight,
      dpiScale: dpiScale ?? this.dpiScale,
      format: format ?? this.format,
      readable: readable ?? this.readable,
      depth: depth ?? this.depth,
      layerCount: layerCount ?? this.layerCount,
      textureType: textureType ?? this.textureType,
      mipmapCount: mipmapCount ?? this.mipmapCount,
      filter: filter ?? this.filter,
      mipmapFilter: clearMipmapFilter
          ? null
          : (mipmapFilter ?? this.mipmapFilter),
      mipmapSharpness: mipmapSharpness ?? this.mipmapSharpness,
      wrap: wrap ?? this.wrap,
      depthSampleMode: clearDepthSampleMode
          ? null
          : (depthSampleMode ?? this.depthSampleMode),
      compressed: compressed ?? this.compressed,
      formatLinear: formatLinear ?? this.formatLinear,
      imageData: imageData ?? this.imageData,
      imageDataMipmaps: imageDataMipmaps ?? this.imageDataMipmaps,
      preferImageDataRendering:
          preferImageDataRendering ?? this.preferImageDataRendering,
      nativeImage: nativeImage ?? this.nativeImage,
    );
  }
}

class LoveGraphicsSurfaceSnapshot {
  const LoveGraphicsSurfaceSnapshot({
    required this.clearColor,
    required this.clearColorMask,
    required this.clearScissor,
    required this.commands,
  });

  final LoveColor clearColor;
  final LoveGraphicsColorMask clearColorMask;
  final LoveScissorRect? clearScissor;
  final List<LoveDrawCommand> commands;
}

class LoveGraphicsSurface {
  LoveGraphicsSurface({
    LoveColor? clearColor,
    LoveGraphicsColorMask? clearColorMask,
    LoveScissorRect? clearScissor,
  }) : _clearColor = (clearColor ?? const LoveColor(0, 0, 0, 0)).clamped(),
       _clearColorMask = clearColorMask ?? LoveGraphicsColorMask.all,
       _clearScissor = clearScissor;

  final List<LoveDrawCommand> _commands = <LoveDrawCommand>[];
  LoveColor _clearColor;
  LoveGraphicsColorMask _clearColorMask;
  LoveScissorRect? _clearScissor;

  LoveColor get clearColor => _clearColor;

  LoveGraphicsColorMask get clearColorMask => _clearColorMask;

  LoveScissorRect? get clearScissor => _clearScissor;

  List<LoveDrawCommand> get commands =>
      List<LoveDrawCommand>.unmodifiable(_commands);

  void begin({
    required LoveColor clearColor,
    required LoveGraphicsColorMask clearColorMask,
    LoveScissorRect? clearScissor,
  }) {
    _commands.clear();
    _clearColor = clearColor.clamped();
    _clearColorMask = clearColorMask;
    _clearScissor = clearScissor;
  }

  void clear({
    required LoveColor clearColor,
    required LoveGraphicsColorMask clearColorMask,
    LoveScissorRect? clearScissor,
  }) {
    begin(
      clearColor: clearColor,
      clearColorMask: clearColorMask,
      clearScissor: clearScissor,
    );
  }

  void addCommand(LoveDrawCommand command) {
    _commands.add(command);
  }

  LoveGraphicsSurfaceSnapshot snapshot() {
    return LoveGraphicsSurfaceSnapshot(
      clearColor: _clearColor,
      clearColorMask: _clearColorMask,
      clearScissor: _clearScissor,
      commands: List<LoveDrawCommand>.unmodifiable(
        List<LoveDrawCommand>.from(_commands),
      ),
    );
  }
}

class LoveCanvas extends LoveImage {
  LoveCanvas({
    required super.source,
    required super.width,
    required super.height,
    required double dpiScale,
    LoveGraphicsDefaultFilter filter = LoveGraphicsDefaultFilter.standard,
    LoveGraphicsWrap wrap = LoveGraphicsWrap.clamp,
    String format = 'normal',
    bool readable = true,
    super.compressed = false,
    super.formatLinear = false,
    super.nativeImage,
    this.msaa = 0,
    this.mipmapMode = LoveCanvasMipmapMode.none,
    LoveGraphicsSurface? surface,
    String textureType = '2d',
    int layerCount = 1,
    int depth = 1,
  }) : _filter = filter,
       _mipmapFilter = mipmapMode == LoveCanvasMipmapMode.none
           ? null
           : LoveGraphicsFilterMode.linear,
       _mipmapSharpness = 0.0,
       _wrap = wrap,
       _depthSampleMode = null,
       _surface = surface ?? LoveGraphicsSurface(),
       super(
         pixelWidth: (width * dpiScale).round(),
         pixelHeight: (height * dpiScale).round(),
         dpiScale: dpiScale,
         format: format,
         readable: readable,
         textureType: textureType,
         layerCount: layerCount,
         depth: depth,
         mipmapCount: mipmapMode == LoveCanvasMipmapMode.none
             ? 1
             : _mipmapCountForDimensions(
                 (width * dpiScale).round(),
                 (height * dpiScale).round(),
               ),
         filter: filter,
         mipmapFilter: mipmapMode == LoveCanvasMipmapMode.none
             ? null
             : LoveGraphicsFilterMode.linear,
         mipmapSharpness: 0.0,
         wrap: wrap,
         depthSampleMode: null,
       );

  LoveGraphicsDefaultFilter _filter;
  LoveGraphicsFilterMode? _mipmapFilter;
  double _mipmapSharpness;
  LoveGraphicsWrap _wrap;
  LoveGraphicsCompareMode? _depthSampleMode;
  final LoveGraphicsSurface _surface;

  final int msaa;
  final LoveCanvasMipmapMode mipmapMode;
  int mipmapGenerations = 0;

  @override
  LoveGraphicsDefaultFilter get filter => _filter;

  @override
  LoveGraphicsWrap get wrap => _wrap;

  @override
  LoveGraphicsFilterMode? get mipmapFilter => _mipmapFilter;

  @override
  double get mipmapSharpness => _mipmapSharpness;

  @override
  LoveGraphicsCompareMode? get depthSampleMode => _depthSampleMode;

  LoveGraphicsSurface get surface => _surface;

  void setFilterValue(LoveGraphicsDefaultFilter value) {
    _filter = value;
  }

  void setWrapValue(LoveGraphicsWrap value) {
    _wrap = value;
  }

  void setMipmapFilterValue(LoveGraphicsFilterMode? mode, double sharpness) {
    _mipmapFilter = mode;
    _mipmapSharpness = sharpness;
  }

  void setDepthSampleModeValue(LoveGraphicsCompareMode? value) {
    _depthSampleMode = value;
  }

  void generateMipmaps() {
    mipmapGenerations++;
  }

  LoveImageData readbackImageData({
    int mipmap = 1,
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  }) {
    final imageData = snapshot().rasterizedImageData(mipmap);
    final regionWidth = width ?? imageData.width;
    final regionHeight = height ?? imageData.height;
    if (x == 0 &&
        y == 0 &&
        regionWidth == imageData.width &&
        regionHeight == imageData.height) {
      return imageData;
    }
    return imageData.copyRegion(
      x: x,
      y: y,
      width: regionWidth,
      height: regionHeight,
    );
  }

  LoveCanvasSnapshot snapshot() {
    return LoveCanvasSnapshot(
      source: source,
      width: width,
      height: height,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      dpiScale: dpiScale,
      format: format,
      readable: readable,
      depth: depth,
      layerCount: layerCount,
      textureType: textureType,
      mipmapCount: mipmapCount,
      filter: filter,
      mipmapFilter: mipmapFilter,
      mipmapSharpness: mipmapSharpness,
      wrap: wrap,
      depthSampleMode: depthSampleMode,
      compressed: compressed,
      formatLinear: formatLinear,
      nativeImage: nativeImage,
      msaa: msaa,
      mipmapMode: mipmapMode,
      surface: _surface.snapshot(),
    );
  }
}

class LoveCanvasSnapshot extends LoveImage {
  LoveCanvasSnapshot({
    required super.source,
    required super.width,
    required super.height,
    required super.pixelWidth,
    required super.pixelHeight,
    required super.dpiScale,
    required super.format,
    required super.readable,
    required super.depth,
    required super.layerCount,
    required super.textureType,
    required super.mipmapCount,
    required super.filter,
    required super.mipmapFilter,
    required super.mipmapSharpness,
    required super.wrap,
    required super.depthSampleMode,
    required super.compressed,
    required super.formatLinear,
    required super.nativeImage,
    required this.surface,
    required this.msaa,
    required this.mipmapMode,
  });

  final LoveGraphicsSurfaceSnapshot surface;
  final int msaa;
  final LoveCanvasMipmapMode mipmapMode;

  LoveImageData rasterizedImageData([int mipmap = 1]) {
    if (mipmap < 1) {
      throw RangeError.range(mipmap, 1, null, 'mipmap');
    }

    final imageData = LoveCanvasRasterizer.rasterizeSurface(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      format: format,
      snapshot: surface,
    );
    if (mipmap == 1) {
      return imageData;
    }
    final mipmaps = imageData.generateMipmaps();
    final level = math.min(mipmap, mipmaps.length) - 1;
    return mipmaps[level];
  }
}

class LoveImageData {
  LoveImageData({
    required this.width,
    required this.height,
    this.format = 'rgba8',
    LoveColor? fill,
  }) : _pixels = List<LoveColor>.filled(
         width * height,
         (fill ?? const LoveColor(0, 0, 0, 0)).clamped(),
         growable: false,
       );

  factory LoveImageData.fromRgbaBytes({
    required int width,
    required int height,
    String format = 'rgba8',
    required Uint8List bytes,
  }) {
    final expectedLength = width * height * 4;
    if (bytes.length < expectedLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Expected at least $expectedLength RGBA bytes for a ${width}x$height image',
      );
    }

    final imageData = LoveImageData(
      width: width,
      height: height,
      format: format,
    );
    for (var index = 0; index < width * height; index++) {
      final offset = index * 4;
      imageData._pixels[index] = LoveColor(
        bytes[offset] / 255,
        bytes[offset + 1] / 255,
        bytes[offset + 2] / 255,
        bytes[offset + 3] / 255,
      );
    }
    return imageData;
  }

  factory LoveImageData.fromPackageImage(
    package_image.Image image, {
    String format = 'rgba8',
  }) {
    final imageData = LoveImageData(
      width: image.width,
      height: image.height,
      format: format,
    );

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        imageData._pixels[(y * image.width) + x] = LoveColor(
          pixel.rNormalized.toDouble(),
          pixel.gNormalized.toDouble(),
          pixel.bNormalized.toDouble(),
          pixel.aNormalized.toDouble(),
        );
      }
    }

    return imageData;
  }

  factory LoveImageData.decodeEncodedBytes({
    required List<int> bytes,
    String? source,
    String format = 'rgba8',
  }) {
    final encodedBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final decoded = source == null
        ? package_image.decodeImage(encodedBytes)
        : package_image.decodeNamedImage(source, encodedBytes);
    if (decoded == null) {
      throw ArgumentError(
        'Unable to decode image data${source == null ? '' : ' from "$source"'}',
      );
    }

    return LoveImageData.fromPackageImage(decoded, format: format);
  }

  final int width;
  final int height;
  final String format;
  final List<LoveColor> _pixels;

  int get length => _pixels.length;

  LoveColor getPixel(int x, int y) {
    _validateCoordinates(x, y);
    return _pixels[(y * width) + x];
  }

  void setPixel(int x, int y, LoveColor color) {
    _validateCoordinates(x, y);
    _pixels[(y * width) + x] = color.clamped();
  }

  LoveImageData clone() => copyRegion(x: 0, y: 0, width: width, height: height);

  package_image.Image toPackageImage() {
    final image = package_image.Image(
      width: width,
      height: height,
      numChannels: 4,
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = getPixel(x, y);
        image.setPixelRgba(
          x,
          y,
          (pixel.r * 255).round(),
          (pixel.g * 255).round(),
          (pixel.b * 255).round(),
          (pixel.a * 255).round(),
        );
      }
    }

    return image;
  }

  Uint8List encode(String format) {
    final normalizedFormat = format.toLowerCase();
    final image = toPackageImage();

    return switch (normalizedFormat) {
      'png' => package_image.encodePng(image),
      'jpg' => package_image.encodeJpg(image),
      'bmp' => package_image.encodeBmp(image),
      'tga' => package_image.encodeTga(image),
      _ => throw ArgumentError.value(
        format,
        'format',
        'Unsupported encoded image format',
      ),
    };
  }

  List<LoveImageData> generateMipmaps() {
    final levels = <LoveImageData>[clone()];
    if (width == 1 && height == 1) {
      return List<LoveImageData>.unmodifiable(levels);
    }

    var current = toPackageImage();
    while (current.width > 1 || current.height > 1) {
      final nextWidth = math.max(1, current.width ~/ 2);
      final nextHeight = math.max(1, current.height ~/ 2);
      current = package_image.copyResize(
        current,
        width: nextWidth,
        height: nextHeight,
        interpolation: package_image.Interpolation.average,
      );
      levels.add(LoveImageData.fromPackageImage(current, format: format));
    }

    return List<LoveImageData>.unmodifiable(levels);
  }

  LoveImageData copyRegion({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final imageData = LoveImageData(
      width: width,
      height: height,
      format: format,
    );

    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        imageData.setPixel(column, row, getPixel(x + column, y + row));
      }
    }

    return imageData;
  }

  void _validateCoordinates(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      throw RangeError('Pixel coordinates out of bounds: ($x, $y)');
    }
  }
}

class LoveCompressedImageMipmap {
  const LoveCompressedImageMipmap({
    required this.width,
    required this.height,
    required this.offset,
    required this.size,
  });

  final int width;
  final int height;
  final int offset;
  final int size;
}

class LoveCompressedImageData {
  LoveCompressedImageData({
    required this.source,
    required List<int> bytes,
    required this.format,
    required this.srgb,
    required List<LoveCompressedImageMipmap> mipmaps,
  }) : bytes = Uint8List.fromList(bytes),
       mipmaps = List<LoveCompressedImageMipmap>.unmodifiable(mipmaps) {
    if (mipmaps.isEmpty) {
      throw ArgumentError.value(
        mipmaps,
        'mipmaps',
        'Compressed image data must contain at least one mipmap level',
      );
    }
  }

  final String source;
  final Uint8List bytes;
  final String format;
  final bool srgb;
  final List<LoveCompressedImageMipmap> mipmaps;

  int get width => mipmaps.first.width;

  int get height => mipmaps.first.height;

  int get mipmapCount => mipmaps.length;

  LoveCompressedImageMipmap mipmap(int level) {
    if (level < 1 || level > mipmaps.length) {
      throw RangeError.range(
        level,
        1,
        mipmaps.length,
        'level',
        'Mipmap level does not exist',
      );
    }

    return mipmaps[level - 1];
  }

  int getWidth([int level = 1]) => mipmap(level).width;

  int getHeight([int level = 1]) => mipmap(level).height;

  LoveCompressedImageData clone() {
    return LoveCompressedImageData(
      source: source,
      bytes: bytes,
      format: format,
      srgb: srgb,
      mipmaps: mipmaps,
    );
  }
}

class LoveQuad {
  LoveQuad({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.textureWidth,
    required this.textureHeight,
  });

  double x;
  double y;
  double width;
  double height;
  double textureWidth;
  double textureHeight;

  LoveQuad copy() {
    return LoveQuad(
      x: x,
      y: y,
      width: width,
      height: height,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
    );
  }

  void setViewport(double x, double y, double width, double height) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

class LoveTransform {
  LoveTransform([Matrix4? matrix])
    : _matrix = matrix == null ? Matrix4.identity() : Matrix4.copy(matrix);

  factory LoveTransform.identity() => LoveTransform();

  factory LoveTransform.transformation({
    required double x,
    required double y,
    required double angle,
    required double scaleX,
    required double scaleY,
    required double originX,
    required double originY,
    required double shearX,
    required double shearY,
  }) {
    return LoveTransform(
      _matrixFromTransformation(
        x: x,
        y: y,
        angle: angle,
        scaleX: scaleX,
        scaleY: scaleY,
        originX: originX,
        originY: originY,
        shearX: shearX,
        shearY: shearY,
      ),
    );
  }

  Matrix4 _matrix;

  Matrix4 get matrix => _matrix;

  LoveTransform clone() => LoveTransform(_matrix);

  LoveTransform inverse() {
    final inverse = Matrix4.copy(_matrix);
    final determinant = inverse.invert();
    if (determinant == 0) {
      throw StateError('Transform is not invertible');
    }
    return LoveTransform(inverse);
  }

  void apply(LoveTransform other) {
    _matrix.multiply(other.matrix);
  }

  void translate(double x, double y) {
    _matrix.translateByDouble(x, y, 0, 1);
  }

  void rotate(double angle) {
    _matrix.rotateZ(angle);
  }

  void scale(double x, [double? y]) {
    _matrix.scaleByDouble(x, y ?? x, 1, 1);
  }

  void shear(double kx, double ky) {
    final shear = Matrix4.identity()
      ..setEntry(0, 1, kx)
      ..setEntry(1, 0, ky);
    _matrix.multiply(shear);
  }

  void reset() {
    _matrix = Matrix4.identity();
  }

  void setTransformation({
    required double x,
    required double y,
    required double angle,
    required double scaleX,
    required double scaleY,
    required double originX,
    required double originY,
    required double shearX,
    required double shearY,
  }) {
    _matrix = _matrixFromTransformation(
      x: x,
      y: y,
      angle: angle,
      scaleX: scaleX,
      scaleY: scaleY,
      originX: originX,
      originY: originY,
      shearX: shearX,
      shearY: shearY,
    );
  }

  ({double x, double y}) transformPoint(double x, double y) {
    final point = _matrix.transformed3(Vector3(x, y, 0));
    return (x: point.x, y: point.y);
  }

  ({double x, double y}) inverseTransformPoint(double x, double y) {
    final inverse = Matrix4.copy(_matrix);
    final determinant = inverse.invert();
    if (determinant == 0) {
      throw StateError('Transform is not invertible');
    }

    final point = inverse.transformed3(Vector3(x, y, 0));
    return (x: point.x, y: point.y);
  }

  List<double> getMatrixRowMajor() {
    final storage = _matrix.storage;
    return <double>[
      storage[0],
      storage[4],
      storage[8],
      storage[12],
      storage[1],
      storage[5],
      storage[9],
      storage[13],
      storage[2],
      storage[6],
      storage[10],
      storage[14],
      storage[3],
      storage[7],
      storage[11],
      storage[15],
    ];
  }

  void setMatrixFromColumnMajor(List<double> elements) {
    if (elements.length != 16) {
      throw ArgumentError.value(
        elements.length,
        'elements.length',
        'Expected 16 matrix elements',
      );
    }

    _matrix = Matrix4(
      elements[0],
      elements[1],
      elements[2],
      elements[3],
      elements[4],
      elements[5],
      elements[6],
      elements[7],
      elements[8],
      elements[9],
      elements[10],
      elements[11],
      elements[12],
      elements[13],
      elements[14],
      elements[15],
    );
  }

  void setMatrixFromRowMajor(List<double> elements) {
    if (elements.length != 16) {
      throw ArgumentError.value(
        elements.length,
        'elements.length',
        'Expected 16 matrix elements',
      );
    }

    setMatrixFromColumnMajor(<double>[
      elements[0],
      elements[4],
      elements[8],
      elements[12],
      elements[1],
      elements[5],
      elements[9],
      elements[13],
      elements[2],
      elements[6],
      elements[10],
      elements[14],
      elements[3],
      elements[7],
      elements[11],
      elements[15],
    ]);
  }

  bool get isAffine2DTransform {
    final storage = _matrix.storage;
    return storage[2] == 0 &&
        storage[3] == 0 &&
        storage[6] == 0 &&
        storage[7] == 0 &&
        storage[8] == 0 &&
        storage[9] == 0 &&
        storage[10] == 1 &&
        storage[11] == 0 &&
        storage[14] == 0 &&
        storage[15] == 1;
  }
}

typedef LoveFontWrapResult = ({double width, List<String> lines});
typedef LoveFontMeasureWidth = double Function(String text);
typedef LoveFontWrapText =
    LoveFontWrapResult Function(String text, double wrapLimit);
typedef LoveFontSupportsCodepoint = bool Function(int codepoint);

const int _loveTabCodepoint = 0x09;
const int _loveSpacesPerTab = 4;

class LoveFont {
  LoveFont({
    required this.size,
    this.family,
    this.source,
    this.fontType = 'truetype',
    String? dataType,
    this.glyphs,
    this.glyphAdvance,
    Map<int, double>? glyphAdvances,
    Map<int, double>? glyphKernings,
    this.extraSpacing = 0.0,
    this.hinting = 'normal',
    this.dpiScale = 1.0,
    this.lineHeight = 1.0,
    this.heightOverride,
    this.ascentOverride,
    this.descentOverride,
    this.missingGlyphAdvance,
    this.syntheticTabAdvance,
    this.filter = LoveGraphicsDefaultFilter.standard,
    List<LoveFont>? fallbacks,
    LoveFontMeasureWidth? measureWidthCallback,
    LoveFontWrapText? wrapTextCallback,
    LoveFontSupportsCodepoint? supportsCodepointCallback,
    this.isImplicitDefaultGraphicsFont = false,
  }) : dataType = dataType ?? fontType,
       glyphAdvances = glyphAdvances == null
           ? null
           : Map<int, double>.unmodifiable(
               Map<int, double>.from(glyphAdvances),
             ),
       glyphKernings = glyphKernings == null
           ? null
           : Map<int, double>.unmodifiable(
               Map<int, double>.from(glyphKernings),
             ),
       _measureWidthCallback = measureWidthCallback,
       _wrapTextCallback = wrapTextCallback,
       _supportsCodepointCallback = supportsCodepointCallback,
       _fallbacks = fallbacks == null
           ? <LoveFont>[]
           : List<LoveFont>.from(fallbacks);

  static const String trueTypeFontType = 'truetype';
  static const String imageFontType = 'image';
  static const String bmFontDataType = 'bmfont';

  static String fontTypeForSource(String? source) {
    if (source == null || source.isEmpty) {
      return trueTypeFontType;
    }

    final dotIndex = source.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == source.length - 1) {
      return trueTypeFontType;
    }

    return switch (source.substring(dotIndex + 1).toLowerCase()) {
      'png' || 'bmp' || 'tga' || 'jpg' || 'jpeg' => imageFontType,
      _ => trueTypeFontType,
    };
  }

  static String fontDataTypeForSource(String? source) {
    if (source == null || source.isEmpty) {
      return trueTypeFontType;
    }

    final dotIndex = source.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == source.length - 1) {
      return trueTypeFontType;
    }

    return switch (source.substring(dotIndex + 1).toLowerCase()) {
      'fnt' => bmFontDataType,
      'png' || 'bmp' || 'tga' || 'jpg' || 'jpeg' => imageFontType,
      _ => trueTypeFontType,
    };
  }

  static const double defaultSize = 12.0;
  static LoveFont fallback() =>
      LoveFont(size: defaultSize, isImplicitDefaultGraphicsFont: true);

  double size;
  String? family;
  String? source;
  String fontType;
  String dataType;
  String? glyphs;
  double? glyphAdvance;
  Map<int, double>? glyphAdvances;
  Map<int, double>? glyphKernings;
  double extraSpacing;
  String hinting;
  double dpiScale;
  double lineHeight;
  double? heightOverride;
  double? ascentOverride;
  double? descentOverride;
  double? missingGlyphAdvance;
  double? syntheticTabAdvance;
  LoveGraphicsDefaultFilter filter;
  final bool isImplicitDefaultGraphicsFont;
  final LoveFontMeasureWidth? _measureWidthCallback;
  final LoveFontWrapText? _wrapTextCallback;
  final LoveFontSupportsCodepoint? _supportsCodepointCallback;
  final List<LoveFont> _fallbacks;
  final Map<int, double> _cachedGlyphAdvances = <int, double>{};
  final Map<int, double> _cachedGlyphKernings = <int, double>{};

  double get height => heightOverride ?? size;

  double get ascent => ascentOverride ?? (size * 0.8).roundToDouble();

  double get descent =>
      descentOverride ?? math.max(0, size - ascent).roundToDouble();

  double get baseline {
    if (ascent != 0) {
      return ascent;
    }

    if (dataType == trueTypeFontType) {
      return (height / 1.25).roundToDouble();
    }

    return 0.0;
  }

  List<LoveFont> get fallbacks => List<LoveFont>.unmodifiable(_fallbacks);

  bool get _hasSyntheticTabAdvance =>
      syntheticTabAdvance != null && syntheticTabAdvance! > 0;

  bool get _hasLocalGlyphLayoutData =>
      fontType == imageFontType ||
      glyphAdvances != null ||
      glyphKernings != null ||
      _hasSyntheticTabAdvance ||
      missingGlyphAdvance != null;

  bool get _requiresFallbackAwareLayout =>
      _hasLocalGlyphLayoutData ||
      (_supportsCodepointCallback != null && _fallbacks.isNotEmpty);

  double measureWidth(String text) {
    if (text.isEmpty) {
      return 0.0;
    }

    if (_requiresFallbackAwareLayout) {
      return _measureGlyphWidth(text);
    }

    final measureWidthCallback = _measureWidthCallback;
    if (measureWidthCallback != null) {
      var maxWidth = 0.0;
      for (final line in text.split('\n')) {
        final width = measureWidthCallback(line.replaceAll('\r', ''));
        if (width > maxWidth) {
          maxWidth = width;
        }
      }
      return maxWidth;
    }

    var maxWidth = 0.0;
    for (final line in text.split('\n')) {
      final width = line.replaceAll('\r', '').runes.length * size * 0.6;
      if (width > maxWidth) {
        maxWidth = width;
      }
    }
    return maxWidth;
  }

  double getKerning(Object? left, Object? right) {
    final leftGlyph = _glyphCodepoint(left);
    final rightGlyph = _glyphCodepoint(right);
    if (leftGlyph == null || rightGlyph == null) {
      return 0.0;
    }

    return _glyphKerning(leftGlyph, rightGlyph);
  }

  LoveFontWrapResult wrapText(String text, double wrapLimit) {
    final wrapTextCallback = _wrapTextCallback;
    if (wrapTextCallback != null && !_requiresFallbackAwareLayout) {
      return wrapTextCallback(text, wrapLimit);
    }

    final codepoints = text.runes.toList(growable: false);
    final lines = <String>[];
    final widths = <double>[];
    final lineCodepoints = <int>[];

    var width = 0.0;
    var widthBeforeLastSpace = 0.0;
    var widthOfTrailingSpace = 0.0;
    int? previous;
    var lastSpaceIndex = -1;

    var index = 0;
    while (index < codepoints.length) {
      final codepoint = codepoints[index];

      if (codepoint == 0x0a) {
        lines.add(String.fromCharCodes(lineCodepoints));
        widths.add(width - widthOfTrailingSpace);

        width = 0.0;
        widthBeforeLastSpace = 0.0;
        widthOfTrailingSpace = 0.0;
        previous = null;
        lastSpaceIndex = -1;
        lineCodepoints.clear();
        index++;
        continue;
      }

      if (codepoint == 0x0d) {
        index++;
        continue;
      }

      final charWidth = _layoutCharWidth(previous, codepoint);
      final newWidth = width + charWidth;

      if (codepoint != 0x20 && newWidth > wrapLimit) {
        if (lineCodepoints.isEmpty) {
          index++;
        } else if (lastSpaceIndex != -1) {
          while (lineCodepoints.isNotEmpty && lineCodepoints.last != 0x20) {
            lineCodepoints.removeLast();
          }
          width = widthBeforeLastSpace;
          index = lastSpaceIndex + 1;
        }

        lines.add(String.fromCharCodes(lineCodepoints));
        widths.add(width);

        width = 0.0;
        widthBeforeLastSpace = 0.0;
        widthOfTrailingSpace = 0.0;
        previous = null;
        lastSpaceIndex = -1;
        lineCodepoints.clear();
        continue;
      }

      if (previous != 0x20 && codepoint == 0x20) {
        widthBeforeLastSpace = width;
      }

      width = newWidth;
      previous = codepoint;
      lineCodepoints.add(codepoint);

      if (codepoint == 0x20) {
        lastSpaceIndex = index;
        widthOfTrailingSpace += charWidth;
      } else {
        widthOfTrailingSpace = 0.0;
      }

      index++;
    }

    lines.add(String.fromCharCodes(lineCodepoints));
    widths.add(width - widthOfTrailingSpace);

    var maxWidth = 0.0;
    for (final lineWidth in widths) {
      if (lineWidth > maxWidth) {
        maxWidth = lineWidth;
      }
    }
    return (width: maxWidth, lines: lines);
  }

  bool hasGlyphValues(Iterable<Object?> values) {
    if (values.isEmpty) {
      return false;
    }

    for (final value in values) {
      switch (value) {
        case String text:
          if (text.isEmpty) {
            return false;
          }
          for (final codepoint in text.runes) {
            if (!_supportsCodepoint(codepoint)) {
              return false;
            }
          }
        case num codepoint:
          if (!_supportsCodepoint(
            _truncateLoveFontNumericCodepoint(codepoint),
          )) {
            return false;
          }
        default:
          return false;
      }
    }

    return true;
  }

  bool _supportsCodepoint(int codepoint) {
    if (_supportsCodepointLocally(codepoint)) {
      return true;
    }

    for (final fallback in _fallbacks) {
      if (fallback._supportsCodepointLocally(codepoint)) {
        return true;
      }
    }

    return false;
  }

  void setFallbacks(List<LoveFont> fallbacks) {
    for (final fallback in fallbacks) {
      if (fallback.dataType != dataType) {
        throw ArgumentError('Font fallbacks must be of the same font type.');
      }
    }

    // Mirrors LOVE graphics::Font::setFallbacks, which keeps existing glyph
    // and kerning cache entries even after the fallback list changes. Each
    // fallback contributes only its primary font data, matching LOVE's use of
    // fallback.rasterizers[0] rather than recursively chaining fallback lists.
    _fallbacks
      ..clear()
      ..addAll(fallbacks);
  }

  LoveFont copy() {
    return LoveFont(
      size: size,
      family: family,
      source: source,
      fontType: fontType,
      dataType: dataType,
      glyphs: glyphs,
      glyphAdvance: glyphAdvance,
      glyphAdvances: glyphAdvances,
      glyphKernings: glyphKernings,
      extraSpacing: extraSpacing,
      hinting: hinting,
      dpiScale: dpiScale,
      lineHeight: lineHeight,
      heightOverride: heightOverride,
      ascentOverride: ascentOverride,
      descentOverride: descentOverride,
      missingGlyphAdvance: missingGlyphAdvance,
      syntheticTabAdvance: syntheticTabAdvance,
      filter: filter,
      fallbacks: _fallbacks,
      measureWidthCallback: _measureWidthCallback,
      wrapTextCallback: _wrapTextCallback,
      supportsCodepointCallback: _supportsCodepointCallback,
      isImplicitDefaultGraphicsFont: isImplicitDefaultGraphicsFont,
    );
  }

  LoveFont copyWith({
    double? size,
    String? family,
    String? source,
    String? fontType,
    String? dataType,
    String? glyphs,
    double? glyphAdvance,
    Map<int, double>? glyphAdvances,
    Map<int, double>? glyphKernings,
    double? extraSpacing,
    String? hinting,
    double? dpiScale,
    double? lineHeight,
    double? heightOverride,
    double? ascentOverride,
    double? descentOverride,
    double? missingGlyphAdvance,
    double? syntheticTabAdvance,
    LoveGraphicsDefaultFilter? filter,
    List<LoveFont>? fallbacks,
    LoveFontMeasureWidth? measureWidthCallback,
    LoveFontWrapText? wrapTextCallback,
    LoveFontSupportsCodepoint? supportsCodepointCallback,
    bool? isImplicitDefaultGraphicsFont,
  }) {
    return LoveFont(
      size: size ?? this.size,
      family: family ?? this.family,
      source: source ?? this.source,
      fontType: fontType ?? this.fontType,
      dataType: dataType ?? this.dataType,
      glyphs: glyphs ?? this.glyphs,
      glyphAdvance: glyphAdvance ?? this.glyphAdvance,
      glyphAdvances: glyphAdvances ?? this.glyphAdvances,
      glyphKernings: glyphKernings ?? this.glyphKernings,
      extraSpacing: extraSpacing ?? this.extraSpacing,
      hinting: hinting ?? this.hinting,
      dpiScale: dpiScale ?? this.dpiScale,
      lineHeight: lineHeight ?? this.lineHeight,
      heightOverride: heightOverride ?? this.heightOverride,
      ascentOverride: ascentOverride ?? this.ascentOverride,
      descentOverride: descentOverride ?? this.descentOverride,
      missingGlyphAdvance: missingGlyphAdvance ?? this.missingGlyphAdvance,
      syntheticTabAdvance: syntheticTabAdvance ?? this.syntheticTabAdvance,
      filter: filter ?? this.filter,
      fallbacks: fallbacks ?? _fallbacks,
      measureWidthCallback: measureWidthCallback ?? _measureWidthCallback,
      wrapTextCallback: wrapTextCallback ?? _wrapTextCallback,
      supportsCodepointCallback:
          supportsCodepointCallback ?? _supportsCodepointCallback,
      isImplicitDefaultGraphicsFont:
          isImplicitDefaultGraphicsFont ?? this.isImplicitDefaultGraphicsFont,
    );
  }

  double _measureGlyphWidth(String text) {
    var maxWidth = 0.0;
    var width = 0.0;
    int? previous;
    for (final codepoint in text.runes) {
      if (codepoint == 0x0a) {
        if (width > maxWidth) {
          maxWidth = width;
        }
        width = 0.0;
        previous = null;
        continue;
      }

      if (codepoint == 0x0d) {
        continue;
      }

      if (previous != null) {
        width += _glyphKerning(previous, codepoint);
      }
      width += _glyphAdvanceForCodepoint(codepoint);
      previous = codepoint;
    }
    return math.max(maxWidth, width);
  }

  double _layoutCharWidth(int? previous, int codepoint) {
    final advance = _requiresFallbackAwareLayout
        ? _glyphAdvanceForCodepoint(codepoint)
        : _layoutAdvanceForCodepoint(codepoint);
    if (previous == null) {
      return advance;
    }

    final kerning = _requiresFallbackAwareLayout
        ? _glyphKerning(previous, codepoint)
        : _layoutKerning(previous, codepoint);
    return advance + kerning;
  }

  double _layoutAdvanceForCodepoint(int codepoint) {
    final measureWidthCallback = _measureWidthCallback;
    if (measureWidthCallback != null) {
      return measureWidthCallback(String.fromCharCode(codepoint));
    }

    return size * 0.6;
  }

  double _layoutKerning(int leftGlyph, int rightGlyph) {
    final measureWidthCallback = _measureWidthCallback;
    if (measureWidthCallback == null) {
      return 0.0;
    }

    final left = String.fromCharCode(leftGlyph);
    final right = String.fromCharCode(rightGlyph);
    return measureWidthCallback('$left$right') -
        measureWidthCallback(left) -
        measureWidthCallback(right);
  }

  double _glyphAdvanceForCodepoint(int codepoint) {
    final cachedAdvance = _cachedGlyphAdvances[codepoint];
    if (cachedAdvance != null) {
      return cachedAdvance;
    }

    final font = _fontForLayoutCodepoint(codepoint);
    final advance = font?._glyphAdvanceForCodepointLocally(codepoint) ?? 0.0;
    _cachedGlyphAdvances[codepoint] = advance;
    return advance;
  }

  double _glyphAdvanceForCodepointLocally(int codepoint) {
    if (codepoint == _loveTabCodepoint && _hasSyntheticTabAdvance) {
      return syntheticTabAdvance!;
    }

    final advanceMap = glyphAdvances;
    if (advanceMap != null) {
      return advanceMap[codepoint] ?? missingGlyphAdvance ?? 0.0;
    }

    if (glyphAdvance != null) {
      return glyphAdvance! + extraSpacing;
    }

    final measureWidthCallback = _measureWidthCallback;
    if (measureWidthCallback != null) {
      return measureWidthCallback(String.fromCharCode(codepoint));
    }

    return 0.0;
  }

  double _glyphKerning(int leftGlyph, int rightGlyph) {
    final pair = _packLoveGlyphPair(leftGlyph, rightGlyph);
    final cachedKerning = _cachedGlyphKernings[pair];
    if (cachedKerning != null) {
      return cachedKerning;
    }

    final font = _fontForKerningPair(leftGlyph, rightGlyph);
    final kerning = font?._glyphKerningLocally(leftGlyph, rightGlyph) ?? 0.0;
    _cachedGlyphKernings[pair] = kerning;
    return kerning;
  }

  double _glyphKerningLocally(int leftGlyph, int rightGlyph) {
    final kerningMap = glyphKernings;
    if (kerningMap != null) {
      return kerningMap[_packLoveGlyphPair(leftGlyph, rightGlyph)] ?? 0.0;
    }

    final measureWidthCallback = _measureWidthCallback;
    if (measureWidthCallback == null) {
      return 0.0;
    }

    final left = String.fromCharCode(leftGlyph);
    final right = String.fromCharCode(rightGlyph);
    return measureWidthCallback('$left$right') -
        measureWidthCallback(left) -
        measureWidthCallback(right);
  }

  LoveFont? _fontForLayoutCodepoint(int codepoint) {
    if (_supportsLayoutCodepointLocally(codepoint)) {
      return this;
    }

    for (final fallback in _fallbacks) {
      if (fallback._supportsCodepointLocally(codepoint)) {
        return fallback;
      }
    }

    // LOVE falls back to the primary rasterizer's missing-glyph metrics when
    // no fallback actually contains the queried codepoint.
    if (missingGlyphAdvance != null) {
      return this;
    }

    return null;
  }

  bool _supportsLayoutCodepointLocally(int codepoint) {
    return _supportsCodepointLocally(codepoint) ||
        (codepoint == _loveTabCodepoint && _hasSyntheticTabAdvance);
  }

  LoveFont? _fontForKerningPair(int leftGlyph, int rightGlyph) {
    if (_supportsCodepointLocally(leftGlyph) &&
        _supportsCodepointLocally(rightGlyph)) {
      return this;
    }

    for (final fallback in _fallbacks) {
      if (fallback._supportsCodepointLocally(leftGlyph) &&
          fallback._supportsCodepointLocally(rightGlyph)) {
        return fallback;
      }
    }

    return null;
  }

  bool _supportsCodepointLocally(int codepoint) {
    final supportsCodepointCallback = _supportsCodepointCallback;
    if (supportsCodepointCallback != null) {
      return supportsCodepointCallback(codepoint);
    }

    if (fontType != imageFontType) {
      return _isValidUnicodeScalar(codepoint);
    }

    final localGlyphAdvances = glyphAdvances;
    if (localGlyphAdvances != null &&
        localGlyphAdvances.containsKey(codepoint)) {
      return true;
    }

    final localGlyphs = glyphs;
    if (localGlyphs != null && localGlyphs.runes.contains(codepoint)) {
      return true;
    }

    return false;
  }

  int? _glyphCodepoint(Object? value) {
    return switch (value) {
      null => null,
      String text when text.isNotEmpty => text.runes.first,
      num codepoint => _truncateLoveFontNumericCodepoint(codepoint),
      _ => null,
    };
  }
}

class LoveTextSpan {
  const LoveTextSpan({required this.text, this.color});

  final String text;
  final LoveColor? color;

  LoveTextSpan copy() => LoveTextSpan(text: text, color: color);
}

class LoveTextEntry {
  LoveTextEntry({
    required List<LoveTextSpan> spans,
    Matrix4? transform,
    this.wrapLimit,
    this.align = 'left',
  }) : spans = List<LoveTextSpan>.unmodifiable(
         spans.map((segment) => segment.copy()),
       ),
       transform = transform == null
           ? Matrix4.identity()
           : Matrix4.copy(transform);

  final List<LoveTextSpan> spans;
  final Matrix4 transform;
  final double? wrapLimit;
  final String align;

  String get plainText => spans.map((segment) => segment.text).join();

  double widthForFont(LoveFont font) {
    if (wrapLimit case final double limit) {
      return font.wrapText(plainText, limit).width;
    }

    return font.measureWidth(plainText);
  }

  double heightForFont(LoveFont font) {
    final renderedLineHeight = font.height * font.lineHeight;
    if (wrapLimit case final double limit) {
      final lineCount = math.max(
        font.wrapText(plainText, limit).lines.length,
        1,
      );
      return lineCount * renderedLineHeight;
    }

    if (plainText.isEmpty) {
      return 0.0;
    }

    return renderedLineHeight;
  }

  LoveTextEntry copy() {
    return LoveTextEntry(
      spans: spans,
      transform: transform,
      wrapLimit: wrapLimit,
      align: align,
    );
  }
}

class LoveTextDrawable {
  LoveTextDrawable({required this.font, List<LoveTextEntry>? entries})
    : _entries = entries == null
          ? <LoveTextEntry>[]
          : List<LoveTextEntry>.from(entries.map((entry) => entry.copy()));

  // Mirrors the high-level LOVE Text object flow from wrap_Text.cpp/Text.cpp:
  // set* replaces the batch, add* appends, and width/height default to the
  // most recently added entry.
  LoveFont font;
  final List<LoveTextEntry> _entries;

  List<LoveTextEntry> get entries => List<LoveTextEntry>.unmodifiable(_entries);

  void clear() {
    _entries.clear();
  }

  void set(List<LoveTextSpan> spans) {
    if (_shouldClearOnSet(spans)) {
      clear();
      return;
    }

    _entries
      ..clear()
      ..add(LoveTextEntry(spans: spans));
  }

  void setf(List<LoveTextSpan> spans, double wrapLimit, String align) {
    if (_shouldClearOnSet(spans)) {
      clear();
      return;
    }

    _entries
      ..clear()
      ..add(LoveTextEntry(spans: spans, wrapLimit: wrapLimit, align: align));
  }

  int add(List<LoveTextSpan> spans, Matrix4 transform) {
    _entries.add(LoveTextEntry(spans: spans, transform: transform));
    return _entries.length - 1;
  }

  int addf(
    List<LoveTextSpan> spans,
    double wrapLimit,
    String align,
    Matrix4 transform,
  ) {
    _entries.add(
      LoveTextEntry(
        spans: spans,
        transform: transform,
        wrapLimit: wrapLimit,
        align: align,
      ),
    );
    return _entries.length - 1;
  }

  double getWidth([int index = -1]) {
    final entry = _entryAt(index);
    return entry?.widthForFont(font) ?? 0.0;
  }

  double getHeight([int index = -1]) {
    final entry = _entryAt(index);
    return entry?.heightForFont(font) ?? 0.0;
  }

  ({double width, double height}) getDimensions([int index = -1]) {
    return (width: getWidth(index), height: getHeight(index));
  }

  LoveTextDrawable copy() {
    return LoveTextDrawable(font: font.copy(), entries: _entries);
  }

  LoveTextEntry? _entryAt(int index) {
    if (_entries.isEmpty) {
      return null;
    }

    final resolvedIndex = index < 0 ? _entries.length - 1 : index;
    if (resolvedIndex < 0 || resolvedIndex >= _entries.length) {
      return null;
    }

    return _entries[resolvedIndex];
  }

  bool _shouldClearOnSet(List<LoveTextSpan> spans) {
    return spans.isEmpty || (spans.length == 1 && spans.first.text.isEmpty);
  }
}

class LoveColor {
  const LoveColor(this.r, this.g, this.b, [this.a = 1.0]);

  static const LoveColor white = LoveColor(1, 1, 1, 1);
  static const LoveColor black = LoveColor(0, 0, 0, 1);

  final double r;
  final double g;
  final double b;
  final double a;

  LoveColor clamped() {
    return LoveColor(
      _clampColor(r),
      _clampColor(g),
      _clampColor(b),
      _clampColor(a),
    );
  }

  LoveColor modulate(LoveColor other) {
    return LoveColor(
      r * other.r,
      g * other.g,
      b * other.b,
      a * other.a,
    ).clamped();
  }

  @override
  bool operator ==(Object other) {
    return other is LoveColor &&
        other.r == r &&
        other.g == g &&
        other.b == b &&
        other.a == a;
  }

  @override
  int get hashCode => Object.hash(r, g, b, a);
}

sealed class LoveDrawCommand {
  LoveDrawCommand({
    required this.color,
    required this.lineWidth,
    required this.lineStyle,
    required this.lineJoin,
    required this.blendMode,
    required this.blendAlphaMode,
    required this.colorMask,
    required this.wireframe,
    required this.scissor,
    LoveShader? shader,
    required Matrix4 transform,
  }) : shader = shader?.snapshot(),
       transform = Matrix4.copy(transform);

  final LoveColor color;
  final double lineWidth;
  final LoveGraphicsLineStyle lineStyle;
  final LoveGraphicsLineJoin lineJoin;
  final LoveGraphicsBlendMode blendMode;
  final LoveGraphicsBlendAlphaMode blendAlphaMode;
  final LoveGraphicsColorMask colorMask;
  final bool wireframe;
  final LoveScissorRect? scissor;
  final LoveShader? shader;
  final Matrix4 transform;
}

class LoveRectangleCommand extends LoveDrawCommand {
  LoveRectangleCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.mode,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.cornerRadiusX = 0,
    this.cornerRadiusY = 0,
  });

  final LoveGraphicsDrawMode mode;
  final double x;
  final double y;
  final double width;
  final double height;
  final double cornerRadiusX;
  final double cornerRadiusY;
}

class LoveTextCommand extends LoveDrawCommand {
  LoveTextCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required Matrix4 textTransform,
    required LoveFont font,
    required List<LoveTextSpan> spans,
    required this.x,
    required this.y,
    this.limit,
    this.align = 'left',
  }) : spans = List<LoveTextSpan>.unmodifiable(spans),
       font = font.copy(),
       textTransform = Matrix4.copy(textTransform);

  final List<LoveTextSpan> spans;
  final LoveFont font;
  final Matrix4 textTransform;
  final double x;
  final double y;
  final double? limit;
  final String align;

  String get text => spans.map((segment) => segment.text).join();
}

class LoveTextObjectCommand extends LoveDrawCommand {
  LoveTextObjectCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required Matrix4 drawTransform,
    required LoveTextDrawable textObject,
  }) : drawTransform = Matrix4.copy(drawTransform),
       textObject = textObject.copy();

  final Matrix4 drawTransform;
  final LoveTextDrawable textObject;
}

class LoveImageCommand extends LoveDrawCommand {
  LoveImageCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required Matrix4 drawTransform,
    required this.image,
    LoveQuad? quad,
  }) : quad = quad?.copy(),
       drawTransform = Matrix4.copy(drawTransform);

  final LoveImage image;
  final LoveQuad? quad;
  final Matrix4 drawTransform;
}

class LoveSpriteBatchCommand extends LoveDrawCommand {
  LoveSpriteBatchCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required Matrix4 drawTransform,
    required LoveSpriteBatch spriteBatch,
  }) : drawTransform = Matrix4.copy(drawTransform),
       spriteBatch = spriteBatch.copyForDraw();

  final Matrix4 drawTransform;
  final LoveSpriteBatch spriteBatch;
}

class LoveParticleSystemCommand extends LoveDrawCommand {
  LoveParticleSystemCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required Matrix4 drawTransform,
    required LoveParticleSystemSnapshot particleSystem,
  }) : drawTransform = Matrix4.copy(drawTransform),
       particleSystem = particleSystem.copy();

  final Matrix4 drawTransform;
  final LoveParticleSystemSnapshot particleSystem;
}

class LoveMeshCommand extends LoveDrawCommand {
  LoveMeshCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    required super.shader,
    required super.transform,
    required Matrix4 drawTransform,
    required LoveMesh mesh,
    required this.frontFaceWinding,
    required this.cullMode,
  }) : drawTransform = Matrix4.copy(drawTransform),
       mesh = mesh.copy();

  final LoveMesh mesh;
  final Matrix4 drawTransform;
  final LoveGraphicsVertexWinding frontFaceWinding;
  final LoveGraphicsCullMode cullMode;
}

class LoveCircleCommand extends LoveDrawCommand {
  LoveCircleCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.mode,
    required this.x,
    required this.y,
    required this.radius,
  });

  final LoveGraphicsDrawMode mode;
  final double x;
  final double y;
  final double radius;
}

class LoveLineCommand extends LoveDrawCommand {
  LoveLineCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.points,
  });

  final List<({double x, double y})> points;
}

class LovePolygonCommand extends LoveDrawCommand {
  LovePolygonCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.mode,
    required this.points,
  });

  final LoveGraphicsDrawMode mode;
  final List<({double x, double y})> points;
}

class LoveEllipseCommand extends LoveDrawCommand {
  LoveEllipseCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.mode,
    required this.x,
    required this.y,
    required this.radiusX,
    required this.radiusY,
  });

  final LoveGraphicsDrawMode mode;
  final double x;
  final double y;
  final double radiusX;
  final double radiusY;
}

class LoveArcCommand extends LoveDrawCommand {
  LoveArcCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.drawMode,
    required this.arcMode,
    required this.x,
    required this.y,
    required this.radius,
    required this.angle1,
    required this.angle2,
  });

  final LoveGraphicsDrawMode drawMode;
  final LoveGraphicsArcMode arcMode;
  final double x;
  final double y;
  final double radius;
  final double angle1;
  final double angle2;
}

class LovePointsCommand extends LoveDrawCommand {
  LovePointsCommand({
    required super.color,
    required super.lineWidth,
    required super.lineStyle,
    required super.lineJoin,
    required super.blendMode,
    required super.blendAlphaMode,
    required super.colorMask,
    required super.wireframe,
    required super.scissor,
    super.shader,
    required super.transform,
    required this.pointSize,
    required this.points,
  });

  final double pointSize;
  final List<({double x, double y, LoveColor? color})> points;
}

class LoveGraphicsState {
  LoveGraphicsState({
    LoveColor? color,
    LoveColor? backgroundColor,
    LoveFont? font,
    this.scissor,
    double? pointSize,
    double? lineWidth,
    LoveGraphicsLineStyle? lineStyle,
    LoveGraphicsLineJoin? lineJoin,
    LoveGraphicsBlendMode? blendMode,
    LoveGraphicsBlendAlphaMode? blendAlphaMode,
    LoveGraphicsColorMask? colorMask,
    LoveGraphicsDefaultFilter? defaultFilter,
    LoveShader? shader,
    bool? wireframe,
    Matrix4? transform,
    LoveGraphicsCompareMode? depthMode,
    bool? depthWrite,
    LoveGraphicsCompareMode? stencilCompare,
    int? stencilValue,
    LoveGraphicsVertexWinding? frontFaceWinding,
    LoveGraphicsCullMode? meshCullMode,
  }) : color = (color ?? LoveColor.white).clamped(),
       backgroundColor = (backgroundColor ?? LoveColor.black).clamped(),
       font = font?.copy() ?? LoveFont.fallback(),
       pointSize = pointSize ?? 1.0,
       lineWidth = lineWidth ?? 1.0,
       lineStyle = lineStyle ?? LoveGraphicsLineStyle.smooth,
       lineJoin = lineJoin ?? LoveGraphicsLineJoin.miter,
       blendMode = blendMode ?? LoveGraphicsBlendMode.alpha,
       blendAlphaMode =
           blendAlphaMode ?? LoveGraphicsBlendAlphaMode.alphaMultiply,
       colorMask = colorMask ?? LoveGraphicsColorMask.all,
       defaultFilter = defaultFilter ?? LoveGraphicsDefaultFilter.standard,
       shader = shader?.snapshot(),
       wireframe = wireframe ?? false,
       transform = transform ?? Matrix4.identity(),
       depthMode = depthMode ?? LoveGraphicsCompareMode.always,
       depthWrite = depthWrite ?? false,
       stencilCompare = stencilCompare ?? LoveGraphicsCompareMode.always,
       stencilValue = stencilValue ?? 0,
       frontFaceWinding = frontFaceWinding ?? LoveGraphicsVertexWinding.ccw,
       meshCullMode = meshCullMode ?? LoveGraphicsCullMode.none;

  LoveColor color;
  LoveColor backgroundColor;
  LoveFont font;
  LoveScissorRect? scissor;
  double pointSize;
  double lineWidth;
  LoveGraphicsLineStyle lineStyle;
  LoveGraphicsLineJoin lineJoin;
  LoveGraphicsBlendMode blendMode;
  LoveGraphicsBlendAlphaMode blendAlphaMode;
  LoveGraphicsColorMask colorMask;
  LoveGraphicsDefaultFilter defaultFilter;
  LoveShader? shader;
  bool wireframe;
  Matrix4 transform;
  LoveGraphicsCompareMode depthMode;
  bool depthWrite;
  LoveGraphicsCompareMode stencilCompare;
  int stencilValue;
  LoveGraphicsVertexWinding frontFaceWinding;
  LoveGraphicsCullMode meshCullMode;

  LoveGraphicsState copy() {
    return LoveGraphicsState(
      color: color,
      backgroundColor: backgroundColor,
      font: font.copy(),
      scissor: scissor,
      pointSize: pointSize,
      lineWidth: lineWidth,
      lineStyle: lineStyle,
      lineJoin: lineJoin,
      blendMode: blendMode,
      blendAlphaMode: blendAlphaMode,
      colorMask: colorMask,
      defaultFilter: defaultFilter,
      shader: shader?.snapshot(),
      wireframe: wireframe,
      transform: Matrix4.copy(transform),
      depthMode: depthMode,
      depthWrite: depthWrite,
      stencilCompare: stencilCompare,
      stencilValue: stencilValue,
      frontFaceWinding: frontFaceWinding,
      meshCullMode: meshCullMode,
    );
  }
}

class LoveGraphicsStackFrame {
  LoveGraphicsStackFrame({required this.type, required LoveGraphicsState state})
    : state = state.copy();

  final LoveGraphicsStackType type;
  final LoveGraphicsState state;
}

class LoveGraphicsFrame {
  LoveGraphicsFrame({LoveColor? color, LoveColor? backgroundColor})
    : _state = LoveGraphicsState(
        color: color,
        backgroundColor: backgroundColor,
      ),
      _screenSurface = LoveGraphicsSurface(
        clearColor: (backgroundColor ?? LoveColor.black).clamped(),
        clearColorMask: LoveGraphicsColorMask.all,
      );

  static const int maxUserStackDepth = 128;

  final List<LoveGraphicsStackFrame> _stack = <LoveGraphicsStackFrame>[];
  final LoveGraphicsSurface _screenSurface;
  LoveGraphicsState _state;
  LoveCanvas? _activeCanvas;
  int _canvasSwitches = 0;
  int _shaderSwitches = 0;

  LoveColor get color => _state.color;

  set color(LoveColor value) {
    _state.color = value.clamped();
  }

  LoveColor get backgroundColor => _state.backgroundColor;

  set backgroundColor(LoveColor value) {
    _state.backgroundColor = value.clamped();
  }

  LoveColor get clearColor => _screenSurface.clearColor;

  LoveGraphicsColorMask get clearColorMask => _screenSurface.clearColorMask;

  LoveScissorRect? get clearScissor => _screenSurface.clearScissor;

  LoveFont get font => _state.font;

  set font(LoveFont value) {
    _state.font = value;
  }

  LoveScissorRect? get scissor => _state.scissor;

  set scissor(LoveScissorRect? value) {
    _state.scissor = value;
  }

  int get stackDepth => _stack.length;

  double get lineWidth => _state.lineWidth;

  double get pointSize => _state.pointSize;

  set pointSize(double value) {
    _state.pointSize = value > 0 ? value : 1.0;
  }

  set lineWidth(double value) {
    _state.lineWidth = value > 0 ? value : 1.0;
  }

  LoveGraphicsLineStyle get lineStyle => _state.lineStyle;

  set lineStyle(LoveGraphicsLineStyle value) {
    _state.lineStyle = value;
  }

  LoveGraphicsLineJoin get lineJoin => _state.lineJoin;

  set lineJoin(LoveGraphicsLineJoin value) {
    _state.lineJoin = value;
  }

  LoveGraphicsBlendMode get blendMode => _state.blendMode;

  set blendMode(LoveGraphicsBlendMode value) {
    _state.blendMode = value;
  }

  LoveGraphicsBlendAlphaMode get blendAlphaMode => _state.blendAlphaMode;

  set blendAlphaMode(LoveGraphicsBlendAlphaMode value) {
    _state.blendAlphaMode = value;
  }

  LoveGraphicsColorMask get colorMask => _state.colorMask;

  set colorMask(LoveGraphicsColorMask value) {
    _state.colorMask = value;
  }

  LoveGraphicsDefaultFilter get defaultFilter => _state.defaultFilter;

  set defaultFilter(LoveGraphicsDefaultFilter value) {
    _state.defaultFilter = value;
  }

  LoveShader? get shader => _state.shader?.snapshot();

  bool get wireframe => _state.wireframe;

  set wireframe(bool value) {
    _state.wireframe = value;
  }

  LoveGraphicsCompareMode get depthMode => _state.depthMode;

  set depthMode(LoveGraphicsCompareMode value) {
    _state.depthMode = value;
  }

  bool get depthWrite => _state.depthWrite;

  set depthWrite(bool value) {
    _state.depthWrite = value;
  }

  LoveGraphicsCompareMode get stencilCompare => _state.stencilCompare;

  set stencilCompare(LoveGraphicsCompareMode value) {
    _state.stencilCompare = value;
  }

  int get stencilValue => _state.stencilValue;

  set stencilValue(int value) {
    _state.stencilValue = value;
  }

  LoveGraphicsVertexWinding get frontFaceWinding => _state.frontFaceWinding;

  set frontFaceWinding(LoveGraphicsVertexWinding value) {
    _state.frontFaceWinding = value;
  }

  LoveGraphicsCullMode get meshCullMode => _state.meshCullMode;

  set meshCullMode(LoveGraphicsCullMode value) {
    _state.meshCullMode = value;
  }

  Matrix4 get transform => _state.transform;

  List<LoveDrawCommand> get commands =>
      List<LoveDrawCommand>.unmodifiable(_screenSurface.commands);

  LoveCanvas? get activeCanvas => _activeCanvas;

  int get canvasSwitches => _canvasSwitches;

  int get shaderSwitches => _shaderSwitches;

  LoveGraphicsSurface get _activeSurface =>
      _activeCanvas?.surface ?? _screenSurface;

  void beginFrame() {
    _screenSurface.begin(
      clearColor: _state.backgroundColor,
      clearColorMask: _state.colorMask,
      clearScissor: _state.scissor,
    );
    _activeCanvas = null;
    _canvasSwitches = 0;
    _shaderSwitches = 0;
  }

  void clear([LoveColor? color]) {
    _activeSurface.clear(
      clearColor: (color ?? _state.backgroundColor).clamped(),
      clearColorMask: _state.colorMask,
      clearScissor: _state.scissor,
    );
  }

  void reset() {
    _state = LoveGraphicsState();
  }

  void addCommand(LoveDrawCommand command) {
    _activeSurface.addCommand(command);
  }

  void setCanvas(LoveCanvas? canvas) {
    if (identical(_activeCanvas, canvas)) {
      return;
    }

    _activeCanvas = canvas;
    _canvasSwitches++;
  }

  void setShader(LoveShader? shader) {
    if (_shaderEquals(_state.shader, shader)) {
      return;
    }

    _state.shader = shader?.snapshot();
    _shaderSwitches++;
  }

  void push([LoveGraphicsStackType type = LoveGraphicsStackType.transform]) {
    if (_stack.length == maxUserStackDepth) {
      throw StateError('Maximum graphics stack depth reached');
    }

    _stack.add(LoveGraphicsStackFrame(type: type, state: _state));
  }

  void pop() {
    if (_stack.isEmpty) {
      throw StateError('Minimum graphics stack depth reached');
    }

    final frame = _stack.removeLast();
    switch (frame.type) {
      case LoveGraphicsStackType.all:
        _state = frame.state.copy();
      case LoveGraphicsStackType.transform:
        _state.transform = Matrix4.copy(frame.state.transform);
    }
  }

  void translate(double x, double y) {
    _state.transform.translateByDouble(x, y, 0, 1);
  }

  void rotate(double angle) {
    _state.transform.rotateZ(angle);
  }

  void scale(double x, [double? y]) {
    _state.transform.scaleByDouble(x, y ?? x, 1, 1);
  }

  void shear(double kx, double ky) {
    final shear = Matrix4.identity()
      ..setEntry(0, 1, kx)
      ..setEntry(1, 0, ky);
    _state.transform.multiply(shear);
  }

  void origin() {
    _state.transform.setIdentity();
  }

  void applyTransform(LoveTransform transform) {
    _state.transform.multiply(transform.matrix);
  }

  void replaceTransform(LoveTransform transform) {
    _state.transform = Matrix4.copy(transform.matrix);
  }

  void setScissor(LoveScissorRect? rect) {
    _state.scissor = rect;
  }

  void intersectScissor(LoveScissorRect rect) {
    final current = _state.scissor;
    _state.scissor = current == null ? rect : current.intersect(rect);
  }

  Matrix4 copyTransform() => Matrix4.copy(_state.transform);

  ({double x, double y}) transformPoint(double x, double y) {
    final point = _state.transform.transformed3(Vector3(x, y, 0));
    return (x: point.x, y: point.y);
  }

  ({double x, double y}) inverseTransformPoint(double x, double y) {
    final inverse = Matrix4.copy(_state.transform);
    final determinant = inverse.invert();
    if (determinant == 0) {
      throw StateError('Current transform is not invertible');
    }

    final point = inverse.transformed3(Vector3(x, y, 0));
    return (x: point.x, y: point.y);
  }
}

Matrix4 _matrixFromTransformation({
  required double x,
  required double y,
  required double angle,
  required double scaleX,
  required double scaleY,
  required double originX,
  required double originY,
  required double shearX,
  required double shearY,
}) {
  final cosAngle = math.cos(angle);
  final sinAngle = math.sin(angle);
  final a = cosAngle * scaleX - shearY * sinAngle * scaleY;
  final b = sinAngle * scaleX + shearY * cosAngle * scaleY;
  final c = shearX * cosAngle * scaleX - sinAngle * scaleY;
  final d = shearX * sinAngle * scaleX + cosAngle * scaleY;
  final tx = x - (originX * a) - (originY * c);
  final ty = y - (originX * b) - (originY * d);

  return Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
}

abstract interface class LoveClock {
  double nowSeconds();

  Future<void> sleepSeconds(double seconds);
}

class SystemLoveClock implements LoveClock {
  SystemLoveClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  double nowSeconds() =>
      _stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;

  @override
  Future<void> sleepSeconds(double seconds) {
    if (seconds <= 0) {
      return Future<void>.value();
    }

    final microseconds = (seconds * Duration.microsecondsPerSecond).round();
    return Future<void>.delayed(Duration(microseconds: microseconds));
  }
}

class LoveRandomGenerator {
  LoveRandomGenerator({int low = defaultSeedLow, int high = defaultSeedHigh}) {
    setSeed(low: low, high: high);
  }

  static const int defaultSeedLow = 0xCBBF7A44;
  static const int defaultSeedHigh = 0x0139408D;
  static const int _seedBits = 32;
  static const int _mask32 = 0xFFFFFFFF;
  static const int _doubleMantissaBits =
      NumberLimits.doubleStoredSignificandBits + 1;
  static const int _mantissaShift =
      NumberLimits.sizeInBits - _doubleMantissaBits;
  static const int _doubleMantissaMask = (1 << _doubleMantissaBits) - 1;
  static final BigInt _mask64 =
      (BigInt.one << NumberLimits.sizeInBits) - BigInt.one;
  static final BigInt _nonZeroFallbackState = BigInt.parse(
    '9E3779B97F4A7C15',
    radix: 16,
  );
  static final BigInt _nextUint64Multiplier = BigInt.parse(
    '2545F4914F6CDD1D',
    radix: 16,
  );

  int _seedLow = defaultSeedLow;
  int _seedHigh = defaultSeedHigh;
  BigInt _state = _nonZeroFallbackState;

  int get seedLow => _seedLow;
  int get seedHigh => _seedHigh;

  static BigInt _normalizeUint64(dynamic value) =>
      NumberUtils.toBigInt(value) & _mask64;

  void setSeed({required int low, required int high}) {
    _seedLow = low & _mask32;
    _seedHigh = high & _mask32;
    _state = _loveRandomSeedToState(low: _seedLow, high: _seedHigh);
    _resetLoveRandomNormalCache(this);
  }

  double nextUnitDouble() {
    final mantissa =
        ((_nextUint64() >> _mantissaShift) & BigInt.from(_doubleMantissaMask))
            .toInt();
    return mantissa / (1 << _doubleMantissaBits);
  }

  int nextIntInclusive({required int min, required int max}) {
    if (max < min) {
      throw RangeError.range(max, min, null, 'max');
    }

    final span = max - min + 1;
    return min + (nextUnitDouble() * span).floor();
  }

  BigInt _nextUint64() {
    var x = _state & _mask64;
    x ^= x >> 12;
    x &= _mask64;
    x ^= (x << 25) & _mask64;
    x &= _mask64;
    x ^= x >> 27;
    x &= _mask64;
    _state = x;
    return (x * _nextUint64Multiplier) & _mask64;
  }
}

class LoveWindowMetrics {
  const LoveWindowMetrics({
    this.width = 800,
    this.height = 600,
    this.x = 0,
    this.y = 0,
    this.title = 'LÖVE',
    this.fullscreen = false,
    this.fullscreenType = 'desktop',
    this.vsync = 1,
    this.open = true,
    this.visible = true,
    this.maximized = false,
    this.minimized = false,
    this.displaySleepEnabled = true,
    this.attentionRequested = false,
    this.attentionRequestContinuous = false,
    this.msaa = 0,
    this.resizable = false,
    this.borderless = false,
    this.centered = true,
    this.display = 1,
    this.minWidth = 1,
    this.minHeight = 1,
    this.highDpi = false,
    this.refreshRate = 0,
    this.dpiScale = 1.0,
    this.desktopWidth = 800,
    this.desktopHeight = 600,
    this.safeArea,
    this.icon,
  });

  final int width;
  final int height;
  final int x;
  final int y;
  final String title;
  final bool fullscreen;
  final String fullscreenType;
  final int vsync;
  final bool open;
  final bool visible;
  final bool maximized;
  final bool minimized;
  final bool displaySleepEnabled;
  final bool attentionRequested;
  final bool attentionRequestContinuous;
  final int msaa;
  final bool resizable;
  final bool borderless;
  final bool centered;
  final int display;
  final int minWidth;
  final int minHeight;
  final bool highDpi;
  final int refreshRate;
  final double dpiScale;
  final int desktopWidth;
  final int desktopHeight;
  final LoveWindowSafeArea? safeArea;
  final LoveImageData? icon;

  LoveWindowMetrics copyWith({
    int? width,
    int? height,
    int? x,
    int? y,
    String? title,
    bool? fullscreen,
    String? fullscreenType,
    int? vsync,
    bool? open,
    bool? visible,
    bool? maximized,
    bool? minimized,
    bool? displaySleepEnabled,
    bool? attentionRequested,
    bool? attentionRequestContinuous,
    int? msaa,
    bool? resizable,
    bool? borderless,
    bool? centered,
    int? display,
    int? minWidth,
    int? minHeight,
    bool? highDpi,
    int? refreshRate,
    double? dpiScale,
    int? desktopWidth,
    int? desktopHeight,
    LoveWindowSafeArea? safeArea,
    LoveImageData? icon,
  }) {
    return LoveWindowMetrics(
      width: width ?? this.width,
      height: height ?? this.height,
      x: x ?? this.x,
      y: y ?? this.y,
      title: title ?? this.title,
      fullscreen: fullscreen ?? this.fullscreen,
      fullscreenType: fullscreenType ?? this.fullscreenType,
      vsync: vsync ?? this.vsync,
      open: open ?? this.open,
      visible: visible ?? this.visible,
      maximized: maximized ?? this.maximized,
      minimized: minimized ?? this.minimized,
      displaySleepEnabled: displaySleepEnabled ?? this.displaySleepEnabled,
      attentionRequested: attentionRequested ?? this.attentionRequested,
      attentionRequestContinuous:
          attentionRequestContinuous ?? this.attentionRequestContinuous,
      msaa: msaa ?? this.msaa,
      resizable: resizable ?? this.resizable,
      borderless: borderless ?? this.borderless,
      centered: centered ?? this.centered,
      display: display ?? this.display,
      minWidth: minWidth ?? this.minWidth,
      minHeight: minHeight ?? this.minHeight,
      highDpi: highDpi ?? this.highDpi,
      refreshRate: refreshRate ?? this.refreshRate,
      dpiScale: dpiScale ?? this.dpiScale,
      desktopWidth: desktopWidth ?? this.desktopWidth,
      desktopHeight: desktopHeight ?? this.desktopHeight,
      safeArea: safeArea ?? this.safeArea,
      icon: icon ?? this.icon,
    );
  }

  Map<dynamic, dynamic> toModeFlags({Map<dynamic, dynamic>? target}) {
    final map = target ?? <dynamic, dynamic>{};
    map['fullscreen'] = fullscreen;
    map['fullscreentype'] = fullscreenType;
    map['vsync'] = vsync;
    map['msaa'] = msaa;
    map['resizable'] = resizable;
    map['borderless'] = borderless;
    map['centered'] = centered;
    map['display'] = display;
    map['minwidth'] = minWidth;
    map['minheight'] = minHeight;
    map['highdpi'] = highDpi;
    map['refreshrate'] = refreshRate;
    return map;
  }
}

class LoveWindowSafeArea {
  const LoveWindowSafeArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class LoveWindowFullscreenMode {
  const LoveWindowFullscreenMode({required this.width, required this.height});

  final int width;
  final int height;
}

class LoveWindowDisplay {
  const LoveWindowDisplay({
    required this.name,
    required this.orientation,
    required this.fullscreenModes,
  });

  final String name;
  final String orientation;
  final List<LoveWindowFullscreenMode> fullscreenModes;
}

abstract interface class LoveHost {
  LoveClock get clock;

  bool get usesExternalFrameLoop;

  LoveRandomGenerator get random;

  LoveKeyboardState get keyboard;

  LoveMouseState get mouse;

  LoveTouchState get touch;

  LoveJoystickManager get joysticks;

  LoveSystemState get system;

  LoveGraphicsFrame get graphics;

  bool get requiresMountedFilesystemForRelativeResourcePaths;

  Future<LoveAudioSourceBackend> createAudioSourceBackend(
    String source, {
    required String sourceType,
    Uint8List? bytes,
    String? mimeType,
  });

  Future<LoveImage> loadImage(
    String source, {
    Uint8List? bytes,
    Map<dynamic, dynamic>? settings,
  });

  Future<LoveFont?> loadTrueTypeFont(
    String source, {
    required Uint8List bytes,
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  });

  Future<LoveFont?> loadDefaultTrueTypeFont({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  });

  Future<Uint8List?> loadDefaultTrueTypeFontBytes();

  int get imageCount;

  String get rendererName;

  String get rendererVersion;

  String get rendererVendor;

  String get rendererDevice;

  LoveWindowMetrics get windowMetrics;

  set windowMetrics(LoveWindowMetrics value);

  List<LoveWindowDisplay> get windowDisplays;

  set windowDisplays(List<LoveWindowDisplay> value);

  bool get windowHasFocus;

  set windowHasFocus(bool value);

  bool get windowHasMouseFocus;

  set windowHasMouseFocus(bool value);

  Future<LoveWindowMessageBoxResponse> showWindowMessageBox(
    LoveWindowMessageBoxData data,
  );
}

class LoveHeadlessHost implements LoveHost {
  LoveHeadlessHost({
    LoveClock? clock,
    LoveRandomGenerator? random,
    LoveKeyboardState? keyboard,
    LoveMouseState? mouse,
    LoveTouchState? touch,
    LoveJoystickManager? joysticks,
    LoveSystemState? system,
    LoveGraphicsFrame? graphics,
    Map<String, LoveImage>? images,
    Future<LoveImage> Function(
      String source, {
      Uint8List? bytes,
      Map<dynamic, dynamic>? settings,
    })?
    imageLoader,
    Future<LoveFont?> Function(
      String source, {
      required Uint8List bytes,
      required double size,
      required String hinting,
      required double dpiScale,
      required LoveGraphicsDefaultFilter defaultFilter,
    })?
    trueTypeFontLoader,
    Future<LoveFont?> Function({
      required double size,
      required String hinting,
      required double dpiScale,
      required LoveGraphicsDefaultFilter defaultFilter,
    })?
    defaultTrueTypeFontLoader,
    Future<Uint8List?> Function()? defaultTrueTypeFontDataLoader,
    LoveAudioBackendFactory? audioBackendFactory,
    LoveWindowMetrics? windowMetrics,
    List<LoveWindowDisplay>? windowDisplays,
    bool windowHasFocus = false,
    bool windowHasMouseFocus = false,
    LoveWindowMessageBoxHandler? windowMessageBoxHandler,
  }) : _clock = clock ?? SystemLoveClock(),
       _random = random ?? LoveRandomGenerator(),
       _keyboard = keyboard ?? LoveKeyboardState(),
       _mouse = mouse ?? LoveMouseState(),
       _touch = touch ?? LoveTouchState(),
       _joysticks = joysticks ?? LoveJoystickManager(),
       _system = system ?? LoveSystemState(),
       _graphics = graphics ?? LoveGraphicsFrame(),
       _images = Map<String, LoveImage>.from(
         images ?? const <String, LoveImage>{},
       ),
       _imageLoader = imageLoader,
       _trueTypeFontLoader = trueTypeFontLoader,
       _defaultTrueTypeFontLoader = defaultTrueTypeFontLoader,
       _defaultTrueTypeFontDataLoader = defaultTrueTypeFontDataLoader,
       _audioBackendFactory = audioBackendFactory,
       _windowMetrics = windowMetrics ?? const LoveWindowMetrics(),
       _windowDisplaysOverride = windowDisplays,
       _windowHasFocus = windowHasFocus,
       _windowHasMouseFocus = windowHasMouseFocus,
       _windowMessageBoxHandler = windowMessageBoxHandler;

  final LoveClock _clock;
  final LoveRandomGenerator _random;
  final LoveKeyboardState _keyboard;
  final LoveMouseState _mouse;
  final LoveTouchState _touch;
  final LoveJoystickManager _joysticks;
  final LoveSystemState _system;
  final LoveGraphicsFrame _graphics;
  final Map<String, LoveImage> _images;
  final Future<LoveImage> Function(
    String source, {
    Uint8List? bytes,
    Map<dynamic, dynamic>? settings,
  })?
  _imageLoader;
  final Future<LoveFont?> Function(
    String source, {
    required Uint8List bytes,
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  })?
  _trueTypeFontLoader;
  final Future<LoveFont?> Function({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  })?
  _defaultTrueTypeFontLoader;
  final Future<Uint8List?> Function()? _defaultTrueTypeFontDataLoader;
  final LoveAudioBackendFactory? _audioBackendFactory;
  LoveWindowMetrics _windowMetrics;
  List<LoveWindowDisplay>? _windowDisplaysOverride;
  bool _windowHasFocus;
  bool _windowHasMouseFocus;
  final LoveWindowMessageBoxHandler? _windowMessageBoxHandler;

  @override
  LoveClock get clock => _clock;

  @override
  bool get usesExternalFrameLoop => false;

  @override
  LoveRandomGenerator get random => _random;

  @override
  LoveKeyboardState get keyboard => _keyboard;

  @override
  LoveMouseState get mouse => _mouse;

  @override
  LoveTouchState get touch => _touch;

  @override
  LoveJoystickManager get joysticks => _joysticks;

  @override
  LoveSystemState get system => _system;

  @override
  LoveGraphicsFrame get graphics => _graphics;

  @override
  bool get requiresMountedFilesystemForRelativeResourcePaths => true;

  @override
  Future<LoveAudioSourceBackend> createAudioSourceBackend(
    String source, {
    required String sourceType,
    Uint8List? bytes,
    String? mimeType,
  }) async {
    final factory = _audioBackendFactory;
    if (factory != null) {
      return await factory(
        source,
        sourceType: sourceType,
        bytes: bytes,
        mimeType: mimeType,
      );
    }

    return const LoveNoopAudioSourceBackend();
  }

  @override
  Future<LoveImage> loadImage(
    String source, {
    Uint8List? bytes,
    Map<dynamic, dynamic>? settings,
  }) async {
    final cached = _images[source];
    if (cached != null) {
      return cached;
    }

    final loader = _imageLoader;
    if (loader != null) {
      final image = await loader(source, bytes: bytes, settings: settings);
      _images[source] = image;
      return image;
    }

    final resolvedBytes = bytes;
    if (resolvedBytes != null) {
      final imageData = LoveImageData.decodeEncodedBytes(
        bytes: resolvedBytes,
        source: source,
      );
      final image = LoveImage(
        source: source,
        width: imageData.width,
        height: imageData.height,
        imageData: imageData,
        preferImageDataRendering: true,
      );
      _images[source] = image;
      return image;
    }

    throw UnsupportedError('No headless image loader configured for "$source"');
  }

  @override
  Future<LoveFont?> loadTrueTypeFont(
    String source, {
    required Uint8List bytes,
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) async {
    final loader = _trueTypeFontLoader;
    if (loader == null) {
      return null;
    }

    return await loader(
      source,
      bytes: bytes,
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
  }

  @override
  Future<LoveFont?> loadDefaultTrueTypeFont({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) async {
    final loader = _defaultTrueTypeFontLoader;
    if (loader == null) {
      return null;
    }

    return await loader(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
  }

  @override
  Future<Uint8List?> loadDefaultTrueTypeFontBytes() async {
    final loader = _defaultTrueTypeFontDataLoader;
    if (loader == null) {
      return null;
    }

    return await loader();
  }

  @override
  int get imageCount => _images.length;

  @override
  String get rendererName => 'LuaLike Headless';

  @override
  String get rendererVersion => loveVersionString;

  @override
  String get rendererVendor => 'LuaLike';

  @override
  String get rendererDevice => 'HeadlessHost';

  @override
  LoveWindowMetrics get windowMetrics => _windowMetrics;

  @override
  set windowMetrics(LoveWindowMetrics value) {
    _windowMetrics = value;
  }

  @override
  List<LoveWindowDisplay> get windowDisplays =>
      _windowDisplaysOverride ??
      loveDefaultWindowDisplaysForMetrics(_windowMetrics);

  @override
  set windowDisplays(List<LoveWindowDisplay> value) {
    _windowDisplaysOverride = List<LoveWindowDisplay>.unmodifiable(value);
  }

  @override
  bool get windowHasFocus => _windowHasFocus;

  @override
  set windowHasFocus(bool value) {
    _windowHasFocus = value;
  }

  @override
  bool get windowHasMouseFocus => _windowHasMouseFocus;

  @override
  set windowHasMouseFocus(bool value) {
    _windowHasMouseFocus = value;
  }

  @override
  Future<LoveWindowMessageBoxResponse> showWindowMessageBox(
    LoveWindowMessageBoxData data,
  ) async {
    final handler = _windowMessageBoxHandler;
    if (handler != null) {
      return await handler(data);
    }

    return LoveWindowMessageBoxResponse(
      success: true,
      pressedButtonIndex: data.buttons.isEmpty ? 0 : 1,
    );
  }
}

List<LoveWindowDisplay> loveDefaultWindowDisplaysForMetrics(
  LoveWindowMetrics metrics,
) {
  final orientation = loveNormalizeWindowDisplayOrientation(
    metrics.desktopWidth >= metrics.desktopHeight ? 'landscape' : 'portrait',
  );
  final modes =
      List<LoveWindowFullscreenMode>.unmodifiable(<LoveWindowFullscreenMode>[
        LoveWindowFullscreenMode(
          width: metrics.desktopWidth,
          height: metrics.desktopHeight,
        ),
      ]);
  return List<LoveWindowDisplay>.unmodifiable(
    List<LoveWindowDisplay>.generate(
      math.max(metrics.display, 1),
      (index) => LoveWindowDisplay(
        name: 'Display ${index + 1}',
        orientation: orientation,
        fullscreenModes: modes,
      ),
      growable: false,
    ),
  );
}

class LoveRuntimeContext {
  LoveRuntimeContext({LoveHost? host}) : _host = host ?? LoveHeadlessHost() {
    _defaultGraphicsFont = _host.graphics.font;
    _resetTimerState();
  }

  static final Expando<LoveRuntimeContext> _contexts =
      Expando<LoveRuntimeContext>('love2d.runtime');

  LoveHost _host;
  LoveFont? _defaultGraphicsFont;
  bool deprecationOutput = true;

  late double _currentTime;
  late double _prevTime;
  late double _prevFpsUpdate;
  double _delta = 0;
  double _averageDelta = 0;
  int _fps = 0;
  int _frames = 0;
  final Set<LoveFont> _fonts = <LoveFont>{};
  final Set<LoveCanvas> _canvases = <LoveCanvas>{};
  final LoveEventState _events = LoveEventState();
  final LoveAudioState _audio = LoveAudioState();
  int _nextCanvasId = 0;

  LoveHost get host => _host;

  LoveWindowMetrics get windowMetrics => _host.windowMetrics;

  LoveRandomGenerator get random => _host.random;

  LoveKeyboardState get keyboard => _host.keyboard;

  LoveMouseState get mouse => _host.mouse;

  LoveTouchState get touch => _host.touch;

  LoveJoystickManager get joysticks => _host.joysticks;

  LoveEventState get events => _events;

  LoveAudioState get audio => _audio;

  LoveSystemState get system => _host.system;

  LoveGraphicsFrame get graphics => _host.graphics;

  double get time => _host.clock.nowSeconds();

  double get delta => _delta;

  double get averageDelta => _averageDelta;

  int get fps => _fps;

  static LoveRuntimeContext attach(LuaRuntime runtime, {LoveHost? host}) {
    final existing = _contexts[runtime];
    if (existing != null) {
      if (host != null) {
        existing.replaceHost(host);
      }
      return existing;
    }

    final context = LoveRuntimeContext(host: host);
    _contexts[runtime] = context;
    return context;
  }

  static LoveRuntimeContext of(LuaRuntime runtime) {
    return _contexts[runtime] ?? attach(runtime);
  }

  void replaceHost(LoveHost host) {
    _host = host;
    _clearLoveDefaultGraphicsFontState(this);
    _defaultGraphicsFont = _host.graphics.font;
    _resetTimerState();
  }

  Future<void> sleep(double seconds) => _host.clock.sleepSeconds(seconds);

  void beginDrawFrame() {
    graphics.beginFrame();
  }

  double step() {
    _frames++;
    _prevTime = _currentTime;
    _currentTime = time;
    _delta = _currentTime - _prevTime;

    final timeSinceLastUpdate = _currentTime - _prevFpsUpdate;
    if (timeSinceLastUpdate > 1) {
      _fps = ((_frames / timeSinceLastUpdate) + 0.5).floor();
      _averageDelta = timeSinceLastUpdate / _frames;
      _prevFpsUpdate = _currentTime;
      _frames = 0;
    }

    return _delta;
  }

  double stepExternal(double dt) {
    final nextDelta = dt.isFinite && dt >= 0 ? dt : 0.0;
    _frames++;
    _prevTime = _currentTime;
    _currentTime = _prevTime + nextDelta;
    _delta = nextDelta;

    final timeSinceLastUpdate = _currentTime - _prevFpsUpdate;
    if (timeSinceLastUpdate > 1) {
      _fps = ((_frames / timeSinceLastUpdate) + 0.5).floor();
      _averageDelta = timeSinceLastUpdate / _frames;
      _prevFpsUpdate = _currentTime;
      _frames = 0;
    }

    return _delta;
  }

  bool isVersionCompatibleString(String version) {
    return loveCompatibleVersions.contains(
      _canonicalizeCompatibilityVersion(version),
    );
  }

  bool isVersionCompatible({
    required int major,
    required int minor,
    int revision = 0,
  }) {
    return loveCompatibleVersions.contains('$major.$minor.$revision');
  }

  void _resetTimerState() {
    _currentTime = time;
    _prevTime = _currentTime;
    _prevFpsUpdate = _currentTime;
    _delta = 0;
    _averageDelta = 0;
    _fps = 0;
    _frames = 0;
  }

  void setDefaultGraphicsFont(LoveFont font) {
    _defaultGraphicsFont = font;
  }

  void registerFont(LoveFont font) {
    if (identical(font, _defaultGraphicsFont)) {
      return;
    }
    _fonts.add(font);
  }

  void registerCanvas(LoveCanvas canvas) {
    _canvases.add(canvas);
  }

  String nextCanvasSource() => '__love_canvas_${++_nextCanvasId}__';

  Map<dynamic, dynamic> graphicsStats({Map<dynamic, dynamic>? target}) {
    final map = target ?? <dynamic, dynamic>{};
    map['drawcalls'] = graphics.commands.length;
    map['drawcallsbatched'] = 0;
    map['canvasswitches'] = graphics.canvasSwitches;
    map['shaderswitches'] = graphics.shaderSwitches;
    map['canvases'] = _canvases.length;
    map['images'] = host.imageCount;
    map['fonts'] = _fonts.length + (_defaultGraphicsFont == null ? 0 : 1);
    map['texturememory'] = 0;
    return map;
  }
}

String _canonicalizeCompatibilityVersion(String version) {
  final separatorCount = '.'.allMatches(version).length;
  return separatorCount < 2 ? '$version.0' : version;
}

int _mipmapDimension(int dimension, int mipmap) {
  final clampedLevel = mipmap < 1 ? 1 : mipmap;
  final scale = 1 << (clampedLevel - 1);
  return math.max(1, dimension ~/ scale);
}

int _mipmapCountForDimensions(int width, int height) {
  var count = 1;
  var currentWidth = math.max(1, width);
  var currentHeight = math.max(1, height);
  while (currentWidth > 1 || currentHeight > 1) {
    currentWidth = math.max(1, currentWidth ~/ 2);
    currentHeight = math.max(1, currentHeight ~/ 2);
    count++;
  }
  return count;
}

bool _shaderEquals(LoveShader? left, LoveShader? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return left == right;
  }

  if (left.kind != right.kind ||
      left.pixelCode != right.pixelCode ||
      left.vertexCode != right.vertexCode) {
    return false;
  }

  final leftUniforms = left.uniforms;
  final rightUniforms = right.uniforms;
  if (leftUniforms.length != rightUniforms.length) {
    return false;
  }

  for (final entry in leftUniforms.entries) {
    if (!_shaderUniformEquals(entry.value, rightUniforms[entry.key])) {
      return false;
    }
  }

  return true;
}

bool _shaderUniformEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!_shaderUniformEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!_shaderUniformEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }

  return left == right;
}

double _clampColor(double value) {
  return switch (value) {
    < 0 => 0,
    > 1 => 1,
    _ => value,
  };
}
