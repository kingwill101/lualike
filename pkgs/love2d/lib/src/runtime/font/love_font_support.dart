part of '../love_runtime.dart';

/// Identifies the source asset model used to rasterize glyphs.
enum LoveRasterizerKind {
  /// Rasterizes glyphs from TrueType or OpenType outline data.
  trueType,

  /// Rasterizes glyphs from an image-strip font.
  image,

  /// Rasterizes glyphs from a BMFont definition and its page textures.
  bmFont,
}

/// Stores pixel data and metrics for a single rasterized glyph.
final class LoveGlyphData extends LoveDataObject {
  /// Creates glyph data from metrics and optional pixel bytes.
  LoveGlyphData({
    required this.glyph,
    required this.width,
    required this.height,
    required this.advance,
    required this.bearingX,
    required this.bearingY,
    required this.format,
    List<int>? bytes,
  }) : super._(
         _loveGlyphBytes(
           width: width,
           height: height,
           format: format,
           bytes: bytes,
         ),
       );

  /// The Unicode codepoint represented by this glyph.
  final int glyph;

  /// The glyph bitmap width in pixels.
  final int width;

  /// The glyph bitmap height in pixels.
  final int height;

  /// The pen advance to apply after drawing this glyph.
  final int advance;

  /// The left-side bearing in pixels.
  final int bearingX;

  /// The top-side bearing in pixels.
  final int bearingY;

  /// The pixel format stored in [bytes].
  final String format;

  /// The minimum x coordinate of the glyph bounds.
  int get minX => bearingX;

  /// The minimum y coordinate of the glyph bounds.
  int get minY => height - bearingY;

  /// The maximum x coordinate of the glyph bounds.
  int get maxX => bearingX + width;

  /// The maximum y coordinate of the glyph bounds.
  int get maxY => bearingY;

  /// The single-character string represented by [glyph].
  String get glyphString => String.fromCharCode(glyph);

  /// Returns a copy of this glyph data.
  @override
  LoveGlyphData clone() {
    return LoveGlyphData(
      glyph: glyph,
      width: width,
      height: height,
      advance: advance,
      bearingX: bearingX,
      bearingY: bearingY,
      format: format,
      bytes: bytes,
    );
  }
}

/// Stores one character record parsed from a BMFont definition.
final class LoveBmFontCharacter {
  /// Creates a BMFont character entry.
  const LoveBmFontCharacter({
    required this.glyph,
    required this.x,
    required this.y,
    required this.page,
    required this.width,
    required this.height,
    required this.advance,
    required this.bearingX,
    required this.bearingY,
  });

  /// The Unicode codepoint represented by this character.
  final int glyph;

  /// The left pixel offset of the glyph on its page image.
  final int x;

  /// The top pixel offset of the glyph on its page image.
  final int y;

  /// The BMFont page id that contains the glyph bitmap.
  final int page;

  /// The glyph bitmap width in pixels.
  final int width;

  /// The glyph bitmap height in pixels.
  final int height;

  /// The horizontal pen advance in pixels.
  final int advance;

  /// The horizontal bearing in pixels.
  final int bearingX;

  /// The vertical bearing in pixels.
  final int bearingY;
}

/// Describes a parsed BMFont definition and its glyph tables.
final class LoveBmFontDefinition {
  /// Creates an immutable BMFont definition snapshot.
  LoveBmFontDefinition({
    required this.source,
    required this.fontSize,
    required this.unicode,
    required this.lineHeight,
    required this.ascent,
    required Map<int, String> pageSources,
    required Map<int, LoveBmFontCharacter> characters,
    required Map<int, int> kerning,
  }) : pageSources = Map<int, String>.unmodifiable(pageSources),
       characters = Map<int, LoveBmFontCharacter>.unmodifiable(characters),
       kerning = Map<int, int>.unmodifiable(kerning);

  /// The source identifier used to load this definition.
  final String source;

  /// The nominal font size declared by the definition.
  final int fontSize;

  /// Whether the font declares full Unicode support.
  final bool unicode;

  /// The declared line height in pixels.
  final int lineHeight;

  /// The baseline ascent in pixels.
  final int ascent;

  /// The page image sources keyed by page id.
  final Map<int, String> pageSources;

  /// The glyph records keyed by Unicode codepoint.
  final Map<int, LoveBmFontCharacter> characters;

  /// The kerning table keyed by packed glyph pairs.
  final Map<int, int> kerning;

