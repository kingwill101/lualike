part of '../love_api_bindings.dart';

LoveRuntimeContext _runtimeContext(LibraryRegistrationContext context) {
  final runtime = context.interpreter;
  if (runtime == null) {
    throw StateError('No Lua runtime available for LOVE bindings');
  }

  return LoveRuntimeContext.attach(runtime);
}

LoveWindowMetrics _windowMetricsFromArgs(
  LoveWindowMetrics current,
  List<Object?> args, {
  required String symbol,
  required bool mergeExistingFlags,
}) {
  final width = args.isNotEmpty
      ? _requireRoundedInt(args, 0, symbol)
      : current.width;
  final height = args.length >= 2
      ? _requireRoundedInt(args, 1, symbol)
      : current.height;
  final flags = args.length >= 3
      ? _optionalTableTarget(_valueAt(args, 2))?.$2
      : null;

  final resolvedWidth = width == 0 ? current.desktopWidth : width;
  final resolvedHeight = height == 0 ? current.desktopHeight : height;
  var next = current.copyWith(width: resolvedWidth, height: resolvedHeight);

  if (!mergeExistingFlags && flags == null) {
    return next.copyWith(
      fullscreen: false,
      fullscreenType: current.fullscreenType,
      vsync: current.vsync,
      maximized: false,
      msaa: current.msaa,
      resizable: false,
      borderless: false,
      centered: true,
      display: current.display,
      minWidth: current.minWidth,
      minHeight: current.minHeight,
      highDpi: false,
      refreshRate: current.refreshRate,
    );
  }

  if (flags == null) {
    return next;
  }

  next = next.copyWith(
    fullscreen: _tableBool(flags, 'fullscreen') ?? next.fullscreen,
    fullscreenType:
        _tableString(flags, 'fullscreentype') ?? next.fullscreenType,
    vsync: _tableRoundedInt(flags, 'vsync') ?? next.vsync,
    msaa: _tableRoundedInt(flags, 'msaa') ?? next.msaa,
    resizable: _tableBool(flags, 'resizable') ?? next.resizable,
    borderless: _tableBool(flags, 'borderless') ?? next.borderless,
    centered: _tableBool(flags, 'centered') ?? next.centered,
    display: _tableRoundedInt(flags, 'display') ?? next.display,
    minWidth: _tableRoundedInt(flags, 'minwidth') ?? next.minWidth,
    minHeight: _tableRoundedInt(flags, 'minheight') ?? next.minHeight,
    highDpi: _tableBool(flags, 'highdpi') ?? next.highDpi,
    refreshRate: _tableRoundedInt(flags, 'refreshrate') ?? next.refreshRate,
  );
  if (next.fullscreen || !next.resizable) {
    next = next.copyWith(maximized: false);
  }
  return next;
}

Value _colorResult(LoveColor color) {
  return Value.multi(<Object?>[color.r, color.g, color.b, color.a]);
}

LoveColor _requireColor(List<Object?> args, int index, String symbol) {
  final value = _valueAt(args, index);
  final table = switch (value) {
    final Value wrapped when wrapped.raw is Map =>
      wrapped.raw as Map<dynamic, dynamic>,
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table != null && _looksLikeColorTable(table)) {
    return LoveColor(
      _tableIndexedNumber(table, 1, symbol),
      _tableIndexedNumber(table, 2, symbol),
      _tableIndexedNumber(table, 3, symbol),
      _tableIndexedNumber(table, 4, symbol, defaultValue: 1.0),
    );
  }

  return LoveColor(
    _requireNumber(args, index, symbol),
    _requireNumber(args, index + 1, symbol),
    _requireNumber(args, index + 2, symbol),
    args.length > index + 3 ? _requireNumber(args, index + 3, symbol) : 1.0,
  );
}

LoveGraphicsDrawMode _requireDrawMode(
  List<Object?> args,
  int index,
  String symbol,
) {
  return switch (_requireString(args, index, symbol)) {
    'fill' => LoveGraphicsDrawMode.fill,
    'line' => LoveGraphicsDrawMode.line,
    final value => throw LuaError('$symbol invalid draw mode "$value"'),
  };
}

LoveGraphicsStackType _graphicsStackType(Object? value, String symbol) {
  return switch (_stringLike(value)) {
    null || 'transform' => LoveGraphicsStackType.transform,
    'all' => LoveGraphicsStackType.all,
    final stackType => throw LuaError(
      '$symbol invalid graphics stack type "$stackType"',
    ),
  };
}

LoveGraphicsArcMode _requireArcMode(String value, String symbol) {
  return switch (value) {
    'open' => LoveGraphicsArcMode.open,
    'closed' => LoveGraphicsArcMode.closed,
    'pie' => LoveGraphicsArcMode.pie,
    _ => throw LuaError('$symbol invalid arc mode "$value"'),
  };
}

