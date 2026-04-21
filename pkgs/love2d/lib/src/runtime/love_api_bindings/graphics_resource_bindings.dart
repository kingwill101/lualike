part of '../love_api_bindings.dart';

LoveApiImplementation _bindGraphicsGetWidth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.width;
}

LoveApiImplementation _bindGraphicsGetHeight(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.height;
}

LoveApiImplementation _bindGraphicsGetDimensions(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    runtime.windowMetrics.width,
    runtime.windowMetrics.height,
  ]);
}

LoveApiImplementation _bindGraphicsGetFont(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final font = await runtime.ensureCurrentGraphicsFont();
    return _wrapFont(context, font);
  };
}

({double dpiScale, bool linear, bool mipmaps}) _newImageSettings(
  Map<dynamic, dynamic>? settings, {
  required String symbol,
  String? source,
}) {
  final explicitDpiScale = settings == null
      ? null
      : _numberIfPresent(_tableEntry(settings, 'dpiscale'));
  final resolvedDpiScale =
      explicitDpiScale ?? _sourceImageDpiScale(source) ?? 1.0;
  if (resolvedDpiScale <= 0) {
    throw LuaError('$symbol dpiscale must be > 0');
  }

  return (
    dpiScale: resolvedDpiScale,
    linear: settings == null
        ? false
        : (_tableBool(settings, 'linear') ?? false),
    mipmaps: settings == null
        ? false
        : (_tableBool(settings, 'mipmaps') ?? false),
  );
}

double? _sourceImageDpiScale(String? source) {
  if (source == null || source.isEmpty) {
    return null;
  }

  final match = RegExp(
    r'@(\d+)x(?:\.[^./\\]+)?$',
    caseSensitive: false,
  ).firstMatch(source);
  if (match == null) {
    return null;
  }

  return double.tryParse(match.group(1)!);
}

int _logicalTextureDimension(int pixels, double dpiScale) {
  if (dpiScale <= 0) {
    return pixels;
  }
  return math.max(1, (pixels / dpiScale).round());
}

int _imageMipmapCountForDimensions(int width, int height) {
  var levels = 1;
  var currentWidth = math.max(1, width);
  var currentHeight = math.max(1, height);

  while (currentWidth > 1 || currentHeight > 1) {
    currentWidth = math.max(1, (currentWidth / 2).floor());
    currentHeight = math.max(1, (currentHeight / 2).floor());
    levels++;
  }

  return levels;
}

LoveImage _resolveImageFromImageData({
  required LoveImageData imageData,
  required String source,
  required LoveGraphicsDefaultFilter defaultFilter,
  required Map<dynamic, dynamic>? settings,
  Object? nativeImage,
}) {
  final resolvedSettings = _newImageSettings(
    settings,
    symbol: 'love.graphics.newImage',
    source: source,
  );
  final mipmaps = resolvedSettings.mipmaps
      ? imageData.generateMipmaps()
      : <LoveImageData>[imageData];

  return LoveImage(
    source: source,
    width: _logicalTextureDimension(imageData.width, resolvedSettings.dpiScale),
    height: _logicalTextureDimension(
      imageData.height,
      resolvedSettings.dpiScale,
    ),
    pixelWidth: imageData.width,
    pixelHeight: imageData.height,
    dpiScale: resolvedSettings.dpiScale,
    format: imageData.format,
    readable: true,
    mipmapCount: mipmaps.length,
    filter: defaultFilter,
    formatLinear: resolvedSettings.linear,
    imageData: mipmaps.first,
    imageDataMipmaps: mipmaps,
    preferImageDataRendering: true,
    nativeImage: nativeImage,
  );
}

LoveImage _resolveImageSettings(
  LoveImage image, {
  required Map<dynamic, dynamic>? settings,
}) {
  final resolvedSettings = _newImageSettings(
    settings,
    symbol: 'love.graphics.newImage',
    source: image.source,
  );
  final logicalWidth = _logicalTextureDimension(
    image.pixelWidth,
    resolvedSettings.dpiScale,
  );
  final logicalHeight = _logicalTextureDimension(
    image.pixelHeight,
    resolvedSettings.dpiScale,
  );

  final imageData = image.imageData;
  if (imageData != null) {
    final mipmaps = resolvedSettings.mipmaps
        ? imageData.generateMipmaps()
        : <LoveImageData>[imageData];
    return image.copyWith(
      width: logicalWidth,
      height: logicalHeight,
      pixelWidth: imageData.width,
      pixelHeight: imageData.height,
      dpiScale: resolvedSettings.dpiScale,
      format: image.format,
      readable: true,
      mipmapCount: mipmaps.length,
      filter: image.filter,
      formatLinear: image.compressed
          ? image.formatLinear
          : resolvedSettings.linear,
      imageData: mipmaps.first,
      imageDataMipmaps: mipmaps,
      preferImageDataRendering: true,
    );
  }

  final mipmapCount = image.compressed
      ? image.mipmapCount
      : (resolvedSettings.mipmaps
            ? _imageMipmapCountForDimensions(
                image.pixelWidth,
                image.pixelHeight,
              )
            : 1);
  return image.copyWith(
    width: logicalWidth,
    height: logicalHeight,
    dpiScale: resolvedSettings.dpiScale,
    mipmapCount: mipmapCount,
    formatLinear: image.compressed
        ? image.formatLinear
        : resolvedSettings.linear,
  );
}