  /// The glyph string reconstructed from [characters] in codepoint order.
  String get glyphs {
    final codepoints = characters.keys.toList(growable: false)..sort();
    return String.fromCharCodes(codepoints);
  }
}

/// Tracks the horizontal bounds of an image-font glyph.
final class _LoveImageGlyphData {
  /// Creates cached image-font glyph bounds.
  const _LoveImageGlyphData({required this.x, required this.width});

  /// The left pixel offset of the glyph within the source image.
  final int x;

  /// The glyph width in pixels.
  final int width;
}

/// Returns a synthesized tab advance for TrueType fonts that omit tab glyphs.
double? _loveTrueTypeSyntheticTabAdvance(
  LoveTrueTypeFontMetadata? metadata, {
  required double size,
  required double dpiScale,
}) {
  final localMetadata = metadata;
  if (localMetadata == null ||
      localMetadata.containsCodepoint(_loveTabCodepoint)) {
    return null;
  }

  final pixelHeight = math.max(1, (size * dpiScale).round());
  final pixelSpaceAdvance = localMetadata.pixelGlyphAdvance(0x20, pixelHeight);
  if (pixelSpaceAdvance == null || pixelSpaceAdvance <= 0) {
    return null;
  }

  final scale = dpiScale <= 0 ? 1.0 : dpiScale;
  return (pixelSpaceAdvance * _loveSpacesPerTab) / scale;
}

/// Truncates a numeric glyph value to an integer codepoint.
int _truncateLoveFontNumericCodepoint(num value) => value.truncate();

/// Builds [LoveFont] values and rasterized glyphs from supported font assets.
final class LoveRasterizer {
  /// Creates a rasterizer backed by TrueType or OpenType outline data.
  LoveRasterizer.trueType({
    required double size,
    required this.hinting,
    required this.dpiScale,
    this.source,
    List<int>? sourceBytes,
  }) : kind = LoveRasterizerKind.trueType,
       imageData = null,
       bmFontDefinition = null,
       bmFontPages = null,
       _imageGlyphs = null,
       _imageSpacer = null,
       glyphs = null,
       extraSpacing = 0 {
    _trueTypeSourceBytes = sourceBytes == null
        ? null
        : Uint8List.fromList(sourceBytes);
    _logicalSize = size;
    final metadata = parseLoveTrueTypeFontMetadata(sourceBytes);
    final pixelHeight = math.max(1, (size * dpiScale).round());
    _trueTypeGlyphPixelHeight = pixelHeight;
    _height = metadata?.pixelHeightMetric(pixelHeight) ?? pixelHeight;
    _advance =
        metadata?.pixelMaxAdvance(pixelHeight) ??
        math.max(1, (pixelHeight * 0.6).round());
    _ascent =
        metadata?.pixelAscent(pixelHeight) ??
        math.max(1, (_height * 0.8).round());
    _descent =
        metadata?.pixelDescent(pixelHeight) ?? math.max(0, _height - _ascent);
    _lineHeight = math.max(1, (_height * 1.25).round());
    _trueTypeMetadata = metadata;
    _glyphCount = metadata?.glyphCount ?? 0;
    _glyphCountSupported = metadata?.supportsGlyphCount ?? false;
  }

  /// Creates a rasterizer backed by an image-strip font.
  LoveRasterizer.image({
    required LoveImageData this.imageData,
    required this.glyphs,
    required this.extraSpacing,
    required this.dpiScale,
    this.source,
    this.kind = LoveRasterizerKind.image,
  }) : bmFontDefinition = null,
       bmFontPages = null,
       _imageGlyphs = _loadImageGlyphs(imageData, glyphs!),
       _imageSpacer = imageData.getPixel(0, 0),
       hinting = 'normal' {
    _trueTypeSourceBytes = null;
    _trueTypeMetadata = null;
    _trueTypeGlyphPixelHeight = imageData!.height;
    _height = imageData!.height;
    _advance = _imageGlyphs!.values.fold<int>(
      0,
      (maximum, glyph) => math.max(maximum, glyph.width + extraSpacing),
    );
    _ascent = _height;
    _descent = 0;
    _lineHeight = _height;
    _glyphCount = glyphs!.runes.length;
    _glyphCountSupported = true;
    _logicalSize = dpiScale <= 0 ? _height.toDouble() : _height / dpiScale;
  }

