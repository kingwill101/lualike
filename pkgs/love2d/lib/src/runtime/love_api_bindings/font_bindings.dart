part of '../love_api_bindings.dart';

/// Binds `love.font.newBMFontRasterizer`.
///
/// LOVE uses this constructor for AngelCode BMFont definitions plus optional
/// page image overrides.
LoveApiImplementation _bindFontNewBmFontRasterizer(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.font.newBMFontRasterizer';
    final rasterizer = await _bmFontRasterizerFromArgs(
      context,
      args,
      symbol: symbol,
    );
    return _wrapRasterizer(context, rasterizer);
  };
}

/// Binds `love.font.newGlyphData`.
///
/// This extracts a single glyph bitmap from an existing [LoveRasterizer].
LoveApiImplementation _bindFontNewGlyphData(
  LibraryRegistrationContext context,
) {
  return (args) {
    const symbol = 'love.font.newGlyphData';
    final rasterizer = _requireRasterizer(args, 0, symbol);
    final glyph = _coerceSingleGlyphLookupArgument(
      args,
      1,
      symbol: symbol,
      allowEmptyString: false,
    );
    return _wrapGlyphData(context, rasterizer.glyphDataForValue(glyph));
  };
}

/// Binds `love.font.newImageRasterizer`.
///
/// LOVE uses image rasterizers for glyph atlases where each code point is
/// mapped from a source image rather than a font file.
LoveApiImplementation _bindFontNewImageRasterizer(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.font.newImageRasterizer';
    final rasterizer = await _imageRasterizerFromArgs(
      context,
      args,
      symbol: symbol,
      kind: LoveRasterizerKind.image,
    );
    return _wrapRasterizer(context, rasterizer);
  };
}

/// Binds `love.font.newRasterizer`.
///
/// This dispatches to the TrueType, BMFont, or auto-detected file variants
/// based on the argument shapes that LOVE accepts.
LoveApiImplementation _bindFontNewRasterizer(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.font.newRasterizer';
    if (args.isEmpty ||
        _numberIfPresent(_valueAt(args, 0)) != null ||
        _numberIfPresent(_valueAt(args, 1)) != null) {
      final rasterizer = await _trueTypeRasterizerFromArgs(
        context,
        args,
        symbol: symbol,
      );
      return _wrapRasterizer(context, rasterizer);
    }

    if (_valueAt(args, 1) == null) {
      final rasterizer = await _autoRasterizerFromArgs(
        context,
        args,
        symbol: symbol,
      );
      return _wrapRasterizer(context, rasterizer);
    }

    final rasterizer = await _bmFontRasterizerFromArgs(
      context,
      args,
      symbol: symbol,
    );
    return _wrapRasterizer(context, rasterizer);
  };
}

/// Binds `love.font.newTrueTypeRasterizer`.
///
/// This keeps the explicit TrueType overload separate from the broader
/// `newRasterizer` dispatcher.
LoveApiImplementation _bindFontNewTrueTypeRasterizer(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.font.newTrueTypeRasterizer';
    final rasterizer = await _trueTypeRasterizerFromArgs(
      context,
      args,
      symbol: symbol,
    );
    return _wrapRasterizer(context, rasterizer);
  };
}