LoveGraphicsLineStyle _lineStyle(String value, String symbol) {
  return switch (value) {
    'smooth' => LoveGraphicsLineStyle.smooth,
    'rough' => LoveGraphicsLineStyle.rough,
    _ => throw LuaError('$symbol invalid line style "$value"'),
  };
}

LoveGraphicsLineJoin _lineJoin(String value, String symbol) {
  return switch (value) {
    'none' => LoveGraphicsLineJoin.none,
    'miter' => LoveGraphicsLineJoin.miter,
    'bevel' => LoveGraphicsLineJoin.bevel,
    _ => throw LuaError('$symbol invalid line join "$value"'),
  };
}

LoveGraphicsBlendMode _blendMode(String value, String symbol) {
  return switch (value) {
    'alpha' => LoveGraphicsBlendMode.alpha,
    'add' => LoveGraphicsBlendMode.add,
    'subtract' => LoveGraphicsBlendMode.subtract,
    'multiply' => LoveGraphicsBlendMode.multiply,
    'lighten' => LoveGraphicsBlendMode.lighten,
    'darken' => LoveGraphicsBlendMode.darken,
    'screen' => LoveGraphicsBlendMode.screen,
    'replace' => LoveGraphicsBlendMode.replace,
    'none' => LoveGraphicsBlendMode.none,
    _ => throw LuaError('$symbol invalid blend mode "$value"'),
  };
}

LoveGraphicsBlendAlphaMode _blendAlphaMode(String value, String symbol) {
  return switch (value) {
    'alphamultiply' => LoveGraphicsBlendAlphaMode.alphaMultiply,
    'premultiplied' => LoveGraphicsBlendAlphaMode.premultiplied,
    _ => throw LuaError('$symbol invalid blend alpha mode "$value"'),
  };
}

LoveGraphicsFilterMode _filterMode(String value, String symbol) {
  return switch (value) {
    'linear' => LoveGraphicsFilterMode.linear,
    'nearest' => LoveGraphicsFilterMode.nearest,
    _ => throw LuaError('$symbol invalid filter mode "$value"'),
  };
}

LoveGraphicsWrapMode _wrapMode(String value, String symbol) {
  return switch (value) {
    'clamp' => LoveGraphicsWrapMode.clamp,
    'repeat' => LoveGraphicsWrapMode.repeat,
    'mirroredrepeat' => LoveGraphicsWrapMode.mirroredRepeat,
    'clampzero' => LoveGraphicsWrapMode.clampZero,
    _ => throw LuaError('$symbol invalid wrap mode "$value"'),
  };
}

LoveCanvasMipmapMode _canvasMipmapMode(String value, String symbol) {
  return switch (value) {
    'none' => LoveCanvasMipmapMode.none,
    'auto' => LoveCanvasMipmapMode.auto,
    'manual' => LoveCanvasMipmapMode.manual,
    _ => throw LuaError('$symbol invalid mipmap mode "$value"'),
  };
}

LoveGraphicsCompareMode _compareMode(String value, String symbol) {
  return switch (value) {
    'equal' => LoveGraphicsCompareMode.equal,
    'notequal' => LoveGraphicsCompareMode.notequal,
    'less' => LoveGraphicsCompareMode.less,
    'lequal' => LoveGraphicsCompareMode.lequal,
    'gequal' => LoveGraphicsCompareMode.gequal,
    'greater' => LoveGraphicsCompareMode.greater,
    'never' => LoveGraphicsCompareMode.never,
    'always' => LoveGraphicsCompareMode.always,
    _ => throw LuaError('$symbol invalid compare mode "$value"'),
  };
}

String _filterModeName(LoveGraphicsFilterMode mode) {
  return switch (mode) {
    LoveGraphicsFilterMode.linear => 'linear',
    LoveGraphicsFilterMode.nearest => 'nearest',
  };
}

String _wrapModeName(LoveGraphicsWrapMode mode) {
  return switch (mode) {
    LoveGraphicsWrapMode.clamp => 'clamp',
    LoveGraphicsWrapMode.repeat => 'repeat',
    LoveGraphicsWrapMode.mirroredRepeat => 'mirroredrepeat',
    LoveGraphicsWrapMode.clampZero => 'clampzero',
  };
}

String _canvasMipmapModeName(LoveCanvasMipmapMode mode) {
  return switch (mode) {
    LoveCanvasMipmapMode.none => 'none',
    LoveCanvasMipmapMode.auto => 'auto',
    LoveCanvasMipmapMode.manual => 'manual',
  };
}