  /// Creates a rasterizer backed by a parsed BMFont definition.
  LoveRasterizer.bmFont({
    required LoveBmFontDefinition definition,
    required Map<int, LoveImageData> pageImages,
    required this.dpiScale,
    this.source,
  }) : kind = LoveRasterizerKind.bmFont,
       imageData = null,
       bmFontDefinition = definition,
       bmFontPages = Map<int, LoveImageData>.unmodifiable(
         Map<int, LoveImageData>.from(pageImages),
       ),
       _imageGlyphs = null,
       _imageSpacer = null,
       glyphs = definition.glyphs,
       extraSpacing = 0,
       hinting = 'normal' {
    _trueTypeSourceBytes = null;
    _trueTypeMetadata = null;
    _trueTypeGlyphPixelHeight = math.max(0, definition.lineHeight);
    _height = math.max(0, definition.lineHeight);
    _advance = definition.characters.values.fold<int>(
      0,
      (maximum, character) => math.max(maximum, character.advance),
    );
    _ascent = math.max(0, definition.ascent);
    _descent = math.max(0, _height - _ascent);
    _lineHeight = _height;
    _glyphCount = definition.characters.length;
    _glyphCountSupported = true;
    _logicalSize = dpiScale <= 0 ? _height.toDouble() : _height / dpiScale;
  }

  /// The source asset kind used by this rasterizer.
  final LoveRasterizerKind kind;

  /// The original asset path or identifier when known.
  final String? source;

  /// The source image for image-font rasterizers.
  final LoveImageData? imageData;

  /// The parsed BMFont definition for BMFont rasterizers.
  final LoveBmFontDefinition? bmFontDefinition;

  /// The loaded BMFont page images keyed by page id.
  final Map<int, LoveImageData>? bmFontPages;

  /// The cached glyph ranges for image-font rasterizers.
  final Map<int, _LoveImageGlyphData>? _imageGlyphs;

  /// The transparent spacer color used by image-font rasterizers.
  final LoveColor? _imageSpacer;

  /// The glyph string declared by the source asset, when available.
  final String? glyphs;

  /// The extra advance added after each image-font glyph.
  final int extraSpacing;

  /// The hinting mode requested for TrueType rasterization.
  final String hinting;

  /// The device pixel ratio used to derive pixel metrics.
  final double dpiScale;
  late final LoveTrueTypeFontMetadata? _trueTypeMetadata;
  late final Uint8List? _trueTypeSourceBytes;

  late final int _height;
  late final int _advance;
  late final int _ascent;
  late final int _descent;
  late final int _lineHeight;
  late final int _glyphCount;
  late final bool _glyphCountSupported;
  late final int _trueTypeGlyphPixelHeight;
  late final double _logicalSize;

  /// The cached glyph data keyed by Unicode codepoint.
  final Map<int, LoveGlyphData> _glyphCache = <int, LoveGlyphData>{};

  /// The glyph height in pixels.
  int get height => _height;

  /// The maximum glyph advance in pixels.
  int get advance => _advance;

  /// The ascent above the baseline in pixels.
  int get ascent => _ascent;

  /// The descent below the baseline in pixels.
  int get descent => _descent;

  /// The line height in pixels.
  int get lineHeight => _lineHeight;

  /// The number of glyphs reported by the source asset.
  int get glyphCount => _glyphCount;

  /// Whether [glyphCount] came from source metadata instead of a fallback.
  bool get supportsGlyphCount => _glyphCountSupported;

  /// Returns whether this rasterizer can produce glyph data for [glyph].
  bool hasGlyph(int glyph) {
    return switch (kind) {
      LoveRasterizerKind.trueType =>
        _trueTypeMetadata?.supportsCodepointCallback?.call(glyph) ??
            _isValidUnicodeScalar(glyph),
      LoveRasterizerKind.image => _imageGlyphs!.containsKey(glyph),
      LoveRasterizerKind.bmFont => bmFontDefinition!.characters.containsKey(
        glyph,
      ),
    };
  }

