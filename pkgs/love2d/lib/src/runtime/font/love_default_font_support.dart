part of '../love_runtime.dart';

/// Cached default graphics fonts keyed by runtime context.
final Map<LoveRuntimeContext, LoveFont> _loveDefaultGraphicsFontCache =
    HashMap<LoveRuntimeContext, LoveFont>.identity();

/// In-flight loaders for the default graphics font keyed by runtime context.
final Map<LoveRuntimeContext, Future<LoveFont>>
_loveDefaultGraphicsFontLoaders =
    HashMap<LoveRuntimeContext, Future<LoveFont>>.identity();

/// Cached default TrueType-derived fonts keyed by runtime context and font
/// configuration.
final Map<LoveRuntimeContext, Map<_LoveDefaultTrueTypeFontCacheKey, LoveFont>>
_loveDefaultTrueTypeFontCache =
    HashMap<
      LoveRuntimeContext,
      Map<_LoveDefaultTrueTypeFontCacheKey, LoveFont>
    >.identity();

/// In-flight loaders for default TrueType-derived fonts keyed by runtime
/// context and font configuration.
final Map<
  LoveRuntimeContext,
  Map<_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>
>
_loveDefaultTrueTypeFontLoaders =
    HashMap<
      LoveRuntimeContext,
      Map<_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>
    >.identity();

/// Cache key for default TrueType fonts derived from runtime settings.
final class _LoveDefaultTrueTypeFontCacheKey {
  /// Creates a cache key for a default TrueType font configuration.
  const _LoveDefaultTrueTypeFontCacheKey({
    required this.size,
    required this.hinting,
    required this.dpiScale,
    required this.defaultFilter,
  });

  /// The requested font size in LOVE units.
  final double size;

  /// The hinting mode used to build the font.
  final String hinting;

  /// The DPI scale used to build the font.
  final double dpiScale;

  /// The default graphics filter applied to the font textures.
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

/// Clears all cached default-font state for [runtime].
void _clearLoveDefaultGraphicsFontState(LoveRuntimeContext runtime) {
  _loveDefaultGraphicsFontCache.remove(runtime);
  _loveDefaultGraphicsFontLoaders.remove(runtime);
  _loveDefaultTrueTypeFontCache.remove(runtime);
  _loveDefaultTrueTypeFontLoaders.remove(runtime);
}

/// Adds default-font caching and loading helpers to runtime contexts.
extension LoveRuntimeContextDefaultFontSupport on LoveRuntimeContext {
  /// The cached default TrueType fonts for this runtime.
  Map<_LoveDefaultTrueTypeFontCacheKey, LoveFont>
  _defaultTrueTypeFontsForRuntime() => _loveDefaultTrueTypeFontCache
      .putIfAbsent(this, () => <_LoveDefaultTrueTypeFontCacheKey, LoveFont>{});

  /// The in-flight default TrueType font loaders for this runtime.
  Map<_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>
  _defaultTrueTypeFontLoadersForRuntime() =>
      _loveDefaultTrueTypeFontLoaders.putIfAbsent(
        this,
        () => <_LoveDefaultTrueTypeFontCacheKey, Future<LoveFont>>{},
      );

  /// Builds the cache key for a default TrueType font request.
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

  /// Loads a default TrueType font prototype or synthesizes a fallback font
  /// from bundled metadata.
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

  /// Returns either a cached default TrueType font copy or an in-flight loader
  /// for one.
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

  /// Loads the default TrueType-or-fallback font for this runtime.
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

  /// Ensures that the current graphics font is a realized default font.
  ///
  /// Returns either the current font immediately or a future that resolves once
  /// the default font has been loaded and installed.
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

  /// Ensures that the current graphics font is loaded and installed.
  Future<LoveFont> ensureCurrentGraphicsFont() {
    final fontOrFuture = ensureCurrentGraphicsFontOrFuture();
    return fontOrFuture is Future<LoveFont>
        ? fontOrFuture
        : Future<LoveFont>.value(fontOrFuture as LoveFont);
  }
}
