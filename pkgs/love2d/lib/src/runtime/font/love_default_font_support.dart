part of '../love_runtime.dart';

final Map<LoveRuntimeContext, LoveFont> _loveDefaultGraphicsFontCache =
    HashMap<LoveRuntimeContext, LoveFont>.identity();
final Map<LoveRuntimeContext, Future<LoveFont>>
_loveDefaultGraphicsFontLoaders =
    HashMap<LoveRuntimeContext, Future<LoveFont>>.identity();
final Map<LoveRuntimeContext, Map<_LoveDefaultTrueTypeFontCacheKey, LoveFont>>
_loveDefaultTrueTypeFontCache =
    HashMap<
      LoveRuntimeContext,
      Map<_LoveDefaultTrueTypeFontCacheKey, LoveFont>
    >.identity();
final Map<
  LoveRuntimeContext,
  Map<_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>
>
_loveDefaultTrueTypeFontLoaders =
    HashMap<
      LoveRuntimeContext,
      Map<_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>
    >.identity();

final class _LoveDefaultTrueTypeFontCacheKey {
  const _LoveDefaultTrueTypeFontCacheKey({
    required this.size,
    required this.hinting,
    required this.dpiScale,
    required this.defaultFilter,
  });

  final double size;
  final String hinting;
  final double dpiScale;
  final LoveGraphicsDefaultFilter defaultFilter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LoveDefaultTrueTypeFontCacheKey &&
          size == other.size &&
          hinting == other.hinting &&
          dpiScale == other.dpiScale &&
          defaultFilter == other.defaultFilter;

  @override
  int get hashCode => Object.hash(size, hinting, dpiScale, defaultFilter);
}

void _clearLoveDefaultGraphicsFontState(LoveRuntimeContext runtime) {
  _loveDefaultGraphicsFontCache.remove(runtime);
  _loveDefaultGraphicsFontLoaders.remove(runtime);
  _loveDefaultTrueTypeFontCache.remove(runtime);
  _loveDefaultTrueTypeFontLoaders.remove(runtime);
}

extension LoveRuntimeContextDefaultFontSupport on LoveRuntimeContext {
  Map<_LoveDefaultTrueTypeFontCacheKey, LoveFont>
  _defaultTrueTypeFontsForRuntime() => _loveDefaultTrueTypeFontCache
      .putIfAbsent(this, () => <_LoveDefaultTrueTypeFontCacheKey, LoveFont>{});

  Map<_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>
  _defaultTrueTypeFontLoadersForRuntime() =>
      _loveDefaultTrueTypeFontLoaders.putIfAbsent(
        this,
        () => <_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>{},
      );