  /// Returns whether every value in [values] maps to supported glyphs.
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
            if (!hasGlyph(codepoint)) {
              return false;
            }
          }
        case num codepoint:
          if (!hasGlyph(_truncateLoveFontNumericCodepoint(codepoint))) {
            return false;
          }
        default:
          return false;
      }
    }

    return true;
  }

  /// Returns glyph data for a glyph string or numeric codepoint [value].
  LoveGlyphData glyphDataForValue(Object? value) {
    final glyph = switch (value) {
      String text when text.isNotEmpty => text.runes.first,
      num number => _truncateLoveFontNumericCodepoint(number),
      _ => throw ArgumentError.value(
        value,
        'value',
        'Expected glyph string or codepoint',
      ),
    };

    return _glyphCache.putIfAbsent(glyph, () => _buildGlyphData(glyph));
  }

  /// Returns a fallback tab advance when the source omits a tab glyph.
  double? _syntheticTabAdvance() {
    if (_hasNativeTabGlyph) {
      return null;
    }

    if (kind == LoveRasterizerKind.trueType) {
      return _loveTrueTypeSyntheticTabAdvance(
        _trueTypeMetadata,
        size: _logicalSize,
        dpiScale: dpiScale,
      );
    }

    final pixelSpaceAdvance = switch (kind) {
      LoveRasterizerKind.trueType => null,
      LoveRasterizerKind.image => switch (_imageGlyphs![0x20]) {
        final imageGlyph? => imageGlyph.width + extraSpacing,
        null => null,
      },
      LoveRasterizerKind.bmFont => bmFontDefinition!.characters[0x20]?.advance,
    };
    if (pixelSpaceAdvance == null || pixelSpaceAdvance <= 0) {
      return null;
    }

    final scale = dpiScale <= 0 ? 1.0 : dpiScale;
    return (pixelSpaceAdvance * _loveSpacesPerTab) / scale;
  }

  /// Whether the source asset includes an explicit tab glyph.
  bool get _hasNativeTabGlyph {
    return switch (kind) {
      LoveRasterizerKind.trueType =>
        _trueTypeMetadata?.containsCodepoint(_loveTabCodepoint) ?? false,
      LoveRasterizerKind.image => _imageGlyphs!.containsKey(_loveTabCodepoint),
      LoveRasterizerKind.bmFont => bmFontDefinition!.characters.containsKey(
        _loveTabCodepoint,
      ),
    };
  }

  /// Converts this rasterizer into a [LoveFont] description.
  LoveFont toLoveFont({required LoveGraphicsDefaultFilter defaultFilter}) {
    final logicalSize = _logicalSize;
    final syntheticTabAdvance = _syntheticTabAdvance();
    return switch (kind) {
      LoveRasterizerKind.trueType => LoveFont(
        size: logicalSize,
        source: source,
        fontType: LoveFont.trueTypeFontType,
        dataType: LoveFont.trueTypeFontType,
        glyphAdvance: _trueTypeMetadata?.logicalMaxAdvance(
          logicalSize,
          dpiScale: dpiScale,
        ),
        glyphAdvances: _trueTypeMetadata?.logicalGlyphAdvances(
          logicalSize,
          dpiScale: dpiScale,
        ),
        glyphKernings: _trueTypeMetadata?.logicalKerning(
          logicalSize,
          dpiScale: dpiScale,
        ),
        hinting: hinting,
        dpiScale: dpiScale,
        heightOverride: height / (dpiScale <= 0 ? 1.0 : dpiScale),
        ascentOverride: ascent / (dpiScale <= 0 ? 1.0 : dpiScale),
        descentOverride: descent / (dpiScale <= 0 ? 1.0 : dpiScale),
        missingGlyphAdvance: _advance / (dpiScale <= 0 ? 1.0 : dpiScale),
        syntheticTabAdvance: syntheticTabAdvance,
        filter: defaultFilter,
        supportsCodepointCallback: _trueTypeMetadata?.supportsCodepointCallback,
      ),
      LoveRasterizerKind.image => LoveFont(
        size: logicalSize,
        source: source,
        fontType: LoveFont.imageFontType,
        dataType: LoveFont.imageFontType,
        glyphs: glyphs,
        glyphAdvance: _advance <= 0
            ? null
            : _advance / (dpiScale <= 0 ? 1.0 : dpiScale),
        glyphAdvances: <int, double>{
          for (final entry in _imageGlyphs!.entries)
            entry.key:
                (entry.value.width + extraSpacing) /
                (dpiScale <= 0 ? 1.0 : dpiScale),
        },
        extraSpacing: extraSpacing / (dpiScale <= 0 ? 1.0 : dpiScale),
        dpiScale: dpiScale,
        heightOverride: height / (dpiScale <= 0 ? 1.0 : dpiScale),
        ascentOverride: ascent / (dpiScale <= 0 ? 1.0 : dpiScale),
        descentOverride: descent / (dpiScale <= 0 ? 1.0 : dpiScale),
        syntheticTabAdvance: syntheticTabAdvance,
        filter: defaultFilter,
      ),
      LoveRasterizerKind.bmFont => _bmFontToLoveFont(
        defaultFilter: defaultFilter,
        logicalSize: logicalSize,
        syntheticTabAdvance: syntheticTabAdvance,
      ),
    };
  }

  /// Builds glyph data for [glyph] using the active rasterizer kind.
  LoveGlyphData _buildGlyphData(int glyph) {
    return switch (kind) {
      LoveRasterizerKind.trueType => _buildTrueTypeGlyphData(glyph),
      LoveRasterizerKind.image => _buildImageGlyphData(glyph),
      LoveRasterizerKind.bmFont => _buildBmFontGlyphData(glyph),
    };
  }

  /// Builds glyph data for a TrueType glyph.
  LoveGlyphData _buildTrueTypeGlyphData(int glyph) {
    final scaledMetrics = _trueTypeMetadata?._scaledGlyphMetrics(
      glyph,
      _trueTypeGlyphPixelHeight,
    );
    if (scaledMetrics != null) {
      final bytes = _rasterizeTrueTypeGlyphLa8(
        _trueTypeSourceBytes,
        _trueTypeMetadata,
        codepoint: glyph,
        pixelHeight: _trueTypeGlyphPixelHeight,
        hinting: hinting,
      );
      return LoveGlyphData(
        glyph: glyph,
        width: scaledMetrics.width,
        height: scaledMetrics.height,
        advance: scaledMetrics.advance,
        bearingX: scaledMetrics.bearingX,
        bearingY: scaledMetrics.bearingY,
        format: 'la8',
        bytes: bytes,
      );
    }

    final width = _estimatedTrueTypeGlyphWidth(glyph);
    return LoveGlyphData(
      glyph: glyph,
      width: width,
      height: _trueTypeGlyphPixelHeight,
      advance: width,
      bearingX: 0,
      bearingY: ascent,
      format: 'la8',
    );
  }

  /// Builds glyph data for an image-font glyph.
  LoveGlyphData _buildImageGlyphData(int glyph) {
    final imageGlyph = _imageGlyphs![glyph];
    if (imageGlyph == null) {
      return LoveGlyphData(
        glyph: glyph,
        width: 0,
        height: height,
        advance: 0,
        bearingX: 0,
        bearingY: 0,
        format: 'rgba8',
      );
    }

    final bytes = _glyphBytesFromImage(
      imageData!,
      x: imageGlyph.x,
      y: 0,
      width: imageGlyph.width,
      height: imageData!.height,
      transparentColor: _imageSpacer,
    );
    return LoveGlyphData(
      glyph: glyph,
      width: imageGlyph.width,
      height: imageData!.height,
      advance: imageGlyph.width + extraSpacing,
      bearingX: 0,
      bearingY: 0,
      format: 'rgba8',
      bytes: bytes,
    );
  }

  /// Builds glyph data for a BMFont glyph.
  LoveGlyphData _buildBmFontGlyphData(int glyph) {
    final definition = bmFontDefinition!;
    final character = definition.characters[glyph];
    if (character == null) {
      return LoveGlyphData(
        glyph: glyph,
        width: 0,
        height: 0,
        advance: 0,
        bearingX: 0,
        bearingY: 0,
        format: 'rgba8',
      );
    }

    final page = bmFontPages![character.page];
    if (page == null) {
      return LoveGlyphData(
        glyph: glyph,
        width: 0,
        height: 0,
        advance: 0,
        bearingX: 0,
        bearingY: 0,
        format: 'rgba8',
      );
    }

    final bytes = character.width > 0 && character.height > 0
        ? _glyphBytesFromImage(
            page,
            x: character.x,
            y: character.y,
            width: character.width,
            height: character.height,
          )
        : null;
    return LoveGlyphData(
      glyph: glyph,
      width: character.width,
      height: character.height,
      advance: character.advance,
      bearingX: character.bearingX,
      bearingY: character.bearingY,
      format: 'rgba8',
      bytes: bytes,
    );
  }

  /// Converts cached BMFont data into a [LoveFont].
  LoveFont _bmFontToLoveFont({
    required LoveGraphicsDefaultFilter defaultFilter,
    required double logicalSize,
    required double? syntheticTabAdvance,
  }) {
    final definition = bmFontDefinition!;
    final scale = dpiScale <= 0 ? 1.0 : dpiScale;
    return LoveFont(
      size: logicalSize,
      source: source,
      fontType: LoveFont.imageFontType,
      dataType: LoveFont.bmFontDataType,
      glyphs: glyphs,
      glyphAdvances: <int, double>{
        for (final entry in definition.characters.entries)
          entry.key: entry.value.advance / scale,
      },
      glyphKernings: <int, double>{
        for (final entry in definition.kerning.entries)
          entry.key: entry.value / scale,
      },
      dpiScale: dpiScale,
      ascentOverride: definition.ascent / scale,
      descentOverride:
          math.max(0, definition.lineHeight - definition.ascent) / scale,
      syntheticTabAdvance: syntheticTabAdvance,
      filter: defaultFilter,
    );
  }

  /// Estimates a fallback TrueType glyph width when metrics are unavailable.
  int _estimatedTrueTypeGlyphWidth(int glyph) {
    if (glyph == 9) {
      return math.max(1, advance * 4);
    }
    if (glyph == 32) {
      return math.max(1, (advance * 0.6).round());
    }
    return advance;
  }
}

