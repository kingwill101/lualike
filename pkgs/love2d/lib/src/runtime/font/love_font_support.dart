part of '../love_runtime.dart';

enum LoveRasterizerKind { trueType, image, bmFont }

final class LoveGlyphData extends LoveDataObject {
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

  final int glyph;
  final int width;
  final int height;
  final int advance;
  final int bearingX;
  final int bearingY;
  final String format;

  int get minX => bearingX;

  int get minY => height - bearingY;

  int get maxX => bearingX + width;

  int get maxY => bearingY;

  String get glyphString => String.fromCharCode(glyph);

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

final class LoveBmFontCharacter {
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

  final int glyph;
  final int x;
  final int y;
  final int page;
  final int width;
  final int height;
  final int advance;
  final int bearingX;
  final int bearingY;
}

final class LoveBmFontDefinition {
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

  final String source;
  final int fontSize;
  final bool unicode;
  final int lineHeight;
  final int ascent;
  final Map<int, String> pageSources;
  final Map<int, LoveBmFontCharacter> characters;
  final Map<int, int> kerning;

  String get glyphs {
    final codepoints = characters.keys.toList(growable: false)..sort();
    return String.fromCharCodes(codepoints);
  }
}

final class _LoveImageGlyphData {
  const _LoveImageGlyphData({required this.x, required this.width});

  final int x;
  final int width;
}

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

int _truncateLoveFontNumericCodepoint(num value) => value.truncate();

final class LoveRasterizer {
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

  final LoveRasterizerKind kind;
  final String? source;
  final LoveImageData? imageData;
  final LoveBmFontDefinition? bmFontDefinition;
  final Map<int, LoveImageData>? bmFontPages;
  final Map<int, _LoveImageGlyphData>? _imageGlyphs;
  final LoveColor? _imageSpacer;
  final String? glyphs;
  final int extraSpacing;
  final String hinting;
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
  final Map<int, LoveGlyphData> _glyphCache = <int, LoveGlyphData>{};

  int get height => _height;

  int get advance => _advance;

  int get ascent => _ascent;

  int get descent => _descent;

  int get lineHeight => _lineHeight;

  int get glyphCount => _glyphCount;

  bool get supportsGlyphCount => _glyphCountSupported;

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

  LoveGlyphData _buildGlyphData(int glyph) {
    return switch (kind) {
      LoveRasterizerKind.trueType => _buildTrueTypeGlyphData(glyph),
      LoveRasterizerKind.image => _buildImageGlyphData(glyph),
      LoveRasterizerKind.bmFont => _buildBmFontGlyphData(glyph),
    };
  }

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

bool _isValidUnicodeScalar(int glyph) {
  return glyph >= 0 && glyph <= 0x10ffff && (glyph < 0xd800 || glyph > 0xdfff);
}

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

bool loveLooksLikeBmFontDefinition(List<int> bytes) {
  return bytes.length > 4 &&
      bytes[0] == 0x69 &&
      bytes[1] == 0x6e &&
      bytes[2] == 0x66 &&
      bytes[3] == 0x6f;
}

bool loveLooksLikeTrueTypeFontData(List<int> bytes) {
  return _matchesFontSignature(bytes, const <int>[0x00, 0x01, 0x00, 0x00]) ||
      _matchesFontSignature(bytes, const <int>[0x4f, 0x54, 0x54, 0x4f]) ||
      _matchesFontSignature(bytes, const <int>[0x74, 0x74, 0x63, 0x66]) ||
      _matchesFontSignature(bytes, const <int>[0x74, 0x72, 0x75, 0x65]) ||
      _matchesFontSignature(bytes, const <int>[0x74, 0x79, 0x70, 0x31]);
}

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

int _bmFontInt(Map<String, String> attributes, String key) {
  final value = attributes[key];
  if (value == null || value.isEmpty) {
    return 0;
  }
  return int.tryParse(value) ?? 0;
}

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

int _readUint16Be(List<int> bytes, int offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

int _readUint32Be(List<int> bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _packLoveGlyphPair(int leftGlyph, int rightGlyph) {
  return (leftGlyph << 32) ^ rightGlyph;
}

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