String _compareModeName(LoveGraphicsCompareMode mode) {
  return switch (mode) {
    LoveGraphicsCompareMode.equal => 'equal',
    LoveGraphicsCompareMode.notequal => 'notequal',
    LoveGraphicsCompareMode.less => 'less',
    LoveGraphicsCompareMode.lequal => 'lequal',
    LoveGraphicsCompareMode.gequal => 'gequal',
    LoveGraphicsCompareMode.greater => 'greater',
    LoveGraphicsCompareMode.never => 'never',
    LoveGraphicsCompareMode.always => 'always',
  };
}

bool _isDepthStencilFormat(String format) => switch (format) {
  'stencil8' ||
  'depth16' ||
  'depth24' ||
  'depth32f' ||
  'depth24stencil8' ||
  'depth32fstencil8' => true,
  _ => false,
};

Value _filterResult(LoveGraphicsDefaultFilter filter) {
  return Value.multi(<Object?>[
    _filterModeName(filter.min),
    _filterModeName(filter.mag),
    filter.anisotropy,
  ]);
}

Value _wrapResult(LoveGraphicsWrap wrap) {
  return Value.multi(<Object?>[
    _wrapModeName(wrap.horizontal),
    _wrapModeName(wrap.vertical),
    _wrapModeName(wrap.depth),
  ]);
}

LoveGraphicsDefaultFilter _filterFromArgs(
  List<Object?> args,
  int startIndex,
  String symbol, {
  LoveGraphicsDefaultFilter? currentFilter,
}) {
  final min = _filterMode(_requireString(args, startIndex, symbol), symbol);
  final mag = args.length >= startIndex + 2
      ? _filterMode(_requireString(args, startIndex + 1, symbol), symbol)
      : min;
  final anisotropy = args.length >= startIndex + 3
      ? _requireNumber(args, startIndex + 2, symbol)
      : 1.0;
  return (currentFilter ?? LoveGraphicsDefaultFilter.standard).copyWith(
    min: min,
    mag: mag,
    anisotropy: anisotropy,
  );
}

LoveGraphicsWrap _wrapFromArgs(
  List<Object?> args,
  int startIndex,
  String symbol, {
  LoveGraphicsWrap? currentWrap,
}) {
  final horizontal = _wrapMode(
    _requireString(args, startIndex, symbol),
    symbol,
  );
  final vertical = args.length >= startIndex + 2
      ? _wrapMode(_requireString(args, startIndex + 1, symbol), symbol)
      : horizontal;
  final depth = args.length >= startIndex + 3
      ? _wrapMode(_requireString(args, startIndex + 2, symbol), symbol)
      : horizontal;
  return (currentWrap ?? LoveGraphicsWrap.clamp).copyWith(
    horizontal: horizontal,
    vertical: vertical,
    depth: depth,
  );
}

String _textAlign(String value, [String symbol = 'love.graphics.printf']) {
  return switch (value) {
    'left' || 'center' || 'right' || 'justify' => value,
    _ => throw LuaError('$symbol invalid alignment "$value"'),
  };
}

int _graphicsTextArgumentStartIndex(List<Object?> args) {
  if (args.length < 2) {
    return 1;
  }

  return _fontIfPresent(args[1]) != null ? 2 : 1;
}

(Value, Map<dynamic, dynamic>)? _optionalTableTarget(Object? value) {
  final tableTarget = _tableTargetIfPresent(value);
  if (tableTarget != null) {
    return tableTarget;
  }

  if (value == null) {
    return null;
  }

  throw LuaError('expected table argument');
}

(Value, Map<dynamic, dynamic>)? _tableTargetIfPresent(Object? value) {
  if (value == null) {
    return null;
  }

  if (value case final Value wrapped when wrapped.raw is Map) {
    return (wrapped, wrapped.raw as Map<dynamic, dynamic>);
  }

  if (value is Map<dynamic, dynamic>) {
    return (Value(value), value);
  }

  return null;
}

Object? _valueAt(List<Object?> args, int index) {
  return index < args.length ? args[index] : null;
}

Object? _rawValue(Object? value) {
  if (value is Value) {
    return value.unwrap();
  }
  if (value is LuaString) {
    return value.toString();
  }
  return value;
}

double _optionalNumber(
  List<Object?> args,
  int index,
  String symbol, {
  required double defaultValue,
}) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw == null) {
    return defaultValue;
  }

  if (raw is num) {
    return raw.toDouble();
  }

  throw LuaError('$symbol expected a number at argument ${index + 1}');
}

double _requireNumber(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is num) {
    return raw.toDouble();
  }

  throw LuaError('$symbol expected a number at argument ${index + 1}');
}