/// Returns whether [glyph] is a valid Unicode scalar value.
bool _isValidUnicodeScalar(int glyph) {
  return glyph >= 0 && glyph <= 0x10ffff && (glyph < 0xd800 || glyph > 0xdfff);
}

/// Scans an image font strip and records each glyph's horizontal bounds.
Map<int, _LoveImageGlyphData> _loadImageGlyphs(
  LoveImageData imageData,
  String glyphs,
) {
  final glyphData = <int, _LoveImageGlyphData>{};
  final spacer = imageData.getPixel(0, 0);
  var start = 0;
  var end = 0;

  for (final glyph in glyphs.runes) {
    start = end;
    while (start < imageData.width && imageData.getPixel(start, 0) == spacer) {
      start++;
    }

    end = start;
    while (end < imageData.width && imageData.getPixel(end, 0) != spacer) {
      end++;
    }

    if (start >= end) {
      break;
    }

    glyphData[glyph] = _LoveImageGlyphData(x: start, width: end - start);
  }

  return glyphData;
}

/// Returns whether [bytes] appear to start with a BMFont text definition.
bool loveLooksLikeBmFontDefinition(List<int> bytes) {
  return bytes.length > 4 &&
      bytes[0] == 0x69 &&
      bytes[1] == 0x6e &&
      bytes[2] == 0x66 &&
      bytes[3] == 0x6f;
}