Future<LoveImage> _loadImageFromSource(
  LibraryRegistrationContext context,
  String source, {
  required String symbol,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
}) async {
  final runtime = _runtimeContext(context);
  final fileData = await _requireResourceFileData(context, source, symbol);
  final bytes = Uint8List.fromList(fileData.bytes);

  try {
    final image = await runtime.host.loadImage(
      source,
      bytes: bytes,
      settings: settings,
    );
    return _resolveImageSettings(
      image.copyWith(filter: defaultFilter),
      settings: settings,
    );
  } catch (hostError) {
    final imageData = LoveImageData.decodeEncodedBytes(
      bytes: fileData.bytes,
      source: fileData.filename,
    );
    return _resolveImageFromImageData(
      imageData: imageData,
      source: fileData.filename,
      defaultFilter: defaultFilter,
      settings: settings,
    );
  }
}

Future<LoveImageData> _loadImageDataFromSource(
  LibraryRegistrationContext context,
  String source, {
  required String symbol,
}) async {
  final runtime = _runtimeContext(context);
  final fileData = await _requireResourceFileData(context, source, symbol);
  final bytes = Uint8List.fromList(fileData.bytes);

  try {
    final image = await runtime.host.loadImage(source, bytes: bytes);
    final imageData = image.imageData;
    if (imageData != null) {
      return imageData.clone();
    }
  } catch (hostError) {
    // Fall back to the pure Dart decoder below.
  }

  return LoveImageData.decodeEncodedBytes(
    bytes: fileData.bytes,
    source: fileData.filename,
  );
}

LoveApiImplementation _bindGraphicsNewImage(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.graphics.newImage';
    final settings = args.length >= 2
        ? _optionalTableTarget(_valueAt(args, 1))?.$2
        : null;
    final imageData = _imageDataIfPresent(_valueAt(args, 0));
    if (imageData != null) {
      return _wrapImage(
        context,
        _resolveImageFromImageData(
          imageData: imageData,
          source: 'ImageData',
          defaultFilter: runtime.graphics.defaultFilter,
          settings: settings,
        ),
      );
    }

    final compressedImageData = _compressedImageDataIfPresent(
      _valueAt(args, 0),
    );
    if (compressedImageData != null) {
      final resolvedSettings = _newImageSettings(
        settings,
        symbol: symbol,
        source: compressedImageData.source,
      );
      return _wrapImage(
        context,
        LoveImage(
          source: compressedImageData.source,
          width: _logicalTextureDimension(
            compressedImageData.width,
            resolvedSettings.dpiScale,
          ),
          height: _logicalTextureDimension(
            compressedImageData.height,
            resolvedSettings.dpiScale,
          ),
          pixelWidth: compressedImageData.width,
          pixelHeight: compressedImageData.height,
          dpiScale: resolvedSettings.dpiScale,
          format: compressedImageData.format,
          readable: false,
          mipmapCount: compressedImageData.mipmapCount,
          filter: runtime.graphics.defaultFilter,
          compressed: true,
          formatLinear: !compressedImageData.srgb,
        ),
      );
    }

    final sourceValue = _valueAt(args, 0);
    final source = _stringLike(sourceValue);
    if (source != null) {
      try {
        final image = await _loadImageFromSource(
          context,
          source,
          symbol: symbol,
          settings: settings,
          defaultFilter: runtime.graphics.defaultFilter,
        );
        return _wrapImage(context, image);
      } catch (error) {
        if (error is LuaError) {
          rethrow;
        }
        throw LuaError('$symbol failed to load "$source": $error');
      }
    }

    try {
      final fileData = await _requireResourceFileData(
        context,
        sourceValue,
        symbol,
        expectedKinds:
            'filename, FileData, File, ImageData, or CompressedImageData',
      );
      try {
        final imageData = LoveImageData.decodeEncodedBytes(
          bytes: fileData.bytes,
          source: fileData.filename,
        );
        return _wrapImage(
          context,
          _resolveImageFromImageData(
            imageData: imageData,
            source: fileData.filename,
            defaultFilter: runtime.graphics.defaultFilter,
            settings: settings,
          ),
        );
      } catch (error) {
        throw LuaError('$symbol failed to load "${fileData.filename}": $error');
      }
    } on LuaError {
      rethrow;
    }
  };
}