  _LoveDefaultTrueTypeFontCacheKey _defaultTrueTypeFontCacheKey({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) => _LoveDefaultTrueTypeFontCacheKey(
    size: size,
    hinting: hinting,
    dpiScale: dpiScale,
    defaultFilter: defaultFilter,
  );

  Future<LoveFont> _loadDefaultTrueTypeOrFallbackFontPrototype({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) async {
    final loadedFont = await host.loadDefaultTrueTypeFont(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
    if (loadedFont != null) {
      return loadedFont;
    }

    final sourceBytes = await host.loadDefaultTrueTypeFontBytes();
    if (sourceBytes != null) {
      return LoveRasterizer.trueType(
        size: size,
        hinting: hinting,
        dpiScale: dpiScale,
        sourceBytes: sourceBytes,
      ).toLoveFont(defaultFilter: defaultFilter);
    }

    final metadata = parseLoveTrueTypeFontMetadata(sourceBytes);
    final missingGlyphAdvance = metadata?.logicalMaxAdvance(
      size,
      dpiScale: dpiScale,
    );
    return LoveFont(
      size: size,
      fontType: LoveFont.trueTypeFontType,
      dataType: LoveFont.trueTypeFontType,
      glyphAdvance: missingGlyphAdvance,
      glyphAdvances: metadata?.logicalGlyphAdvances(size, dpiScale: dpiScale),
      glyphKernings: metadata?.logicalKerning(size, dpiScale: dpiScale),
      hinting: hinting,
      dpiScale: dpiScale,
      heightOverride: metadata?.logicalHeight(size),
      ascentOverride: metadata?.logicalAscent(size),
      descentOverride: metadata?.logicalDescent(size),
      missingGlyphAdvance: missingGlyphAdvance,
      syntheticTabAdvance: _loveTrueTypeSyntheticTabAdvance(
        metadata,
        size: size,
        dpiScale: dpiScale,
      ),
      filter: defaultFilter,
      supportsCodepointCallback: metadata?.supportsCodepointCallback,
    );
  }

  Object createDefaultTrueTypeOrFallbackFontOrFuture({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) {
    final cacheKey = _defaultTrueTypeFontCacheKey(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
    final cached = _defaultTrueTypeFontsForRuntime()[cacheKey];
    if (cached != null) {
      return cached.copy();
    }

    final inFlight = _defaultTrueTypeFontLoadersForRuntime()[cacheKey];
    if (inFlight != null) {
      return inFlight.then((font) => font.copy());
    }

    final loader = _loadDefaultTrueTypeOrFallbackFontPrototype(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
    _defaultTrueTypeFontLoadersForRuntime()[cacheKey] = loader;

    return loader
        .then((font) {
          _defaultTrueTypeFontsForRuntime()[cacheKey] = font;
          return font.copy();
        })
        .whenComplete(() {
          _defaultTrueTypeFontLoadersForRuntime().remove(cacheKey);
        });
  }

  Future<LoveFont> createDefaultTrueTypeOrFallbackFont({
    required double size,
    required String hinting,
    required double dpiScale,
    required LoveGraphicsDefaultFilter defaultFilter,
  }) {
    final fontOrFuture = createDefaultTrueTypeOrFallbackFontOrFuture(
      size: size,
      hinting: hinting,
      dpiScale: dpiScale,
      defaultFilter: defaultFilter,
    );
    return fontOrFuture is Future<LoveFont>
        ? fontOrFuture
        : Future<LoveFont>.value(fontOrFuture as LoveFont);
  }

  Object ensureCurrentGraphicsFontOrFuture() {
    final current = graphics.font;
    if (!current.isImplicitDefaultGraphicsFont) {
      registerFont(current);
      return current;
    }

    final cached = _loveDefaultGraphicsFontCache[this];
    if (cached != null) {
      graphics.font = cached;
      setDefaultGraphicsFont(cached);
      return cached;
    }

    final inFlight = _loveDefaultGraphicsFontLoaders[this];
    if (inFlight != null) {
      return inFlight.then((font) {
        graphics.font = font;
        setDefaultGraphicsFont(font);
        return font;
      });
    }

    final fontOrFuture = createDefaultTrueTypeOrFallbackFontOrFuture(
      size: LoveFont.defaultSize,
      hinting: 'normal',
      dpiScale: windowMetrics.dpiScale,
      defaultFilter: graphics.defaultFilter,
    );
    final loader = fontOrFuture is Future<LoveFont>
        ? fontOrFuture
        : Future<LoveFont>.value(fontOrFuture as LoveFont);
    _loveDefaultGraphicsFontLoaders[this] = loader;

    return loader
        .then((font) {
          _loveDefaultGraphicsFontCache[this] = font;
          graphics.font = font;
          setDefaultGraphicsFont(font);
          return font;
        })
        .whenComplete(() {
          _loveDefaultGraphicsFontLoaders.remove(this);
        });
  }

  Future<LoveFont> ensureCurrentGraphicsFont() {
    final fontOrFuture = ensureCurrentGraphicsFontOrFuture();
    return fontOrFuture is Future<LoveFont>
        ? fontOrFuture
        : Future<LoveFont>.value(fontOrFuture as LoveFont);
  }
}