/// Returns whether [bytes] appear to contain TrueType-family font data.
bool loveLooksLikeTrueTypeFontData(List<int> bytes) {
  return _matchesFontSignature(bytes, const <int>[0x00, 0x01, 0x00, 0x00]) ||
      _matchesFontSignature(bytes, const <int>[0x4f, 0x54, 0x54, 0x4f]) ||
      _matchesFontSignature(bytes, const <int>[0x74, 0x74, 0x63, 0x66]) ||
      _matchesFontSignature(bytes, const <int>[0x74, 0x72, 0x75, 0x65]) ||
      _matchesFontSignature(bytes, const <int>[0x74, 0x79, 0x70, 0x31]);
}

/// Parses a text BMFont definition from [bytes].
LoveBmFontDefinition parseLoveBmFontDefinition({
  required List<int> bytes,
  required String source,
}) {
  final text = convert.utf8.decode(bytes, allowMalformed: true);
  final pageSources = <int, String>{};
  final characters = <int, LoveBmFontCharacter>{};
  final kerning = <int, int>{};

  var fontSize = 0;
  var unicode = false;
  var lineHeight = 0;
  var ascent = 0;

  for (final line in const convert.LineSplitter().convert(text)) {
    if (line.isEmpty) {
      continue;
    }

    final separator = line.indexOf(' ');
    final tag = separator < 0 ? line : line.substring(0, separator);
    final attributes = _parseBmFontAttributes(
      separator < 0 ? '' : line.substring(separator + 1),
    );

    switch (tag) {
      case 'info':
        fontSize = _bmFontInt(attributes, 'size');
        unicode = _bmFontInt(attributes, 'unicode') > 0;
      case 'common':
        lineHeight = _bmFontInt(attributes, 'lineHeight');
        ascent = _bmFontInt(attributes, 'base');
      case 'page':
        pageSources[_bmFontInt(attributes, 'id')] = attributes['file'] ?? '';
      case 'char':
        final glyph = _bmFontInt(attributes, 'id');
        characters[glyph] = LoveBmFontCharacter(
          glyph: glyph,
          x: _bmFontInt(attributes, 'x'),
          y: _bmFontInt(attributes, 'y'),
          page: _bmFontInt(attributes, 'page'),
          width: _bmFontInt(attributes, 'width'),
          height: _bmFontInt(attributes, 'height'),
          advance: _bmFontInt(attributes, 'xadvance'),
          bearingX: _bmFontInt(attributes, 'xoffset'),
          bearingY: -_bmFontInt(attributes, 'yoffset'),
        );
      case 'kerning':
        final first = _bmFontInt(attributes, 'first');
        final second = _bmFontInt(attributes, 'second');
        kerning[_packLoveGlyphPair(first, second)] = _bmFontInt(
          attributes,
          'amount',
        );
    }
  }

  if (characters.isEmpty) {
    throw ArgumentError('Invalid BMFont file (no character definitions?)');
  }

  var resolvedLineHeight = lineHeight;
  if (resolvedLineHeight == 0) {
    for (final character in characters.values) {
      resolvedLineHeight = math.max(resolvedLineHeight, character.height);
    }
  }

  if (resolvedLineHeight < 0) {
    throw ArgumentError('Invalid BMFont lineHeight.');
  }

  for (final entry in characters.entries) {
    final glyph = entry.key;
    final character = entry.value;
    if (!unicode && glyph > 127) {
      throw ArgumentError(
        'Invalid BMFont character id (only unicode and ASCII are supported)',
      );
    }
    if (character.page < 0) {
      throw ArgumentError(
        'Invalid BMFont character page id: ${character.page}',
      );
    }
  }

  return LoveBmFontDefinition(
    source: source,
    fontSize: fontSize,
    unicode: unicode,
    lineHeight: resolvedLineHeight,
    ascent: ascent,
    pageSources: pageSources,
    characters: characters,
    kerning: kerning,
  );
}