int _requireRoundedInt(List<Object?> args, int index, String symbol) {
  return _requireNumber(args, index, symbol).round();
}

String _requireString(List<Object?> args, int index, String symbol) {
  final stringValue = _stringLike(_valueAt(args, index));
  if (stringValue != null) {
    return stringValue;
  }

  throw LuaError('$symbol expected a string at argument ${index + 1}');
}

List<LoveTextSpan> _requireColoredTextSpans(
  List<Object?> args,
  int index,
  String symbol,
) {
  final spans = _coloredTextSpansIfPresent(
    _valueAt(args, index),
    symbol: symbol,
    argumentIndex: index + 1,
  );
  if (spans != null) {
    return spans;
  }

  throw LuaError(
    '$symbol expected a string or colored text at argument ${index + 1}',
  );
}

bool _requireBoolean(List<Object?> args, int index, String symbol) {
  final raw = _rawValue(_valueAt(args, index));
  if (raw is bool) {
    return raw;
  }

  throw LuaError('$symbol expected a boolean at argument ${index + 1}');
}

Value _requireCallable(List<Object?> args, int index, String symbol) {
  final raw = _valueAt(args, index);
  return switch (raw) {
    final Value value when value.isCallable() => value,
    final BuiltinFunction function => Value(function),
    final Function function => Value(function),
    _ => throw LuaError('$symbol expected a callable at argument ${index + 1}'),
  };
}

LoveFont? _fontIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final font = table[_loveFontObjectKey];
  return font is LoveFont ? font : null;
}

LoveTextDrawable? _textDrawableIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final text = table[_loveTextObjectKey];
  return text is LoveTextDrawable ? text : null;
}

LoveImage? _imageIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final image = table[_loveImageObjectKey];
  return image is LoveImage ? image : null;
}

LoveCanvas? _canvasIfPresent(Object? value) {
  final image = _imageIfPresent(value);
  return image is LoveCanvas ? image : null;
}

LoveImageData? _imageDataIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final imageData = table[_loveImageDataObjectKey];
  return imageData is LoveImageData ? imageData : null;
}

LoveCompressedImageData? _compressedImageDataIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final imageData = table[_loveCompressedImageDataObjectKey];
  return imageData is LoveCompressedImageData ? imageData : null;
}

LoveQuad? _quadIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final quad = table[_loveQuadObjectKey];
  return quad is LoveQuad ? quad : null;
}

LoveTransform? _transformIfPresent(Object? value) {
  final raw = _rawValue(value);
  final table = switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };

  if (table == null) {
    return null;
  }

  final transform = table[_loveTransformObjectKey];
  return transform is LoveTransform ? transform : null;
}

LoveFont _requireFont(List<Object?> args, int index, String symbol) {
  final font = _fontIfPresent(_valueAt(args, index));
  if (font != null) {
    return font;
  }

  throw LuaError('$symbol expected a Font at argument ${index + 1}');
}

LoveTextDrawable _requireTextDrawable(
  List<Object?> args,
  int index,
  String symbol,
) {
  final text = _textDrawableIfPresent(_valueAt(args, index));
  if (text != null) {
    return text;
  }

  throw LuaError('$symbol expected a Text at argument ${index + 1}');
}

LoveImage _requireImage(List<Object?> args, int index, String symbol) {
  final image = _imageIfPresent(_valueAt(args, index));
  if (image != null) {
    return image;
  }

  throw LuaError('$symbol expected an Image at argument ${index + 1}');
}

LoveCanvas _requireCanvas(List<Object?> args, int index, String symbol) {
  final canvas = _canvasIfPresent(_valueAt(args, index));
  if (canvas != null) {
    return canvas;
  }

  throw LuaError('$symbol expected a Canvas at argument ${index + 1}');
}

LoveImageData _requireImageData(List<Object?> args, int index, String symbol) {
  final imageData = _imageDataIfPresent(_valueAt(args, index));
  if (imageData != null) {
    return imageData;
  }

  throw LuaError('$symbol expected an ImageData at argument ${index + 1}');
}

LoveCompressedImageData _requireCompressedImageData(
  List<Object?> args,
  int index,
  String symbol,
) {
  final imageData = _compressedImageDataIfPresent(_valueAt(args, index));
  if (imageData != null) {
    return imageData;
  }

  throw LuaError(
    '$symbol expected a CompressedImageData at argument ${index + 1}',
  );
}

LoveQuad _requireQuad(List<Object?> args, int index, String symbol) {
  final quad = _quadIfPresent(_valueAt(args, index));
  if (quad != null) {
    return quad;
  }

  throw LuaError('$symbol expected a Quad at argument ${index + 1}');
}