/// Builds a TrueType rasterizer from LOVE-style arguments.
///
/// A numeric first argument, or no arguments at all, selects the runtime's
/// default bundled font. Otherwise the first argument is treated as a
/// file-backed TrueType source.
Future<LoveRasterizer> _trueTypeRasterizerFromArgs(
  LibraryRegistrationContext context,
  List<Object?> args, {
  required String symbol,
}) async {
  final runtime = _runtimeContext(context);
  final first = _valueAt(args, 0);
  if (args.isEmpty || _numberIfPresent(first) != null) {
    final size = args.isEmpty
        ? LoveFont.defaultSize
        : _requireNumber(args, 0, symbol);
    final hinting = _optionalFontHintingArg(args, 1, symbol);
    final dpiScale = _optionalNumber(
      args,
      2,
      symbol,
      defaultValue: runtime.windowMetrics.dpiScale,
    );
    _validateTrueTypeFontSize(size, dpiScale);
    final sourceBytes = await runtime.host.loadDefaultTrueTypeFontBytes();
    return LoveRasterizer.trueType(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      sourceBytes: sourceBytes,
    );
  }

  final fileData = await _requireResourceFileData(context, first, symbol);
  if (!loveLooksLikeTrueTypeFontData(fileData.bytes)) {
    throw LuaError('Invalid font file: ${fileData.filename}');
  }
  final size = _optionalFontSizeArg(
    args,
    1,
    symbol,
    defaultValue: LoveFont.defaultSize,
  );
  final hinting = _optionalFontHintingArg(args, 2, symbol);
  final dpiScale = _optionalNumber(
    args,
    3,
    symbol,
    defaultValue: runtime.windowMetrics.dpiScale,
  );
  _validateTrueTypeFontSize(size, dpiScale);
  return LoveRasterizer.trueType(
    size: size,
    hinting: hinting,
    dpiScale: dpiScale,
    source: fileData.filename,
    sourceBytes: fileData.bytes,
  );
}

/// Builds a rasterizer by sniffing the first file-backed argument.
///
/// LOVE accepts either BMFont definition files or TrueType data for this
/// overload and chooses the matching rasterizer type automatically.
Future<LoveRasterizer> _autoRasterizerFromArgs(
  LibraryRegistrationContext context,
  List<Object?> args, {
  required String symbol,
}) async {
  final runtime = _runtimeContext(context);
  final fileData = await _requireResourceFileData(
    context,
    _valueAt(args, 0),
    symbol,
  );
  if (loveLooksLikeBmFontDefinition(fileData.bytes)) {
    return _bmFontRasterizerFromFileData(
      context,
      fileData,
      symbol: symbol,
      pageImages: const <int, LoveImageData>{},
      dpiScale: 1.0,
    );
  }

  if (!loveLooksLikeTrueTypeFontData(fileData.bytes)) {
    throw LuaError('Invalid font file: ${fileData.filename}');
  }

  return LoveRasterizer.trueType(
    size: LoveFont.defaultSize,
    hinting: 'normal',
    dpiScale: runtime.windowMetrics.dpiScale,
    source: fileData.filename,
    sourceBytes: fileData.bytes,
  );
}

/// Builds a BMFont rasterizer from a definition file and optional page images.
Future<LoveRasterizer> _bmFontRasterizerFromArgs(
  LibraryRegistrationContext context,
  List<Object?> args, {
  required String symbol,
}) async {
  if (args.isEmpty) {
    throw LuaError('$symbol expects at least 1 argument');
  }

  final fileData = await _requireResourceFileData(
    context,
    _valueAt(args, 0),
    symbol,
  );
  final pageImages = await _resolveBmFontPageImages(
    context,
    _valueAt(args, 1),
    symbol: symbol,
  );
  final dpiScale = _optionalFontDpiScaleArg(args, 2, symbol, defaultValue: 1.0);
  return _bmFontRasterizerFromFileData(
    context,
    fileData,
    symbol: symbol,
    pageImages: pageImages,
    dpiScale: dpiScale,
  );
}

/// Parses a BMFont definition, resolves any missing page images, and returns a
/// validated BMFont rasterizer.
Future<LoveRasterizer> _bmFontRasterizerFromFileData(
  LibraryRegistrationContext context,
  LoveFilesystemFileData fileData, {
  required String symbol,
  required Map<int, LoveImageData> pageImages,
  required double dpiScale,
}) async {
  final definition = _parseBmFontDefinition(fileData, symbol: symbol);
  final resolvedPages = Map<int, LoveImageData>.from(pageImages);

  for (final entry in definition.pageSources.entries) {
    if (resolvedPages.containsKey(entry.key)) {
      continue;
    }

    final pageSource = _resolveBmFontPageSource(definition, entry.key);
    if (pageSource == null || pageSource.isEmpty) {
      throw LuaError('$symbol missing image for BMFont page ${entry.key}');
    }

    resolvedPages[entry.key] = await _loadImageDataFromSource(
      context,
      pageSource,
      symbol: symbol,
    );
  }

  for (final imageData in resolvedPages.values) {
    _validateBmFontPageImageData(imageData);
  }

  _validateBmFontDefinition(definition, resolvedPages);
  return LoveRasterizer.bmFont(
    definition: definition,
    pageImages: resolvedPages,
    dpiScale: dpiScale,
    source: fileData.filename,
  );
}

