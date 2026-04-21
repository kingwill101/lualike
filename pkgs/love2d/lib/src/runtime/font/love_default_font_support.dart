part of '../love_runtime.dart';

final Map<LoveRuntimeContext, LoveFont> _loveDefaultGraphicsFontCache =
    HashMap<LoveRuntimeContext, LoveFont>.identity();
final Map<LoveRuntimeContext, Future<LoveFont>>
_loveDefaultGraphicsFontLoaders =
    HashMap<LoveRuntimeContext, Future<LoveFont>>.identity();

void _clearLoveDefaultGraphicsFontState(LoveRuntimeContext runtime) {
  _loveDefaultGraphicsFontCache.remove(runtime);
  _loveDefaultGraphicsFontLoaders.remove(runtime);
}

extension LoveRuntimeContextDefaultFontSupport on LoveRuntimeContext {
  Future<LoveFont> createDefaultTrueTypeOrFallbackFont({
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

  Future<LoveFont> ensureCurrentGraphicsFont() async {
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
      final font = await inFlight;
      graphics.font = font;
      setDefaultGraphicsFont(font);
      return font;
    }

    final loader = createDefaultTrueTypeOrFallbackFont(
      size: LoveFont.defaultSize,
      hinting: 'normal',
      dpiScale: windowMetrics.dpiScale,
      defaultFilter: graphics.defaultFilter,
    );
    _loveDefaultGraphicsFontLoaders[this] = loader;

    try {
      final font = await loader;
      _loveDefaultGraphicsFontCache[this] = font;
      graphics.font = font;
      setDefaultGraphicsFont(font);
      return font;
    } finally {
      _loveDefaultGraphicsFontLoaders.remove(this);
    }
  }
}