LoveApiImplementation _bindGraphicsNewQuad(LibraryRegistrationContext context) {
  return (args) {
    final x = _requireNumber(args, 0, 'love.graphics.newQuad');
    final y = _requireNumber(args, 1, 'love.graphics.newQuad');
    final width = _requireNumber(args, 2, 'love.graphics.newQuad');
    final height = _requireNumber(args, 3, 'love.graphics.newQuad');
    final textureWidth = _numberIfPresent(_valueAt(args, 4));
    final textureHeight = _numberIfPresent(_valueAt(args, 5));

    if (textureWidth != null && textureHeight != null) {
      return _wrapQuad(
        context,
        LoveQuad(
          x: x,
          y: y,
          width: width,
          height: height,
          textureWidth: textureWidth,
          textureHeight: textureHeight,
        ),
      );
    }

    final image = _imageIfPresent(_valueAt(args, 4));
    if (image != null) {
      return _wrapQuad(
        context,
        LoveQuad(
          x: x,
          y: y,
          width: width,
          height: height,
          textureWidth: image.width.toDouble(),
          textureHeight: image.height.toDouble(),
        ),
      );
    }

    throw LuaError(
      'love.graphics.newQuad expected texture dimensions or an Image at argument 5',
    );
  };
}

LoveApiImplementation _bindGraphicsNewFont(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final font = await _loadFontFromArgs(
      context,
      args,
      'love.graphics.newFont',
      defaultFilter: runtime.graphics.defaultFilter,
    );
    runtime.registerFont(font);
    return _wrapFont(context, font);
  };
}

LoveApiImplementation _bindGraphicsNewImageFont(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.graphics.newImageFont';
    final rasterizer = _rasterizerIfPresent(_valueAt(args, 0));
    if (rasterizer != null) {
      final font = rasterizer.toLoveFont(
        defaultFilter: runtime.graphics.defaultFilter,
      );
      runtime.registerFont(font);
      return _wrapFont(context, font);
    }

    final glyphs =
        _strictFontStringLike(
          _valueAt(args, 1),
          symbol: symbol,
          argumentIndex: 2,
        ) ??
        (throw LuaError('$symbol expected a string at argument 2'));
    final extraSpacing = _optionalFontExtraSpacingArg(
      args,
      2,
      symbol,
      defaultValue: 0,
    );
    final dpiScale = _optionalFontDpiScaleArg(
      args,
      3,
      symbol,
      defaultValue: 1.0,
    );
    final resolved = await _resolveFontImageSource(
      context,
      _valueAt(args, 0),
      symbol: symbol,
    );
    final imageData = resolved.$1;
    final source = resolved.$2;

    final font = _imageFontFromImageData(
      imageData,
      symbol: symbol,
      glyphs: glyphs,
      extraSpacing: extraSpacing,
      dpiScale: dpiScale,
      source: source,
      defaultFilter: runtime.graphics.defaultFilter,
    );
    runtime.registerFont(font);
    return _wrapFont(context, font);
  };
}

LoveApiImplementation _bindGraphicsNewText(LibraryRegistrationContext context) {
  return (args) {
    const symbol = 'love.graphics.newText';
    final font = _requireFont(args, 0, symbol);
    final text = LoveTextDrawable(font: font);
    if (args.length >= 2 && _valueAt(args, 1) != null) {
      text.set(_requireColoredTextSpans(args, 1, symbol));
    }
    return _wrapTextDrawable(context, text);
  };
}

LoveApiImplementation _bindGraphicsSetFont(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final font = _requireFont(args, 0, 'love.graphics.setFont');
    runtime.registerFont(font);
    runtime.graphics.font = font;
    return null;
  };
}

LoveApiImplementation _bindGraphicsSetNewFont(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    final font = await _loadFontFromArgs(
      context,
      args,
      'love.graphics.setNewFont',
      defaultFilter: runtime.graphics.defaultFilter,
    );
    runtime.registerFont(font);
    runtime.graphics.font = font;
    return _wrapFont(context, font);
  };
}

LoveFont _imageFontFromImageData(
  LoveImageData imageData, {
  required String symbol,
  required String glyphs,
  required int extraSpacing,
  required double dpiScale,
  String? source,
  required LoveGraphicsDefaultFilter defaultFilter,
}) {
  _validateImageFontImageData(imageData, symbol: symbol);
  return LoveRasterizer.image(
    imageData: imageData,
    glyphs: glyphs,
    extraSpacing: extraSpacing,
    dpiScale: dpiScale,
    source: source,
  ).toLoveFont(defaultFilter: defaultFilter);
}

LoveApiImplementation _bindGraphicsSetDefaultFilter(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final min = _filterMode(
      _requireString(args, 0, 'love.graphics.setDefaultFilter'),
      'love.graphics.setDefaultFilter',
    );
    final mag = args.length >= 2
        ? _filterMode(
            _requireString(args, 1, 'love.graphics.setDefaultFilter'),
            'love.graphics.setDefaultFilter',
          )
        : min;
    final anisotropy = args.length >= 3
        ? _requireNumber(args, 2, 'love.graphics.setDefaultFilter')
        : 1.0;
    runtime.graphics.defaultFilter = LoveGraphicsDefaultFilter(
      min: min,
      mag: mag,
      anisotropy: anisotropy,
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetDefaultFilter(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => _filterResult(runtime.graphics.defaultFilter);
}