/// Parses BMFont key-value attributes from a tag payload.
Map<String, String> _parseBmFontAttributes(String source) {
  final attributes = <String, String>{};
  final matches = RegExp(
    r'([A-Za-z0-9_]+)=("([^"]*)"|[^ ]+)',
  ).allMatches(source);
  for (final match in matches) {
    final key = match.group(1);
    final value = match.group(3) ?? match.group(2);
    if (key != null && value != null) {
      attributes[key] = value;
    }
  }
  return attributes;
}

/// Reads an integer BMFont attribute from [attributes].
int _bmFontInt(Map<String, String> attributes, String key) {
  final value = attributes[key];
  if (value == null || value.isEmpty) {
    return 0;
  }
  return int.tryParse(value) ?? 0;
}

/// Returns whether [bytes] begins with [signature].
bool _matchesFontSignature(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) {
    return false;
  }

  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) {
      return false;
    }
  }

  return true;
}

/// Returns the first SFNT table offset in [bytes], if present.
int? _trueTypeSfntOffset(List<int> bytes) {
  if (bytes.length < 12) {
    return null;
  }

  if (_matchesFontSignature(bytes, const <int>[0x74, 0x74, 0x63, 0x66])) {
    final numFonts = _readUint32Be(bytes, 8);
    if (numFonts <= 0 || bytes.length < 16) {
      return null;
    }

    final firstFontOffset = _readUint32Be(bytes, 12);
    return _looksLikeSfntAt(bytes, firstFontOffset) ? firstFontOffset : null;
  }

  return _looksLikeSfntAt(bytes, 0) ? 0 : null;
}

/// Returns whether [bytes] contains a valid SFNT header at [offset].
bool _looksLikeSfntAt(List<int> bytes, int offset) {
  if (offset < 0 || bytes.length < offset + 12) {
    return false;
  }

  final signature = bytes.sublist(offset, offset + 4);
  final looksLikeSfnt =
      _matchesFontSignature(signature, const <int>[0x00, 0x01, 0x00, 0x00]) ||
      _matchesFontSignature(signature, const <int>[0x4f, 0x54, 0x54, 0x4f]) ||
      _matchesFontSignature(signature, const <int>[0x74, 0x72, 0x75, 0x65]) ||
      _matchesFontSignature(signature, const <int>[0x74, 0x79, 0x70, 0x31]);
  if (!looksLikeSfnt) {
    return false;
  }

  final numTables = _readUint16Be(bytes, offset + 4);
  return numTables > 0 && bytes.length >= offset + 12 + (numTables * 16);
}