/// Parses a BMFont definition file and surfaces parse failures as [LuaError].
LoveBmFontDefinition _parseBmFontDefinition(
  LoveFilesystemFileData fileData, {
  required String symbol,
}) {
  try {
    return parseLoveBmFontDefinition(
      bytes: fileData.bytes,
      source: fileData.filename,
    );
  } on ArgumentError catch (error) {
    throw LuaError('${error.message}');
  }
}

/// Resolves the optional BMFont page-image argument into page-indexed image
/// data.
///
/// LOVE accepts a single image-like value for page `0` or a Lua table of page
/// images indexed in order.
Future<Map<int, LoveImageData>> _resolveBmFontPageImages(
  LibraryRegistrationContext context,
  Object? value, {
  required String symbol,
}) async {
  if (value == null) {
    return <int, LoveImageData>{};
  }

  if (_imageDataIfPresent(value) != null ||
      _stringLike(value) != null ||
      _filesystemFileDataCompatIfPresent(value) != null) {
    final resolved = await _resolveFontImageSource(
      context,
      value,
      symbol: symbol,
    );
    return <int, LoveImageData>{0: resolved.$1};
  }

  final table = _tableIfPresent(value);
  if (table != null) {
    final images = <int, LoveImageData>{};
    for (var pageIndex = 1; ; pageIndex++) {
      final entry = _tableIndexedEntry(table, pageIndex);
      if (entry == null) {
        break;
      }

      final resolved = await _resolveFontImageSource(
        context,
        entry,
        symbol: symbol,
      );
      images[pageIndex - 1] = resolved.$1;
    }
    return images;
  }

  final resolved = await _resolveFontImageSource(
    context,
    value,
    symbol: symbol,
  );
  return <int, LoveImageData>{0: resolved.$1};
}

/// Resolves a BMFont page source relative to the definition file when needed.
String? _resolveBmFontPageSource(LoveBmFontDefinition definition, int pageId) {
  final rawSource = definition.pageSources[pageId];
  if (rawSource == null || rawSource.isEmpty) {
    return null;
  }

  final normalizedPageSource = rawSource.replaceAll('\\', '/');
  if (normalizedPageSource.startsWith('/') ||
      normalizedPageSource.contains('://') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalizedPageSource)) {
    return normalizedPageSource;
  }

  final normalizedFontSource = definition.source.replaceAll('\\', '/');
  final separatorIndex = normalizedFontSource.lastIndexOf('/');
  if (separatorIndex < 0) {
    return normalizedPageSource;
  }

  return '${normalizedFontSource.substring(0, separatorIndex)}/'
      '$normalizedPageSource';
}

/// Validates that BMFont glyph rectangles refer to loaded pages and fit within
/// their image bounds.
void _validateBmFontDefinition(
  LoveBmFontDefinition definition,
  Map<int, LoveImageData> pageImages,
) {
  for (final entry in definition.characters.entries) {
    final glyph = entry.key;
    final character = entry.value;
    if (!definition.unicode && glyph > 127) {
      throw LuaError(
        'Invalid BMFont character id '
        '(only unicode and ASCII are supported)',
      );
    }

    final page = pageImages[character.page];
    if (page == null) {
      throw LuaError('Invalid BMFont character page id: ${character.page}');
    }
    if (character.x < 0 ||
        character.y < 0 ||
        character.x >= page.width ||
        character.y >= page.height) {
      throw LuaError('Invalid coordinates for BMFont character $glyph.');
    }
    if (character.width > 0 && character.x + character.width > page.width) {
      throw LuaError(
        'Invalid width ${character.width} for BMFont character $glyph.',
      );
    }
    if (character.height > 0 && character.y + character.height > page.height) {
      throw LuaError(
        'Invalid height ${character.height} for BMFont character $glyph.',
      );
    }
  }
}