LoveTransform _requireTransform(List<Object?> args, int index, String symbol) {
  final transform = _transformIfPresent(_valueAt(args, index));
  if (transform != null) {
    return transform;
  }

  throw LuaError('$symbol expected a Transform at argument ${index + 1}');
}

Matrix4 _matrixFromTransformArgumentOrStandardTransform(
  List<Object?> args,
  int index,
  String symbol, {
  int transformOffset = 2,
}) {
  final transform = _transformIfPresent(_valueAt(args, index));
  if (transform != null) {
    return Matrix4.copy(transform.matrix);
  }

  return _standardTransform(
    args,
    index,
    symbol,
    transformOffset: transformOffset,
  );
}

Future<LoveFont> _fontFromArgs(
  LibraryRegistrationContext context,
  List<Object?> args,
  String symbol, {
  LoveGraphicsDefaultFilter defaultFilter = LoveGraphicsDefaultFilter.standard,
}) async {
  final runtime = _runtimeContext(context);
  if (args.isEmpty) {
    final size = LoveFont.defaultSize;
    return runtime.createDefaultTrueTypeOrFallbackFont(
      size: size,
      hinting: 'normal',
      dpiScale: runtime.windowMetrics.dpiScale,
      defaultFilter: defaultFilter,
    );
  }

  final rasterizer = _rasterizerIfPresent(args.first);
  if (rasterizer != null) {
    return rasterizer.toLoveFont(defaultFilter: defaultFilter);
  }

  final firstNumber = _numberIfPresent(args.first);
  if (firstNumber case final double size) {
    _validateFontSize(size, symbol);
    final hinting = _optionalFontHintingArg(args, 1, symbol);
    final dpiScale = _optionalFontDpiScaleArg(
      args,
      2,
      symbol,
      defaultValue: runtime.windowMetrics.dpiScale,
    );
    return runtime.createDefaultTrueTypeOrFallbackFont(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
  }

  final source = await _resolveResourceSourcePath(
    context,
    args.first,
    symbol: symbol,
  );
  if (source == null) {
    throw LuaError('$symbol expected a font size or filename at argument 1');
  }

  final fileData = await _resourceFileDataIfPresent(
    context,
    args.first,
    symbol,
  );
  final sourceDataType = LoveFont.fontDataTypeForSource(source);
  if (args.length >= 2 && _valueAt(args, 1) == null) {
    return _fontFromArgs(
      context,
      <Object?>[args.first],
      symbol,
      defaultFilter: defaultFilter,
    );
  }
  final secondNumber = _numberIfPresent(_valueAt(args, 1));

  if (args.length >= 2 && secondNumber == null) {
    if (fileData == null) {
      if (sourceDataType == LoveFont.bmFontDataType) {
        throw LuaError('$symbol could not load BMFont definition "$source"');
      }
      throw LuaError(
        '$symbol expected a font size or BMFont image source at argument 2',
      );
    }
    if (!loveLooksLikeBmFontDefinition(fileData.bytes)) {
      throw LuaError('$symbol invalid font file "${fileData.filename}"');
    }

    final dpiScale = _optionalFontDpiScaleArg(
      args,
      2,
      symbol,
      defaultValue: 1.0,
    );
    final rasterizer = await _bmFontRasterizerFromFileData(
      context,
      fileData,
      symbol: symbol,
      pageImages: await _resolveBmFontPageImages(
        context,
        _valueAt(args, 1),
        symbol: symbol,
      ),
      dpiScale: dpiScale,
    );
    return rasterizer.toLoveFont(defaultFilter: defaultFilter);
  }

  if (args.length == 1 &&
      fileData != null &&
      loveLooksLikeBmFontDefinition(fileData.bytes)) {
    final rasterizer = await _bmFontRasterizerFromFileData(
      context,
      fileData,
      symbol: symbol,
      pageImages: const <int, LoveImageData>{},
      dpiScale: 1.0,
    );
    return rasterizer.toLoveFont(defaultFilter: defaultFilter);
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
  if (fileData == null) {
    if (sourceDataType == LoveFont.bmFontDataType) {
      throw LuaError('$symbol could not load BMFont definition "$source"');
    }
    throw LuaError('$symbol invalid font file "$source"');
  }

  if (!loveLooksLikeTrueTypeFontData(fileData.bytes)) {
    throw LuaError('$symbol invalid font file "${fileData.filename}"');
  }
  final loadedFont = await runtime.host.loadTrueTypeFont(
    source,
    bytes: Uint8List.fromList(fileData.bytes),
    size: size,
    hinting: hinting,
    dpiScale: dpiScale,
    defaultFilter: defaultFilter,
  );
  if (loadedFont != null) {
    return loadedFont;
  }
  return LoveRasterizer.trueType(
    size: size,
    hinting: hinting,
    dpiScale: dpiScale,
    source: source,
    sourceBytes: fileData.bytes,
  ).toLoveFont(defaultFilter: defaultFilter);
}

Future<LoveFont> _loadFontFromArgs(
  LibraryRegistrationContext context,
  List<Object?> args,
  String symbol, {
  LoveGraphicsDefaultFilter defaultFilter = LoveGraphicsDefaultFilter.standard,
}) {
  return _fontFromArgs(context, args, symbol, defaultFilter: defaultFilter);
}

void _validateFontSize(double size, String symbol) {
  if (size <= 0) {
    throw LuaError('$symbol font size must be > 0');
  }
}

String _optionalFontHintingArg(
  List<Object?> args,
  int index,
  String symbol, {
  String defaultValue = 'normal',
}) {
  final raw = _valueAt(args, index);
  if (raw == null) {
    return defaultValue;
  }
  return _fontHinting(_requireString(args, index, symbol), symbol);
}

double _optionalFontSizeArg(
  List<Object?> args,
  int index,
  String symbol, {
  required double defaultValue,
}) {
  final raw = _valueAt(args, index);
  if (raw == null) {
    return defaultValue;
  }
  return _requireNumber(args, index, symbol);
}

String _fontHinting(String value, String symbol) {
  return switch (value) {
    'normal' || 'light' || 'mono' || 'none' => value,
    _ => throw LuaError(
      "Invalid TrueType font hinting mode '$value', expected one of: "
      "'normal', 'light', 'mono', 'none'",
    ),
  };
}

double _optionalFontDpiScaleArg(
  List<Object?> args,
  int index,
  String symbol, {
  required double defaultValue,
}) {
  final raw = _valueAt(args, index);
  if (raw == null) {
    return defaultValue;
  }
  return _fontDpiScale(args, index, symbol);
}

double? _numberIfPresent(Object? value) {
  final raw = _rawValue(value);
  return raw is num ? raw.toDouble() : null;
}

int _textureMipmapLevel(
  List<Object?> args,
  int index,
  String symbol, {
  int defaultValue = 1,
}) {
  final value = _numberIfPresent(_valueAt(args, index));
  final mipmap = (value ?? defaultValue).round();
  if (mipmap < 1) {
    throw LuaError('$symbol mipmap level must be >= 1');
  }
  return mipmap;
}

LoveScissorRect _scissorRectFromArgs(List<Object?> args, String symbol) {
  final x = _requireNumber(args, 0, symbol);
  final y = _requireNumber(args, 1, symbol);
  final width = _requireNumber(args, 2, symbol);
  final height = _requireNumber(args, 3, symbol);
  if (width < 0 || height < 0) {
    throw LuaError("Can't set scissor with negative width and/or height.");
  }

  return LoveScissorRect(x: x, y: y, width: width, height: height);
}

bool _matrixLayout(String value, String symbol) {
  return switch (value) {
    'row' => false,
    'column' => true,
    _ => throw LuaError('$symbol invalid matrix layout "$value"'),
  };
}

List<double> _matrixElementsFromTable(
  Map<dynamic, dynamic> table, {
  required bool columnMajor,
  required String symbol,
}) {
  final first = _tableIndexedEntry(table, 1);
  final firstTable = _tableIfPresent(first);
  if (firstTable != null) {
    final elements = List<double>.filled(16, 0.0, growable: false);
    if (columnMajor) {
      for (var column = 0; column < 4; column++) {
        final columnTable = _tableIfPresent(
          _tableIndexedEntry(table, column + 1),
        );
        if (columnTable == null) {
          throw LuaError('$symbol expected a 4x4 matrix table');
        }
        for (var row = 0; row < 4; row++) {
          elements[(column * 4) + row] = _tableIndexedNumber(
            columnTable,
            row + 1,
            symbol,
          );
        }
      }
      return elements;
    }

    for (var row = 0; row < 4; row++) {
      final rowTable = _tableIfPresent(_tableIndexedEntry(table, row + 1));
      if (rowTable == null) {
        throw LuaError('$symbol expected a 4x4 matrix table');
      }
      for (var column = 0; column < 4; column++) {
        elements[(column * 4) + row] = _tableIndexedNumber(
          rowTable,
          column + 1,
          symbol,
        );
      }
    }
    return elements;
  }

  final elements = List<double>.filled(16, 0.0, growable: false);
  if (columnMajor) {
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        elements[(column * 4) + row] = _tableIndexedNumber(
          table,
          (column * 4) + row + 1,
          symbol,
        );
      }
    }
    return elements;
  }

  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 4; column++) {
      elements[(column * 4) + row] = _tableIndexedNumber(
        table,
        (row * 4) + column + 1,
        symbol,
      );
    }
  }
  return elements;
}

