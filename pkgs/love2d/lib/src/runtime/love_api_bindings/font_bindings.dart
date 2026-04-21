part of '../love_api_bindings.dart';

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
    _validateFontSize(size, symbol);
    final hinting = _optionalFontHintingArg(args, 1, symbol);
    final dpiScale = _optionalFontDpiScaleArg(
      args,
      2,
      symbol,
      defaultValue: runtime.windowMetrics.dpiScale,
    );
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
    throw LuaError('$symbol invalid font file "${fileData.filename}"');
  }
  final size = _optionalFontSizeArg(
    args,
    1,
    symbol,
    defaultValue: LoveFont.defaultSize,
  );
  _validateFontSize(size, symbol);
  final hinting = _optionalFontHintingArg(args, 2, symbol);
  final dpiScale = _optionalFontDpiScaleArg(
    args,
    3,
    symbol,
    defaultValue: runtime.windowMetrics.dpiScale,
  );
  return LoveRasterizer.trueType(
    size: size,
    hinting: hinting,
    dpiScale: dpiScale,
    source: fileData.filename,
    sourceBytes: fileData.bytes,
  );
}

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
    throw LuaError('$symbol invalid font file "${fileData.filename}"');
  }

  return LoveRasterizer.trueType(
    size: LoveFont.defaultSize,
    hinting: 'normal',
    dpiScale: runtime.windowMetrics.dpiScale,
    source: fileData.filename,
    sourceBytes: fileData.bytes,
  );
}

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

  _validateBmFontDefinition(definition, resolvedPages, symbol: symbol);
  return LoveRasterizer.bmFont(
    definition: definition,
    pageImages: resolvedPages,
    dpiScale: dpiScale,
    source: fileData.filename,
  );
}

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
    throw LuaError('$symbol ${error.message}');
  }
}

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

void _validateBmFontDefinition(
  LoveBmFontDefinition definition,
  Map<int, LoveImageData> pageImages, {
  required String symbol,
}) {
  for (final entry in definition.characters.entries) {
    final glyph = entry.key;
    final character = entry.value;
    if (!definition.unicode && glyph > 127) {
      throw LuaError(
        '$symbol invalid BMFont character id '
        '(only unicode and ASCII are supported)',
      );
    }

    final page = pageImages[character.page];
    if (page == null) {
      throw LuaError(
        '$symbol invalid BMFont character page id: ${character.page}',
      );
    }

    if (character.width < 0) {
      throw LuaError(
        '$symbol invalid width ${character.width} for BMFont character $glyph',
      );
    }
    if (character.height < 0) {
      throw LuaError(
        '$symbol invalid height ${character.height} for BMFont character $glyph',
      );
    }
    if (character.x < 0 ||
        character.y < 0 ||
        character.x >= page.width ||
        character.y >= page.height) {
      throw LuaError('$symbol invalid coordinates for BMFont character $glyph');
    }
    if (character.width > 0 && character.x + character.width > page.width) {
      throw LuaError(
        '$symbol invalid width ${character.width} for BMFont character $glyph',
      );
    }
    if (character.height > 0 && character.y + character.height > page.height) {
      throw LuaError(
        '$symbol invalid height ${character.height} for BMFont character $glyph',
      );
    }
  }
}

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

void _validateImageFontImageData(
  LoveImageData imageData, {
  required String symbol,
}) {
  if (imageData.format.toLowerCase() != 'rgba8') {
    throw LuaError(
      '$symbol only 32-bit RGBA images are supported in Image Fonts!',
    );
  }
}

double _fontDpiScale(List<Object?> args, int index, String symbol) {
  final dpiScale = _requireNumber(args, index, symbol);
  if (dpiScale <= 0) {
    throw LuaError('$symbol dpiscale must be > 0');
  }
  return dpiScale;
}