/// Builds an image-based rasterizer from an image source plus glyph ordering.
///
/// Some LOVE call sites pass only glyphs and DPI after the source image, while
/// others also include explicit extra spacing.
Future<LoveRasterizer> _imageRasterizerFromArgs(
  LibraryRegistrationContext context,
  List<Object?> args, {
  required String symbol,
  required LoveRasterizerKind kind,
  bool shorthandDpiOnly = false,
}) async {
  final resolved = await _resolveFontImageSource(
    context,
    _valueAt(args, 0),
    symbol: symbol,
  );
  final glyphs =
      _strictFontStringLike(
        _valueAt(args, 1),
        symbol: symbol,
        argumentIndex: 2,
      ) ??
      (throw LuaError('$symbol expected a string at argument 2'));
  final extraSpacing = shorthandDpiOnly
      ? 0
      : _optionalFontExtraSpacingArg(args, 2, symbol, defaultValue: 0);
  final dpiIndex = shorthandDpiOnly ? 2 : 3;
  final dpiScale = _optionalFontDpiScaleArg(
    args,
    dpiIndex,
    symbol,
    defaultValue: 1.0,
  );
  _validateImageFontImageData(resolved.$1, symbol: symbol);
  return LoveRasterizer.image(
    imageData: resolved.$1,
    glyphs: glyphs,
    extraSpacing: extraSpacing,
    dpiScale: dpiScale,
    source: resolved.$2,
    kind: kind,
  );
}

/// Returns an optional extra glyph-spacing argument using LOVE's numeric
/// truncation rules.
int _optionalFontExtraSpacingArg(
  List<Object?> args,
  int index,
  String symbol, {
  required int defaultValue,
}) {
  if (args.length <= index || _valueAt(args, index) == null) {
    return defaultValue;
  }

  return _truncateLoveFontNumericValue(_requireNumber(args, index, symbol));
}

/// Resolves an image-font source into decoded image data plus an optional
/// source path.
///
/// LOVE accepts `ImageData` directly, a filename-like source string, or a
/// file-backed object that can be decoded as encoded image bytes.
Future<(LoveImageData, String?)> _resolveFontImageSource(
  LibraryRegistrationContext context,
  Object? value, {
  required String symbol,
}) async {
  final imageData = _imageDataIfPresent(value);
  if (imageData != null) {
    return (imageData, null);
  }

  final source = _stringLike(value);
  if (source != null) {
    return (
      await _loadImageDataFromSource(context, source, symbol: symbol),
      source,
    );
  }

  final fileData = await _requireResourceFileData(
    context,
    value,
    symbol,
    expectedKinds: 'filename, FileData, File, or ImageData',
  );
  return (
    LoveImageData.decodeEncodedBytes(
      bytes: fileData.bytes,
      source: fileData.filename,
    ),
    fileData.filename,
  );
}

/// Validates that an image-font source uses LOVE's supported RGBA8 format.
void _validateImageFontImageData(
  LoveImageData imageData, {
  required String symbol,
}) {
  if (imageData.format.toLowerCase() != 'rgba8') {
    throw LuaError('Only 32-bit RGBA images are supported in Image Fonts!');
  }
}

/// Validates that a BMFont page image uses LOVE's supported RGBA8 format.
void _validateBmFontPageImageData(LoveImageData imageData) {
  if (imageData.format.toLowerCase() != 'rgba8') {
    throw LuaError('Only 32-bit RGBA images are supported in BMFonts.');
  }
}

/// Parses a required font DPI scale argument.
double _fontDpiScale(List<Object?> args, int index, String symbol) {
  return _requireNumber(args, index, symbol);
}