/// Returns the offset of the SFNT table identified by [tag].
int? _findSfntTableOffset(List<int> bytes, int sfntOffset, String tag) {
  final numTables = _readUint16Be(bytes, sfntOffset + 4);
  final tagBytes = tag.codeUnits;
  for (var index = 0; index < numTables; index++) {
    final recordOffset = sfntOffset + 12 + (index * 16);
    if (recordOffset + 16 > bytes.length) {
      return null;
    }

    if (bytes[recordOffset] == tagBytes[0] &&
        bytes[recordOffset + 1] == tagBytes[1] &&
        bytes[recordOffset + 2] == tagBytes[2] &&
        bytes[recordOffset + 3] == tagBytes[3]) {
      final tableOffset = _readUint32Be(bytes, recordOffset + 8);
      final tableLength = _readUint32Be(bytes, recordOffset + 12);
      if (tableOffset + tableLength > bytes.length) {
        return null;
      }
      return tableOffset;
    }
  }

  return null;
}

/// Reads an unsigned 16-bit big-endian integer from [bytes].
int _readUint16Be(List<int> bytes, int offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

/// Reads an unsigned 32-bit big-endian integer from [bytes].
int _readUint32Be(List<int> bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

/// Packs a glyph pair into a single kerning-table key.
int _packLoveGlyphPair(int leftGlyph, int rightGlyph) {
  return (leftGlyph << 32) ^ rightGlyph;
}

/// Normalizes glyph pixel bytes to the expected buffer length.
Uint8List _loveGlyphBytes({
  required int width,
  required int height,
  required String format,
  List<int>? bytes,
}) {
  final expectedLength = width <= 0 || height <= 0
      ? 0
      : width * height * _loveGlyphPixelStride(format);
  if (expectedLength == 0) {
    return Uint8List(0);
  }

  if (bytes == null) {
    return _blankLoveGlyphBytes(expectedLength, format: format);
  }

  final normalized = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (normalized.length < expectedLength) {
    throw ArgumentError.value(
      normalized.length,
      'bytes.length',
      'Expected at least $expectedLength bytes for a ${width}x$height '
          '$format glyph',
    );
  }
  return Uint8List.fromList(normalized.sublist(0, expectedLength));
}

/// Creates a blank glyph pixel buffer for [format].
Uint8List _blankLoveGlyphBytes(int length, {required String format}) {
  final bytes = Uint8List(length);
  switch (format) {
    case 'la8':
      for (var index = 0; index < length; index += 2) {
        bytes[index] = 255;
      }
      return bytes;
    case 'rgba8':
      return bytes;
    default:
      throw ArgumentError.value(
        format,
        'format',
        'Unsupported GlyphData pixel format',
      );
  }
}

/// Returns the bytes-per-pixel stride for a glyph [format].
int _loveGlyphPixelStride(String format) {
  return switch (format) {
    'la8' => 2,
    'rgba8' => 4,
    _ => throw ArgumentError.value(
      format,
      'format',
      'Unsupported GlyphData pixel format',
    ),
  };
}

/// Extracts RGBA glyph bytes from [imageData].
Uint8List _glyphBytesFromImage(
  LoveImageData imageData, {
  required int x,
  required int y,
  required int width,
  required int height,
  LoveColor? transparentColor,
}) {
  final bytes = Uint8List(width * height * 4);
  var offset = 0;
  for (var row = 0; row < height; row++) {
    for (var column = 0; column < width; column++) {
      final pixel = imageData.getPixel(x + column, y + row);
      final outputPixel = transparentColor != null && pixel == transparentColor
          ? const LoveColor(0, 0, 0, 0)
          : pixel;
      bytes[offset++] = (outputPixel.r * 255).round();
      bytes[offset++] = (outputPixel.g * 255).round();
      bytes[offset++] = (outputPixel.b * 255).round();
      bytes[offset++] = (outputPixel.a * 255).round();
    }
  }
  return bytes;
}