Matrix4 _standardTransform(
  List<Object?> args,
  int index,
  String symbol, {
  int transformOffset = 2,
}) {
  final x = _optionalNumber(args, index + 0, symbol, defaultValue: 0.0);
  final y = _optionalNumber(args, index + 1, symbol, defaultValue: 0.0);
  final angle = _optionalNumber(
    args,
    index + transformOffset + 0,
    symbol,
    defaultValue: 0.0,
  );
  final sx = _optionalNumber(
    args,
    index + transformOffset + 1,
    symbol,
    defaultValue: 1.0,
  );
  final sy = _optionalNumber(
    args,
    index + transformOffset + 2,
    symbol,
    defaultValue: sx,
  );
  final ox = _optionalNumber(
    args,
    index + transformOffset + 3,
    symbol,
    defaultValue: 0.0,
  );
  final oy = _optionalNumber(
    args,
    index + transformOffset + 4,
    symbol,
    defaultValue: 0.0,
  );
  final kx = _optionalNumber(
    args,
    index + transformOffset + 5,
    symbol,
    defaultValue: 0.0,
  );
  final ky = _optionalNumber(
    args,
    index + transformOffset + 6,
    symbol,
    defaultValue: 0.0,
  );

  final cosAngle = math.cos(angle);
  final sinAngle = math.sin(angle);
  final a = cosAngle * sx - ky * sinAngle * sy;
  final b = sinAngle * sx + ky * cosAngle * sy;
  final c = kx * cosAngle * sx - sinAngle * sy;
  final d = kx * sinAngle * sx + cosAngle * sy;
  final tx = x - (ox * a) - (oy * c);
  final ty = y - (ox * b) - (oy * d);

  return Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
}

bool _luaTruthy(Object? value) {
  final raw = _rawValue(value);
  return raw != null && raw != false;
}

bool? _tableBool(Map<dynamic, dynamic> table, String key) {
  final entry = _tableEntry(table, key);
  if (entry == null) {
    return null;
  }

  return _luaTruthy(entry);
}

int? _tableRoundedInt(Map<dynamic, dynamic> table, String key) {
  final entry = _tableEntry(table, key);
  if (entry == null) {
    return null;
  }

  final raw = _rawValue(entry);
  return raw is num ? raw.round() : null;
}

String? _tableString(Map<dynamic, dynamic> table, String key) {
  return _stringLike(_tableEntry(table, key));
}

bool _looksLikeColorTable(Map<dynamic, dynamic> table) {
  return _tableIndexedEntry(table, 1) != null &&
      _tableIndexedEntry(table, 2) != null &&
      _tableIndexedEntry(table, 3) != null;
}

double _tableIndexedNumber(
  Map<dynamic, dynamic> table,
  int index,
  String symbol, {
  double? defaultValue,
}) {
  final entry = _tableIndexedEntry(table, index);
  if (entry == null) {
    if (defaultValue case final value?) {
      return value;
    }
    throw LuaError('$symbol expected a color component at index $index');
  }

  final raw = _rawValue(entry);
  if (raw is num) {
    return raw.toDouble();
  }

  throw LuaError('$symbol expected a numeric color component at index $index');
}

Object? _tableEntry(Map<dynamic, dynamic> table, String key) {
  if (table.containsKey(key)) {
    return table[key];
  }

  for (final entry in table.entries) {
    if (_stringLike(entry.key) == key) {
      return entry.value;
    }
  }

  return null;
}

Object? _tableIndexedEntry(Map<dynamic, dynamic> table, int index) {
  if (table.containsKey(index)) {
    return table[index];
  }

  final asDouble = index.toDouble();
  if (table.containsKey(asDouble)) {
    return table[asDouble];
  }

  for (final entry in table.entries) {
    final rawKey = _rawValue(entry.key);
    if (rawKey == index || rawKey == asDouble) {
      return entry.value;
    }
  }

  return null;
}

String? _stringLike(Object? value) {
  return switch (_rawValue(value)) {
    final String stringValue => stringValue,
    final LuaString luaString => luaString.toString(),
    _ => null,
  };
}

List<LoveTextSpan>? _coloredTextSpansIfPresent(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  final direct = _strictFontTextSegmentLike(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (direct != null) {
    return <LoveTextSpan>[LoveTextSpan(text: direct)];
  }

  final table = _tableIfPresent(value);
  if (table == null) {
    return null;
  }

  final spans = <LoveTextSpan>[];
  LoveColor? currentColor;
  for (var index = 1; ; index++) {
    final entry = _tableIndexedEntry(table, index);
    if (entry == null) {
      break;
    }

    final colorTable = _tableIfPresent(entry);
    if (colorTable != null) {
      currentColor = LoveColor(
        _tableIndexedNumber(colorTable, 1, symbol),
        _tableIndexedNumber(colorTable, 2, symbol),
        _tableIndexedNumber(colorTable, 3, symbol),
        _tableIndexedNumber(colorTable, 4, symbol, defaultValue: 1.0),
      );
      continue;
    }

    final text = _strictFontTextSegmentLike(
      entry,
      symbol: symbol,
      argumentIndex: argumentIndex,
    );
    if (text == null) {
      throw LuaError(
        '$symbol expected strings and color tables in colored text argument $argumentIndex',
      );
    }

    spans.add(LoveTextSpan(text: text, color: currentColor));
  }

  return spans;
}

List<({double x, double y})> _coordinateSequence(
  List<Object?> args,
  String symbol,
) {
  final coordinates = <double>[];
  if (args.length == 1) {
    final value = _valueAt(args, 0);
    final packed = _rawValue(value);
    if (packed is List) {
      for (final entry in packed) {
        final raw = _rawValue(entry);
        if (raw is! num) {
          throw LuaError('$symbol expected numeric coordinates in list');
        }
        coordinates.add(raw.toDouble());
      }
    } else {
      final table = switch (value) {
        final Value wrapped when wrapped.raw is Map<dynamic, dynamic> =>
          wrapped.raw as Map<dynamic, dynamic>,
        final Map<dynamic, dynamic> map => map,
        _ => null,
      };

      if (table != null) {
        for (var index = 1; ; index++) {
          final entry = _tableIndexedEntry(table, index);
          if (entry == null) {
            break;
          }

          final raw = _rawValue(entry);
          if (raw is! num) {
            throw LuaError('$symbol expected numeric coordinates in table');
          }
          coordinates.add(raw.toDouble());
        }
      } else {
        final raw = packed;
        if (raw is! num) {
          throw LuaError('$symbol expected a coordinate table or numbers');
        }
        coordinates.add(raw.toDouble());
      }
    }
  } else {
    for (final arg in args) {
      final raw = _rawValue(arg);
      if (raw is! num) {
        throw LuaError('$symbol expected numeric coordinates');
      }
      coordinates.add(raw.toDouble());
    }
  }

  if (coordinates.length.isOdd) {
    throw LuaError(
      '$symbol number of vertex components must be a multiple of two',
    );
  }

  return List<({double x, double y})>.generate(
    coordinates.length ~/ 2,
    (index) => (x: coordinates[index * 2], y: coordinates[index * 2 + 1]),
    growable: false,
  );
}

List<({double x, double y, LoveColor? color})> _pointSequence(
  List<Object?> args,
  String symbol, {
  required LoveColor currentColor,
}) {
  if (args.length == 1) {
    final table = _tableIfPresent(args.first);
    if (table != null) {
      final first = _tableIndexedEntry(table, 1);
      final firstTable = _tableIfPresent(first);
      if (firstTable != null) {
        final points = <({double x, double y, LoveColor? color})>[];
        for (var index = 1; ; index++) {
          final entry = _tableIndexedEntry(table, index);
          if (entry == null) {
            break;
          }

          final pointTable = _tableIfPresent(entry);
          if (pointTable == null) {
            throw LuaError('$symbol expected a table of point tables');
          }

          final pointColor = LoveColor(
            _tableIndexedNumber(pointTable, 3, symbol, defaultValue: 1.0),
            _tableIndexedNumber(pointTable, 4, symbol, defaultValue: 1.0),
            _tableIndexedNumber(pointTable, 5, symbol, defaultValue: 1.0),
            _tableIndexedNumber(pointTable, 6, symbol, defaultValue: 1.0),
          ).clamped();

          points.add((
            x: _tableIndexedNumber(pointTable, 1, symbol),
            y: _tableIndexedNumber(pointTable, 2, symbol),
            color: currentColor.modulate(pointColor),
          ));
        }

        return List<({double x, double y, LoveColor? color})>.unmodifiable(
          points,
        );
      }
    }
  }

  return _coordinateSequence(args, symbol)
      .map((point) => (x: point.x, y: point.y, color: null as LoveColor?))
      .toList(growable: false);
}

Map<dynamic, dynamic>? _tableIfPresent(Object? value) {
  final raw = _rawValue(value);
  return switch (raw) {
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };
}

Map<dynamic, dynamic>? _tableIdentityIfPresent(Object? value) {
  return switch (value) {
    final Value wrapped when wrapped.raw is Map<dynamic, dynamic> =>
      wrapped.raw as Map<dynamic, dynamic>,
    final Map<dynamic, dynamic> map => map,
    _ => null,
  };
}
