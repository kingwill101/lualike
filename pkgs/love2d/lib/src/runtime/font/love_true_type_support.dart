part of '../love_runtime.dart';

final class LoveTrueTypeFontMetadata {
  LoveTrueTypeFontMetadata._({
    required this.glyphCount,
    required this.unitsPerEm,
    required this.maxAdvanceWidth,
    required this.ascender,
    required this.descender,
    required this.lineGap,
    required Map<int, int>? codepointToGlyphIndex,
    required Map<int, int>? codepointAdvanceWidths,
    required Map<int, int>? codepointKerning,
    required Map<int, _LoveTrueTypeGlyphMetrics>? codepointGlyphMetrics,
  }) : _codepointToGlyphIndex = codepointToGlyphIndex == null
           ? null
           : Map<int, int>.unmodifiable(
               Map<int, int>.from(codepointToGlyphIndex),
             ),
       _codepointAdvanceWidths = codepointAdvanceWidths == null
           ? null
           : Map<int, int>.unmodifiable(
               Map<int, int>.from(codepointAdvanceWidths),
             ),
       _codepointKerning = codepointKerning == null
           ? null
           : Map<int, int>.unmodifiable(Map<int, int>.from(codepointKerning)),
       _codepointGlyphMetrics = codepointGlyphMetrics == null
           ? null
           : Map<int, _LoveTrueTypeGlyphMetrics>.unmodifiable(
               Map<int, _LoveTrueTypeGlyphMetrics>.from(codepointGlyphMetrics),
             );

  final int? glyphCount;
  final int? unitsPerEm;
  final int? maxAdvanceWidth;
  final int? ascender;
  final int? descender;
  final int? lineGap;
  final Map<int, int>? _codepointToGlyphIndex;
  final Map<int, int>? _codepointAdvanceWidths;
  final Map<int, int>? _codepointKerning;
  final Map<int, _LoveTrueTypeGlyphMetrics>? _codepointGlyphMetrics;

  bool get supportsGlyphCount => glyphCount != null && glyphCount! > 0;

  LoveFontSupportsCodepoint? get supportsCodepointCallback {
    if (_codepointToGlyphIndex == null) {
      return null;
    }
    return containsCodepoint;
  }

  bool containsCodepoint(int codepoint) {
    if (!_isValidUnicodeScalar(codepoint)) {
      return false;
    }
    return _codepointToGlyphIndex?.containsKey(codepoint) ?? false;
  }

  Map<int, double>? logicalGlyphAdvances(double size, {double dpiScale = 1.0}) {
    final advances = _codepointAdvanceWidths;
    final localUnitsPerEm = unitsPerEm;
    final pixelHeight = math.max(1, (size * dpiScale).round());
    if (advances == null ||
        advances.isEmpty ||
        localUnitsPerEm == null ||
        localUnitsPerEm <= 0) {
      return null;
    }

    final resolvedDpiScale = dpiScale <= 0 ? 1.0 : dpiScale;
    return Map<int, double>.unmodifiable(<int, double>{
      for (final entry in advances.entries)
        entry.key: _logicalSnappedMetric(
          entry.value * (pixelHeight / localUnitsPerEm),
          dpiScale: resolvedDpiScale,
        ),
    });
  }

  Map<int, double>? logicalKerning(double size, {double dpiScale = 1.0}) {
    final kerning = _codepointKerning;
    final pixelHeight = math.max(1, (size * dpiScale).round());
    final pixelScale = _pixelScaleForHeight(pixelHeight);
    if (pixelScale == null || kerning == null || kerning.isEmpty) {
      return null;
    }

    final resolvedDpiScale = dpiScale <= 0 ? 1.0 : dpiScale;
    return Map<int, double>.unmodifiable(<int, double>{
      for (final entry in kerning.entries)
        entry.key:
            (((entry.value * pixelScale).round() / resolvedDpiScale) + 0.5)
                .floorToDouble(),
    });
  }

  _LoveScaledTrueTypeGlyphMetrics? _scaledGlyphMetrics(
    int codepoint,
    int pixelHeight,
  ) {
    final scale = _pixelScaleForHeight(pixelHeight);
    final metrics = _codepointGlyphMetrics?[codepoint];
    if (scale == null || metrics == null) {
      return null;
    }
    return metrics.scale(scale);
  }

  double? logicalMaxAdvance(double size, {double dpiScale = 1.0}) {
    final advanceWidth = maxAdvanceWidth;
    final localUnitsPerEm = unitsPerEm;
    final pixelHeight = math.max(1, (size * dpiScale).round());
    if (advanceWidth == null ||
        advanceWidth <= 0 ||
        localUnitsPerEm == null ||
        localUnitsPerEm <= 0) {
      return null;
    }

    final resolvedDpiScale = dpiScale <= 0 ? 1.0 : dpiScale;
    return _logicalSnappedMetric(
      advanceWidth * (pixelHeight / localUnitsPerEm),
      dpiScale: resolvedDpiScale,
    );
  }

  int? pixelMaxAdvance(int pixelHeight) {
    final scale = _pixelScaleForHeight(pixelHeight);
    final advanceWidth = maxAdvanceWidth;
    if (scale == null || advanceWidth == null || advanceWidth <= 0) {
      return null;
    }
    return math.max(1, (advanceWidth * scale).round());
  }

  int? pixelGlyphAdvance(int codepoint, int pixelHeight) {
    final scale = _pixelScaleForHeight(pixelHeight);
    final advanceWidth = _codepointAdvanceWidths?[codepoint];
    if (scale == null || advanceWidth == null || advanceWidth < 0) {
      return null;
    }
    return math.max(0, (advanceWidth * scale).round());
  }

  double? logicalHeight(double size) {
    final scale = _logicalScaleForSize(size);
    final heightUnits = _heightUnits;
    if (scale == null || heightUnits == null) {
      return null;
    }
    return math.max(1, (heightUnits * scale).round()).toDouble();
  }

  double? logicalAscent(double size) {
    final scale = _logicalScaleForSize(size);
    final value = ascender;
    if (scale == null || value == null || value <= 0) {
      return null;
    }
    return math.max(0, (value * scale).round()).toDouble();
  }

  double? logicalDescent(double size) {
    final scale = _logicalScaleForSize(size);
    final value = descender;
    if (scale == null || value == null) {
      return null;
    }
    return math.max(0, (value.abs() * scale).round()).toDouble();
  }

  int? pixelHeightMetric(int pixelHeight) {
    final scale = _pixelScaleForHeight(pixelHeight);
    final heightUnits = _heightUnits;
    if (scale == null || heightUnits == null) {
      return null;
    }
    return math.max(1, (heightUnits * scale).round());
  }

  int? pixelAscent(int pixelHeight) {
    final scale = _pixelScaleForHeight(pixelHeight);
    final value = ascender;
    if (scale == null || value == null || value <= 0) {
      return null;
    }
    return math.max(0, (value * scale).round());
  }

  int? pixelDescent(int pixelHeight) {
    final scale = _pixelScaleForHeight(pixelHeight);
    final value = descender;
    if (scale == null || value == null) {
      return null;
    }
    return math.max(0, (value.abs() * scale).round());
  }

  int? get _heightUnits {
    final ascent = ascender;
    final descent = descender;
    if (ascent == null || descent == null) {
      return null;
    }

    final total = ascent + descent.abs() + (lineGap ?? 0);
    return total > 0 ? total : null;
  }

  double? _logicalScaleForSize(double size) {
    final localUnitsPerEm = unitsPerEm;
    if (localUnitsPerEm == null || localUnitsPerEm <= 0 || size <= 0) {
      return null;
    }
    return size / localUnitsPerEm;
  }

  double? _pixelScaleForHeight(int pixelHeight) {
    final localUnitsPerEm = unitsPerEm;
    if (localUnitsPerEm == null || localUnitsPerEm <= 0 || pixelHeight <= 0) {
      return null;
    }
    return pixelHeight / localUnitsPerEm;
  }

  double _logicalSnappedMetric(
    double scaledPixels, {
    required double dpiScale,
  }) {
    return (((scaledPixels.round()) / dpiScale) + 0.5).floorToDouble();
  }
}

final class _LoveTrueTypeHorizontalHeaderMetadata {
  const _LoveTrueTypeHorizontalHeaderMetadata({
    required this.ascent,
    required this.descent,
    required this.lineGap,
    required this.maxAdvanceWidth,
    required this.numberOfHMetrics,
  });

  final int ascent;
  final int descent;
  final int lineGap;
  final int? maxAdvanceWidth;
  final int? numberOfHMetrics;
}

final class _LoveTrueTypeGlyphMetrics {
  const _LoveTrueTypeGlyphMetrics({
    required this.advanceWidth,
    required this.leftSideBearing,
    this.xMin,
    this.yMin,
    this.xMax,
    this.yMax,
  });

  const _LoveTrueTypeGlyphMetrics.empty({
    required this.advanceWidth,
    required this.leftSideBearing,
  }) : xMin = null,
       yMin = null,
       xMax = null,
       yMax = null;

  final int advanceWidth;
  final int leftSideBearing;
  final int? xMin;
  final int? yMin;
  final int? xMax;
  final int? yMax;

  bool get hasBounds =>
      xMin != null && yMin != null && xMax != null && yMax != null;

  _LoveScaledTrueTypeGlyphMetrics scale(double scale) {
    final advance = math.max(0, (advanceWidth * scale).round());
    if (!hasBounds) {
      return _LoveScaledTrueTypeGlyphMetrics(
        width: 0,
        height: 0,
        advance: advance,
        bearingX: 0,
        bearingY: 0,
      );
    }

    final localXMin = xMin!;
    final localYMin = yMin!;
    final localXMax = xMax!;
    final localYMax = yMax!;
    return _LoveScaledTrueTypeGlyphMetrics(
      width: math.max(0, ((localXMax - localXMin) * scale).round()),
      height: math.max(0, ((localYMax - localYMin) * scale).round()),
      advance: advance,
      bearingX: (localXMin * scale).round(),
      bearingY: (localYMax * scale).round(),
    );
  }
}

final class _LoveScaledTrueTypeGlyphMetrics {
  const _LoveScaledTrueTypeGlyphMetrics({
    required this.width,
    required this.height,
    required this.advance,
    required this.bearingX,
    required this.bearingY,
  });

  final int width;
  final int height;
  final int advance;
  final int bearingX;
  final int bearingY;
}

final class _LoveTrueTypeCmapRecord {
  const _LoveTrueTypeCmapRecord({
    required this.absoluteOffset,
    required this.format,
    required this.priority,
  });

  final int absoluteOffset;
  final int format;
  final int priority;
}

LoveTrueTypeFontMetadata? parseLoveTrueTypeFontMetadata(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  final sfntOffset = _trueTypeSfntOffset(bytes);
  if (sfntOffset == null) {
    return null;
  }

  final glyphCount = _readTrueTypeGlyphCount(bytes, sfntOffset);
  final unitsPerEm = _readTrueTypeUnitsPerEm(bytes, sfntOffset);
  final horizontalHeader = _readTrueTypeHorizontalHeaderMetadata(
    bytes,
    sfntOffset,
  );
  final codepointToGlyphIndex = _tryParseTrueTypeCodepointGlyphIndices(
    bytes,
    sfntOffset,
  );
  final codepointAdvanceWidths =
      glyphCount == null ||
          horizontalHeader?.numberOfHMetrics == null ||
          codepointToGlyphIndex == null
      ? null
      : _buildTrueTypeCodepointAdvanceWidths(
          bytes,
          sfntOffset,
          glyphCount: glyphCount,
          numberOfHMetrics: horizontalHeader!.numberOfHMetrics!,
          codepointToGlyphIndex: codepointToGlyphIndex,
        );
  final codepointKerning = codepointToGlyphIndex == null
      ? null
      : _buildTrueTypeCodepointKerning(
          bytes,
          sfntOffset,
          codepointToGlyphIndex: codepointToGlyphIndex,
        );
  final codepointGlyphMetrics =
      glyphCount == null ||
          horizontalHeader?.numberOfHMetrics == null ||
          codepointToGlyphIndex == null
      ? null
      : _buildTrueTypeCodepointGlyphMetrics(
          bytes,
          sfntOffset,
          glyphCount: glyphCount,
          numberOfHMetrics: horizontalHeader!.numberOfHMetrics!,
          codepointToGlyphIndex: codepointToGlyphIndex,
        );

  if (glyphCount == null &&
      unitsPerEm == null &&
      horizontalHeader?.maxAdvanceWidth == null &&
      horizontalHeader == null &&
      codepointToGlyphIndex == null &&
      codepointAdvanceWidths == null &&
      codepointKerning == null &&
      codepointGlyphMetrics == null) {
    return null;
  }

  return LoveTrueTypeFontMetadata._(
    glyphCount: glyphCount,
    unitsPerEm: unitsPerEm,
    maxAdvanceWidth: horizontalHeader?.maxAdvanceWidth,
    ascender: horizontalHeader?.ascent,
    descender: horizontalHeader?.descent,
    lineGap: horizontalHeader?.lineGap,
    codepointToGlyphIndex: codepointToGlyphIndex,
    codepointAdvanceWidths: codepointAdvanceWidths,
    codepointKerning: codepointKerning,
    codepointGlyphMetrics: codepointGlyphMetrics,
  );
}

int? _readTrueTypeGlyphCount(List<int> bytes, int sfntOffset) {
  final maxpOffset = _findSfntTableOffset(bytes, sfntOffset, 'maxp');
  if (maxpOffset == null || maxpOffset + 6 > bytes.length) {
    return null;
  }

  final glyphCount = _readUint16Be(bytes, maxpOffset + 4);
  return glyphCount > 0 ? glyphCount : null;
}

int? _readTrueTypeUnitsPerEm(List<int> bytes, int sfntOffset) {
  final headOffset = _findSfntTableOffset(bytes, sfntOffset, 'head');
  if (headOffset == null || headOffset + 20 > bytes.length) {
    return null;
  }

  final unitsPerEm = _readUint16Be(bytes, headOffset + 18);
  return unitsPerEm > 0 ? unitsPerEm : null;
}

_LoveTrueTypeHorizontalHeaderMetadata? _readTrueTypeHorizontalHeaderMetadata(
  List<int> bytes,
  int sfntOffset,
) {
  final hheaOffset = _findSfntTableOffset(bytes, sfntOffset, 'hhea');
  if (hheaOffset == null || hheaOffset + 36 > bytes.length) {
    return null;
  }

  final ascent = _readInt16Be(bytes, hheaOffset + 4);
  final descent = _readInt16Be(bytes, hheaOffset + 6);
  final lineGap = _readInt16Be(bytes, hheaOffset + 8);
  final maxAdvanceWidth = _readUint16Be(bytes, hheaOffset + 10);
  final numberOfHMetrics = _readUint16Be(bytes, hheaOffset + 34);
  if (maxAdvanceWidth <= 0 &&
      numberOfHMetrics <= 0 &&
      ascent == 0 &&
      descent == 0 &&
      lineGap == 0) {
    return null;
  }

  return _LoveTrueTypeHorizontalHeaderMetadata(
    ascent: ascent,
    descent: descent,
    lineGap: lineGap,
    maxAdvanceWidth: maxAdvanceWidth > 0 ? maxAdvanceWidth : null,
    numberOfHMetrics: numberOfHMetrics > 0 ? numberOfHMetrics : null,
  );
}

Map<int, int>? _tryParseTrueTypeCodepointGlyphIndices(
  List<int> bytes,
  int sfntOffset,
) {
  final cmapOffset = _findSfntTableOffset(bytes, sfntOffset, 'cmap');
  if (cmapOffset == null || cmapOffset + 4 > bytes.length) {
    return null;
  }

  final numTables = _readUint16Be(bytes, cmapOffset + 2);
  final recordsEnd = cmapOffset + 4 + (numTables * 8);
  if (recordsEnd > bytes.length) {
    return null;
  }

  final records = <_LoveTrueTypeCmapRecord>[];
  final seenOffsets = <int>{};
  for (var index = 0; index < numTables; index++) {
    final recordOffset = cmapOffset + 4 + (index * 8);
    final platformId = _readUint16Be(bytes, recordOffset);
    final encodingId = _readUint16Be(bytes, recordOffset + 2);
    if (!_isUnicodeCmapRecord(platformId, encodingId)) {
      continue;
    }

    final subtableOffset = _readUint32Be(bytes, recordOffset + 4);
    final absoluteOffset = cmapOffset + subtableOffset;
    if (!seenOffsets.add(absoluteOffset) ||
        absoluteOffset < 0 ||
        absoluteOffset + 2 > bytes.length) {
      continue;
    }

    final format = _readUint16Be(bytes, absoluteOffset);
    if (format != 4 && format != 12) {
      continue;
    }

    records.add(
      _LoveTrueTypeCmapRecord(
        absoluteOffset: absoluteOffset,
        format: format,
        priority: _trueTypeCmapRecordPriority(platformId, encodingId, format),
      ),
    );
  }

  if (records.isEmpty) {
    return null;
  }

  records.sort((left, right) => left.priority.compareTo(right.priority));

  final codepointToGlyphIndex = <int, int>{};
  for (final record in records) {
    final mapping = switch (record.format) {
      4 => _parseTrueTypeFormat4GlyphIndices(bytes, record.absoluteOffset),
      12 => _parseTrueTypeFormat12GlyphIndices(bytes, record.absoluteOffset),
      _ => null,
    };
    if (mapping == null || mapping.isEmpty) {
      continue;
    }

    for (final entry in mapping.entries) {
      codepointToGlyphIndex.putIfAbsent(entry.key, () => entry.value);
    }
  }

  return codepointToGlyphIndex.isEmpty ? null : codepointToGlyphIndex;
}

int _trueTypeCmapRecordPriority(int platformId, int encodingId, int format) {
  if (platformId == 3 && encodingId == 10 && format == 12) {
    return 0;
  }
  if (platformId == 0 && format == 12) {
    return 1;
  }
  if (platformId == 3 && encodingId == 1 && format == 4) {
    return 2;
  }
  if (platformId == 0 && format == 4) {
    return 3;
  }
  if (format == 12) {
    return 4;
  }
  return 5;
}

bool _isUnicodeCmapRecord(int platformId, int encodingId) {
  return platformId == 0 ||
      (platformId == 3 && (encodingId == 1 || encodingId == 10));
}

Map<int, int>? _parseTrueTypeFormat4GlyphIndices(List<int> bytes, int offset) {
  if (offset < 0 || offset + 16 > bytes.length) {
    return null;
  }

  final length = _readUint16Be(bytes, offset + 2);
  if (length < 16 || offset + length > bytes.length) {
    return null;
  }

  final segCountX2 = _readUint16Be(bytes, offset + 6);
  if (segCountX2 == 0 || segCountX2.isOdd) {
    return null;
  }

  final segCount = segCountX2 ~/ 2;
  final endCodeOffset = offset + 14;
  final reservedPadOffset = endCodeOffset + (segCount * 2);
  final startCodeOffset = reservedPadOffset + 2;
  final idDeltaOffset = startCodeOffset + (segCount * 2);
  final idRangeOffsetOffset = idDeltaOffset + (segCount * 2);
  final subtableEnd = offset + length;
  if (idRangeOffsetOffset + (segCount * 2) > subtableEnd) {
    return null;
  }

  final codepointToGlyphIndex = <int, int>{};
  for (var segmentIndex = 0; segmentIndex < segCount; segmentIndex++) {
    final startCode = _readUint16Be(
      bytes,
      startCodeOffset + (segmentIndex * 2),
    );
    final endCode = _readUint16Be(bytes, endCodeOffset + (segmentIndex * 2));
    if (startCode > endCode) {
      continue;
    }

    final idDelta = _readInt16Be(bytes, idDeltaOffset + (segmentIndex * 2));
    final idRangeOffset = _readUint16Be(
      bytes,
      idRangeOffsetOffset + (segmentIndex * 2),
    );
    for (var codepoint = startCode; codepoint <= endCode; codepoint++) {
      if (!_isValidUnicodeScalar(codepoint)) {
        continue;
      }

      final glyphIndex = _trueTypeFormat4GlyphIndex(
        bytes,
        codepoint: codepoint,
        segmentIndex: segmentIndex,
        startCode: startCode,
        idDelta: idDelta,
        idRangeOffset: idRangeOffset,
        idRangeOffsetArrayOffset: idRangeOffsetOffset,
        subtableEnd: subtableEnd,
      );
      if (glyphIndex != null && glyphIndex > 0) {
        codepointToGlyphIndex[codepoint] = glyphIndex;
      }
    }
  }

  return codepointToGlyphIndex.isEmpty ? null : codepointToGlyphIndex;
}

int? _trueTypeFormat4GlyphIndex(
  List<int> bytes, {
  required int codepoint,
  required int segmentIndex,
  required int startCode,
  required int idDelta,
  required int idRangeOffset,
  required int idRangeOffsetArrayOffset,
  required int subtableEnd,
}) {
  if (idRangeOffset == 0) {
    final glyphIndex = (codepoint + idDelta) & 0xffff;
    return glyphIndex == 0 ? null : glyphIndex;
  }

  final glyphIndexOffset =
      idRangeOffsetArrayOffset +
      (segmentIndex * 2) +
      idRangeOffset +
      ((codepoint - startCode) * 2);
  if (glyphIndexOffset < 0 || glyphIndexOffset + 2 > subtableEnd) {
    return null;
  }

  final glyphIndex = _readUint16Be(bytes, glyphIndexOffset);
  if (glyphIndex == 0) {
    return null;
  }

  final adjustedGlyphIndex = (glyphIndex + idDelta) & 0xffff;
  return adjustedGlyphIndex == 0 ? null : adjustedGlyphIndex;
}

Map<int, int>? _parseTrueTypeFormat12GlyphIndices(List<int> bytes, int offset) {
  if (offset < 0 || offset + 16 > bytes.length) {
    return null;
  }

  final length = _readUint32Be(bytes, offset + 4);
  if (length < 16 || offset + length > bytes.length) {
    return null;
  }

  final numGroups = _readUint32Be(bytes, offset + 12);
  final groupsOffset = offset + 16;
  if (groupsOffset + (numGroups * 12) > offset + length) {
    return null;
  }

  final codepointToGlyphIndex = <int, int>{};
  for (var groupIndex = 0; groupIndex < numGroups; groupIndex++) {
    final groupOffset = groupsOffset + (groupIndex * 12);
    final startCode = _readUint32Be(bytes, groupOffset);
    final endCode = _readUint32Be(bytes, groupOffset + 4);
    final startGlyphId = _readUint32Be(bytes, groupOffset + 8);
    if (startCode > endCode) {
      continue;
    }

    for (var codepoint = startCode; codepoint <= endCode; codepoint++) {
      if (!_isValidUnicodeScalar(codepoint)) {
        continue;
      }

      final glyphIndex = startGlyphId + (codepoint - startCode);
      if (glyphIndex > 0) {
        codepointToGlyphIndex[codepoint] = glyphIndex;
      }
    }
  }

  return codepointToGlyphIndex.isEmpty ? null : codepointToGlyphIndex;
}

Map<int, int>? _buildTrueTypeCodepointAdvanceWidths(
  List<int> bytes,
  int sfntOffset, {
  required int glyphCount,
  required int numberOfHMetrics,
  required Map<int, int> codepointToGlyphIndex,
}) {
  if (glyphCount <= 0 ||
      numberOfHMetrics <= 0 ||
      codepointToGlyphIndex.isEmpty) {
    return null;
  }

  final hmtxOffset = _findSfntTableOffset(bytes, sfntOffset, 'hmtx');
  if (hmtxOffset == null ||
      hmtxOffset + (numberOfHMetrics * 4) > bytes.length) {
    return null;
  }

  final codepointAdvanceWidths = <int, int>{};
  for (final entry in codepointToGlyphIndex.entries) {
    final glyphIndex = entry.value;
    if (glyphIndex <= 0 || glyphIndex >= glyphCount) {
      continue;
    }

    final metricIndex = glyphIndex < numberOfHMetrics
        ? glyphIndex
        : numberOfHMetrics - 1;
    final metricOffset = hmtxOffset + (metricIndex * 4);
    if (metricOffset + 2 > bytes.length) {
      continue;
    }

    codepointAdvanceWidths[entry.key] = _readUint16Be(bytes, metricOffset);
  }

  return codepointAdvanceWidths.isEmpty ? null : codepointAdvanceWidths;
}

Map<int, int>? _buildTrueTypeCodepointKerning(
  List<int> bytes,
  int sfntOffset, {
  required Map<int, int> codepointToGlyphIndex,
}) {
  if (codepointToGlyphIndex.isEmpty) {
    return null;
  }

  final kernOffset = _findSfntTableOffset(bytes, sfntOffset, 'kern');
  if (kernOffset == null || kernOffset + 4 > bytes.length) {
    return null;
  }

  final codepointByGlyphIndex = <int, int>{};
  for (final entry in codepointToGlyphIndex.entries) {
    codepointByGlyphIndex.putIfAbsent(entry.value, () => entry.key);
  }

  final subtableCount = _readUint16Be(bytes, kernOffset + 2);
  var offset = kernOffset + 4;
  final kerning = <int, int>{};

  for (var subtableIndex = 0; subtableIndex < subtableCount; subtableIndex++) {
    if (offset + 6 > bytes.length) {
      break;
    }

    final subtableLength = _readUint16Be(bytes, offset + 2);
    final coverage = _readUint16Be(bytes, offset + 4);
    if (subtableLength < 6 || offset + subtableLength > bytes.length) {
      break;
    }

    final format = coverage >> 8;
    final horizontal = (coverage & 0x0001) != 0;
    final minimum = (coverage & 0x0002) != 0;
    final crossStream = (coverage & 0x0004) != 0;
    final override = (coverage & 0x0008) != 0;
    if (format == 0 && horizontal && !minimum && !crossStream) {
      _readTrueTypeFormat0KerningSubtable(
        bytes,
        offset,
        subtableLength: subtableLength,
        codepointByGlyphIndex: codepointByGlyphIndex,
        kerning: kerning,
        overridePairs: override,
      );
    }

    offset += subtableLength;
  }

  return kerning.isEmpty ? null : kerning;
}

Map<int, _LoveTrueTypeGlyphMetrics>? _buildTrueTypeCodepointGlyphMetrics(
  List<int> bytes,
  int sfntOffset, {
  required int glyphCount,
  required int numberOfHMetrics,
  required Map<int, int> codepointToGlyphIndex,
}) {
  if (glyphCount <= 0 ||
      numberOfHMetrics <= 0 ||
      codepointToGlyphIndex.isEmpty) {
    return null;
  }

  final headOffset = _findSfntTableOffset(bytes, sfntOffset, 'head');
  final locaOffset = _findSfntTableOffset(bytes, sfntOffset, 'loca');
  final glyfOffset = _findSfntTableOffset(bytes, sfntOffset, 'glyf');
  final hmtxOffset = _findSfntTableOffset(bytes, sfntOffset, 'hmtx');
  if (headOffset == null ||
      locaOffset == null ||
      glyfOffset == null ||
      hmtxOffset == null ||
      headOffset + 52 > bytes.length) {
    return null;
  }

  final indexToLocFormat = _readInt16Be(bytes, headOffset + 50);
  if (indexToLocFormat != 0 && indexToLocFormat != 1) {
    return null;
  }

  final codepointGlyphMetrics = <int, _LoveTrueTypeGlyphMetrics>{};
  for (final entry in codepointToGlyphIndex.entries) {
    final glyphIndex = entry.value;
    if (glyphIndex < 0 || glyphIndex >= glyphCount) {
      continue;
    }

    final horizontalMetric = _readTrueTypeHorizontalMetric(
      bytes,
      hmtxOffset,
      glyphIndex: glyphIndex,
      numberOfHMetrics: numberOfHMetrics,
    );
    final glyphOffsets = _readTrueTypeGlyphOffsets(
      bytes,
      locaOffset,
      glyphIndex: glyphIndex,
      glyphCount: glyphCount,
      indexToLocFormat: indexToLocFormat,
    );
    if (horizontalMetric == null || glyphOffsets == null) {
      continue;
    }

    final (glyphDataStart, glyphDataEnd) = glyphOffsets;
    if (glyphDataStart == glyphDataEnd) {
      codepointGlyphMetrics[entry.key] = _LoveTrueTypeGlyphMetrics.empty(
        advanceWidth: horizontalMetric.advanceWidth,
        leftSideBearing: horizontalMetric.leftSideBearing,
      );
      continue;
    }

    final glyphOffset = glyfOffset + glyphDataStart;
    final glyphLength = glyphDataEnd - glyphDataStart;
    if (glyphOffset < 0 ||
        glyphLength < 10 ||
        glyphOffset + glyphLength > bytes.length) {
      continue;
    }

    codepointGlyphMetrics[entry.key] = _LoveTrueTypeGlyphMetrics(
      advanceWidth: horizontalMetric.advanceWidth,
      leftSideBearing: horizontalMetric.leftSideBearing,
      xMin: _readInt16Be(bytes, glyphOffset + 2),
      yMin: _readInt16Be(bytes, glyphOffset + 4),
      xMax: _readInt16Be(bytes, glyphOffset + 6),
      yMax: _readInt16Be(bytes, glyphOffset + 8),
    );
  }

  return codepointGlyphMetrics.isEmpty ? null : codepointGlyphMetrics;
}

final class _LoveTrueTypeHorizontalMetric {
  const _LoveTrueTypeHorizontalMetric({
    required this.advanceWidth,
    required this.leftSideBearing,
  });

  final int advanceWidth;
  final int leftSideBearing;
}

_LoveTrueTypeHorizontalMetric? _readTrueTypeHorizontalMetric(
  List<int> bytes,
  int hmtxOffset, {
  required int glyphIndex,
  required int numberOfHMetrics,
}) {
  if (glyphIndex < 0 || numberOfHMetrics <= 0) {
    return null;
  }

  final metricIndex = glyphIndex < numberOfHMetrics
      ? glyphIndex
      : numberOfHMetrics - 1;
  final advanceOffset = hmtxOffset + (metricIndex * 4);
  final bearingOffset = glyphIndex < numberOfHMetrics
      ? advanceOffset + 2
      : hmtxOffset +
            (numberOfHMetrics * 4) +
            ((glyphIndex - numberOfHMetrics) * 2);
  if (advanceOffset + 4 > bytes.length || bearingOffset + 2 > bytes.length) {
    return null;
  }

  return _LoveTrueTypeHorizontalMetric(
    advanceWidth: _readUint16Be(bytes, advanceOffset),
    leftSideBearing: _readInt16Be(bytes, bearingOffset),
  );
}

(int, int)? _readTrueTypeGlyphOffsets(
  List<int> bytes,
  int locaOffset, {
  required int glyphIndex,
  required int glyphCount,
  required int indexToLocFormat,
}) {
  if (glyphIndex < 0 || glyphIndex >= glyphCount) {
    return null;
  }

  if (indexToLocFormat == 0) {
    final entryOffset = locaOffset + (glyphIndex * 2);
    if (entryOffset + 4 > bytes.length) {
      return null;
    }
    return (
      _readUint16Be(bytes, entryOffset) * 2,
      _readUint16Be(bytes, entryOffset + 2) * 2,
    );
  }

  final entryOffset = locaOffset + (glyphIndex * 4);
  if (entryOffset + 8 > bytes.length) {
    return null;
  }
  return (
    _readUint32Be(bytes, entryOffset),
    _readUint32Be(bytes, entryOffset + 4),
  );
}

final class _LoveTrueTypeGlyphTableContext {
  const _LoveTrueTypeGlyphTableContext({
    required this.bytes,
    required this.glyfOffset,
    required this.locaOffset,
    required this.glyphCount,
    required this.indexToLocFormat,
  });

  final List<int> bytes;
  final int glyfOffset;
  final int locaOffset;
  final int glyphCount;
  final int indexToLocFormat;
}

final class _LoveTrueTypeOutlinePoint {
  const _LoveTrueTypeOutlinePoint({
    required this.x,
    required this.y,
    required this.onCurve,
  });

  final double x;
  final double y;
  final bool onCurve;
}

final class _LoveTrueTypeRasterPoint {
  const _LoveTrueTypeRasterPoint({
    required this.x,
    required this.y,
    required this.onCurve,
  });

  final double x;
  final double y;
  final bool onCurve;
}

const int _loveTrueTypeArg1And2AreWordsFlag = 0x0001;
const int _loveTrueTypeArgsAreXyValuesFlag = 0x0002;
const int _loveTrueTypeWeHaveAScaleFlag = 0x0008;
const int _loveTrueTypeMoreComponentsFlag = 0x0020;
const int _loveTrueTypeWeHaveAnXAndYScaleFlag = 0x0040;
const int _loveTrueTypeWeHaveATwoByTwoFlag = 0x0080;
const int _loveTrueTypeWeHaveInstructionsFlag = 0x0100;
const int _loveTrueTypeScaledComponentOffsetFlag = 0x0800;
const int _loveTrueTypeMaxCompositeDepth = 16;

Uint8List? _rasterizeTrueTypeGlyphLa8(
  List<int>? bytes,
  LoveTrueTypeFontMetadata? metadata, {
  required int codepoint,
  required int pixelHeight,
  required String hinting,
}) {
  if (bytes == null ||
      bytes.isEmpty ||
      metadata == null ||
      pixelHeight <= 0 ||
      metadata.glyphCount == null ||
      metadata.glyphCount! <= 0) {
    return null;
  }

  final glyphIndex = metadata._codepointToGlyphIndex?[codepoint];
  final glyphMetrics = metadata._codepointGlyphMetrics?[codepoint];
  final scale = metadata._pixelScaleForHeight(pixelHeight);
  if (glyphIndex == null ||
      glyphMetrics == null ||
      !glyphMetrics.hasBounds ||
      scale == null) {
    return null;
  }

  final scaledMetrics = glyphMetrics.scale(scale);
  if (scaledMetrics.width <= 0 || scaledMetrics.height <= 0) {
    return Uint8List(0);
  }

  final outline = _readTrueTypeGlyphOutline(
    bytes,
    glyphIndex,
    glyphCount: metadata.glyphCount!,
  );
  if (outline == null || outline.isEmpty) {
    return null;
  }

  final xMin = glyphMetrics.xMin!.toDouble();
  final yMax = glyphMetrics.yMax!.toDouble();
  final contours = <List<_LoveTrueTypeRasterPoint>>[];
  for (final contour in outline) {
    if (contour.isEmpty) {
      continue;
    }

    contours.add(<_LoveTrueTypeRasterPoint>[
      for (final point in contour)
        _LoveTrueTypeRasterPoint(
          x: (point.x - xMin) * scale,
          y: (yMax - point.y) * scale,
          onCurve: point.onCurve,
        ),
    ]);
  }

  if (contours.isEmpty) {
    return null;
  }

  return _rasterizeTrueTypeContoursLa8(
    contours,
    width: scaledMetrics.width,
    height: scaledMetrics.height,
    monochrome: hinting == 'mono',
  );
}

List<List<_LoveTrueTypeOutlinePoint>>? _readTrueTypeGlyphOutline(
  List<int> bytes,
  int glyphIndex, {
  required int glyphCount,
}) {
  final sfntOffset = _trueTypeSfntOffset(bytes);
  if (sfntOffset == null) {
    return null;
  }

  final headOffset = _findSfntTableOffset(bytes, sfntOffset, 'head');
  final locaOffset = _findSfntTableOffset(bytes, sfntOffset, 'loca');
  final glyfOffset = _findSfntTableOffset(bytes, sfntOffset, 'glyf');
  if (headOffset == null ||
      locaOffset == null ||
      glyfOffset == null ||
      headOffset + 52 > bytes.length) {
    return null;
  }

  final indexToLocFormat = _readInt16Be(bytes, headOffset + 50);
  if (indexToLocFormat != 0 && indexToLocFormat != 1) {
    return null;
  }

  return _readTrueTypeGlyphOutlineFromContext(
    _LoveTrueTypeGlyphTableContext(
      bytes: bytes,
      glyfOffset: glyfOffset,
      locaOffset: locaOffset,
      glyphCount: glyphCount,
      indexToLocFormat: indexToLocFormat,
    ),
    glyphIndex,
    depth: 0,
  );
}

List<List<_LoveTrueTypeOutlinePoint>>? _readTrueTypeGlyphOutlineFromContext(
  _LoveTrueTypeGlyphTableContext context,
  int glyphIndex, {
  required int depth,
}) {
  if (depth > _loveTrueTypeMaxCompositeDepth) {
    return null;
  }

  final glyphOffsets = _readTrueTypeGlyphOffsets(
    context.bytes,
    context.locaOffset,
    glyphIndex: glyphIndex,
    glyphCount: context.glyphCount,
    indexToLocFormat: context.indexToLocFormat,
  );
  if (glyphOffsets == null) {
    return null;
  }

  final (glyphDataStart, glyphDataEnd) = glyphOffsets;
  if (glyphDataStart == glyphDataEnd) {
    return const <List<_LoveTrueTypeOutlinePoint>>[];
  }

  final glyphOffset = context.glyfOffset + glyphDataStart;
  final glyphLength = glyphDataEnd - glyphDataStart;
  if (glyphOffset < 0 ||
      glyphLength < 10 ||
      glyphOffset + glyphLength > context.bytes.length) {
    return null;
  }

  final numberOfContours = _readInt16Be(context.bytes, glyphOffset);
  if (numberOfContours == 0) {
    return const <List<_LoveTrueTypeOutlinePoint>>[];
  }
  if (numberOfContours > 0) {
    return _readTrueTypeSimpleGlyphContours(
      context.bytes,
      glyphOffset,
      glyphLength,
      numberOfContours,
    );
  }

  return _readTrueTypeCompositeGlyphContours(
    context,
    glyphOffset,
    glyphLength,
    depth: depth + 1,
  );
}

List<List<_LoveTrueTypeOutlinePoint>>? _readTrueTypeSimpleGlyphContours(
  List<int> bytes,
  int glyphOffset,
  int glyphLength,
  int numberOfContours,
) {
  if (numberOfContours <= 0) {
    return null;
  }

  final endPtsOffset = glyphOffset + 10;
  final endPtsLength = numberOfContours * 2;
  if (endPtsOffset + endPtsLength + 2 > glyphOffset + glyphLength) {
    return null;
  }

  final contourEndPoints = <int>[
    for (var contourIndex = 0; contourIndex < numberOfContours; contourIndex++)
      _readUint16Be(bytes, endPtsOffset + (contourIndex * 2)),
  ];
  if (contourEndPoints.isEmpty) {
    return null;
  }

  final pointCount = contourEndPoints.last + 1;
  if (pointCount <= 0) {
    return null;
  }

  final instructionLengthOffset = endPtsOffset + endPtsLength;
  final instructionLength = _readUint16Be(bytes, instructionLengthOffset);
  var offset = instructionLengthOffset + 2 + instructionLength;
  if (offset > glyphOffset + glyphLength) {
    return null;
  }

  final flags = <int>[];
  while (flags.length < pointCount) {
    if (offset >= glyphOffset + glyphLength) {
      return null;
    }

    final flag = bytes[offset++];
    flags.add(flag);
    if ((flag & 0x08) != 0) {
      if (offset >= glyphOffset + glyphLength) {
        return null;
      }
      final repeatCount = bytes[offset++];
      for (var repeatIndex = 0; repeatIndex < repeatCount; repeatIndex++) {
        flags.add(flag);
      }
    }
  }

  if (flags.length != pointCount) {
    return null;
  }

  final points = <_LoveTrueTypeOutlinePoint>[];
  var currentX = 0;
  for (final flag in flags) {
    if ((flag & 0x02) != 0) {
      if (offset >= glyphOffset + glyphLength) {
        return null;
      }
      final delta = bytes[offset++];
      currentX += (flag & 0x10) != 0 ? delta : -delta;
    } else if ((flag & 0x10) == 0) {
      if (offset + 2 > glyphOffset + glyphLength) {
        return null;
      }
      currentX += _readInt16Be(bytes, offset);
      offset += 2;
    }

    points.add(
      _LoveTrueTypeOutlinePoint(
        x: currentX.toDouble(),
        y: 0,
        onCurve: (flag & 0x01) != 0,
      ),
    );
  }

  var currentY = 0;
  for (var index = 0; index < flags.length; index++) {
    final flag = flags[index];
    if ((flag & 0x04) != 0) {
      if (offset >= glyphOffset + glyphLength) {
        return null;
      }
      final delta = bytes[offset++];
      currentY += (flag & 0x20) != 0 ? delta : -delta;
    } else if ((flag & 0x20) == 0) {
      if (offset + 2 > glyphOffset + glyphLength) {
        return null;
      }
      currentY += _readInt16Be(bytes, offset);
      offset += 2;
    }

    final point = points[index];
    points[index] = _LoveTrueTypeOutlinePoint(
      x: point.x,
      y: currentY.toDouble(),
      onCurve: point.onCurve,
    );
  }

  final contours = <List<_LoveTrueTypeOutlinePoint>>[];
  var startIndex = 0;
  for (final endIndex in contourEndPoints) {
    if (endIndex < startIndex || endIndex >= points.length) {
      return null;
    }

    contours.add(
      List<_LoveTrueTypeOutlinePoint>.unmodifiable(
        points.sublist(startIndex, endIndex + 1),
      ),
    );
    startIndex = endIndex + 1;
  }

  return contours;
}

List<List<_LoveTrueTypeOutlinePoint>>? _readTrueTypeCompositeGlyphContours(
  _LoveTrueTypeGlyphTableContext context,
  int glyphOffset,
  int glyphLength, {
  required int depth,
}) {
  final glyphEnd = glyphOffset + glyphLength;
  var offset = glyphOffset + 10;
  final contours = <List<_LoveTrueTypeOutlinePoint>>[];
  var flags = 0;

  while (true) {
    if (offset + 4 > glyphEnd) {
      return null;
    }

    flags = _readUint16Be(context.bytes, offset);
    final componentGlyphIndex = _readUint16Be(context.bytes, offset + 2);
    offset += 4;

    if (componentGlyphIndex < 0 || componentGlyphIndex >= context.glyphCount) {
      return null;
    }

    final argsAreWords = (flags & _loveTrueTypeArg1And2AreWordsFlag) != 0;
    final argsAreXyValues = (flags & _loveTrueTypeArgsAreXyValuesFlag) != 0;
    if (!argsAreXyValues) {
      return null;
    }

    late final int arg1;
    late final int arg2;
    if (argsAreWords) {
      if (offset + 4 > glyphEnd) {
        return null;
      }
      arg1 = _readInt16Be(context.bytes, offset);
      arg2 = _readInt16Be(context.bytes, offset + 2);
      offset += 4;
    } else {
      if (offset + 2 > glyphEnd) {
        return null;
      }
      arg1 = _readInt8(context.bytes, offset);
      arg2 = _readInt8(context.bytes, offset + 1);
      offset += 2;
    }

    var xx = 1.0;
    var xy = 0.0;
    var yx = 0.0;
    var yy = 1.0;
    if ((flags & _loveTrueTypeWeHaveAScaleFlag) != 0) {
      if (offset + 2 > glyphEnd) {
        return null;
      }
      xx = _readTrueTypeF2Dot14(context.bytes, offset);
      yy = xx;
      offset += 2;
    } else if ((flags & _loveTrueTypeWeHaveAnXAndYScaleFlag) != 0) {
      if (offset + 4 > glyphEnd) {
        return null;
      }
      xx = _readTrueTypeF2Dot14(context.bytes, offset);
      yy = _readTrueTypeF2Dot14(context.bytes, offset + 2);
      offset += 4;
    } else if ((flags & _loveTrueTypeWeHaveATwoByTwoFlag) != 0) {
      if (offset + 8 > glyphEnd) {
        return null;
      }
      xx = _readTrueTypeF2Dot14(context.bytes, offset);
      xy = _readTrueTypeF2Dot14(context.bytes, offset + 2);
      yx = _readTrueTypeF2Dot14(context.bytes, offset + 4);
      yy = _readTrueTypeF2Dot14(context.bytes, offset + 6);
      offset += 8;
    }

    final componentContours = _readTrueTypeGlyphOutlineFromContext(
      context,
      componentGlyphIndex,
      depth: depth,
    );
    if (componentContours == null) {
      return null;
    }

    final translateX = arg1.toDouble();
    final translateY = arg2.toDouble();
    final offsetX = (flags & _loveTrueTypeScaledComponentOffsetFlag) != 0
        ? (xx * translateX) + (xy * translateY)
        : translateX;
    final offsetY = (flags & _loveTrueTypeScaledComponentOffsetFlag) != 0
        ? (yx * translateX) + (yy * translateY)
        : translateY;
    contours.addAll(
      _transformTrueTypeContours(
        componentContours,
        xx: xx,
        xy: xy,
        yx: yx,
        yy: yy,
        dx: offsetX,
        dy: offsetY,
      ),
    );

    if ((flags & _loveTrueTypeMoreComponentsFlag) == 0) {
      break;
    }
  }

  if ((flags & _loveTrueTypeWeHaveInstructionsFlag) != 0) {
    if (offset + 2 > glyphEnd) {
      return null;
    }
    final instructionLength = _readUint16Be(context.bytes, offset);
    offset += 2 + instructionLength;
    if (offset > glyphEnd) {
      return null;
    }
  }

  return contours;
}

List<List<_LoveTrueTypeOutlinePoint>> _transformTrueTypeContours(
  List<List<_LoveTrueTypeOutlinePoint>> contours, {
  required double xx,
  required double xy,
  required double yx,
  required double yy,
  required double dx,
  required double dy,
}) {
  return <List<_LoveTrueTypeOutlinePoint>>[
    for (final contour in contours)
      List<_LoveTrueTypeOutlinePoint>.unmodifiable(<_LoveTrueTypeOutlinePoint>[
        for (final point in contour)
          _LoveTrueTypeOutlinePoint(
            x: (point.x * xx) + (point.y * xy) + dx,
            y: (point.x * yx) + (point.y * yy) + dy,
            onCurve: point.onCurve,
          ),
      ]),
  ];
}

Uint8List _rasterizeTrueTypeContoursLa8(
  List<List<_LoveTrueTypeRasterPoint>> contours, {
  required int width,
  required int height,
  bool monochrome = false,
}) {
  final bytes = Uint8List(width * height * 2);
  for (var index = 0; index < bytes.length; index += 2) {
    bytes[index] = 255;
  }

  if (width <= 0 || height <= 0 || contours.isEmpty) {
    return bytes;
  }

  final flattenedContours = <List<_LoveTrueTypeRasterPoint>>[];
  for (final contour in contours) {
    final flattened = _flattenTrueTypeContour(contour);
    if (flattened.length >= 2) {
      flattenedContours.add(flattened);
    }
  }

  if (flattenedContours.isEmpty) {
    return bytes;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var coveredSamples = 0;
      for (var sampleY = 0; sampleY < 4; sampleY++) {
        final py = y + ((sampleY + 0.5) / 4.0);
        for (var sampleX = 0; sampleX < 4; sampleX++) {
          final px = x + ((sampleX + 0.5) / 4.0);
          if (_trueTypeContoursContainPoint(flattenedContours, px, py)) {
            coveredSamples++;
          }
        }
      }

      if (coveredSamples == 0) {
        continue;
      }

      bytes[((y * width) + x) * 2 + 1] = monochrome
          ? (coveredSamples >= 8 ? 255 : 0)
          : ((coveredSamples * 255) / 16).round();
    }
  }

  return bytes;
}

List<_LoveTrueTypeRasterPoint> _flattenTrueTypeContour(
  List<_LoveTrueTypeRasterPoint> contour,
) {
  if (contour.isEmpty) {
    return const <_LoveTrueTypeRasterPoint>[];
  }

  final first = contour.first;
  final last = contour.last;
  final start = first.onCurve
      ? first
      : last.onCurve
      ? last
      : _midpointTrueTypeRasterPoint(last, first);
  final startIndex = first.onCurve ? 1 : 0;
  final flattened = <_LoveTrueTypeRasterPoint>[start];
  var previousOnCurve = start;

  for (var index = startIndex; index < contour.length + startIndex;) {
    final point = contour[index % contour.length];
    if (point.onCurve) {
      _appendTrueTypeRasterLine(flattened, point);
      previousOnCurve = point;
      index++;
      continue;
    }

    final next = contour[(index + 1) % contour.length];
    if (next.onCurve) {
      _appendTrueTypeRasterQuadratic(flattened, previousOnCurve, point, next);
      previousOnCurve = next;
      index += 2;
      continue;
    }

    final implied = _midpointTrueTypeRasterPoint(point, next);
    _appendTrueTypeRasterQuadratic(flattened, previousOnCurve, point, implied);
    previousOnCurve = implied;
    index++;
  }

  return flattened;
}

_LoveTrueTypeRasterPoint _midpointTrueTypeRasterPoint(
  _LoveTrueTypeRasterPoint left,
  _LoveTrueTypeRasterPoint right,
) {
  return _LoveTrueTypeRasterPoint(
    x: (left.x + right.x) / 2.0,
    y: (left.y + right.y) / 2.0,
    onCurve: true,
  );
}

void _appendTrueTypeRasterLine(
  List<_LoveTrueTypeRasterPoint> points,
  _LoveTrueTypeRasterPoint end,
) {
  if (_sameTrueTypeRasterPoint(points.last, end)) {
    return;
  }

  points.add(end);
}

void _appendTrueTypeRasterQuadratic(
  List<_LoveTrueTypeRasterPoint> points,
  _LoveTrueTypeRasterPoint start,
  _LoveTrueTypeRasterPoint control,
  _LoveTrueTypeRasterPoint end,
) {
  final steps = _trueTypeQuadraticSubdivisionSteps(start, control, end);
  for (var step = 1; step <= steps; step++) {
    final t = step / steps;
    final inverseT = 1.0 - t;
    final point = _LoveTrueTypeRasterPoint(
      x:
          (inverseT * inverseT * start.x) +
          (2 * inverseT * t * control.x) +
          (t * t * end.x),
      y:
          (inverseT * inverseT * start.y) +
          (2 * inverseT * t * control.y) +
          (t * t * end.y),
      onCurve: true,
    );
    if (!_sameTrueTypeRasterPoint(points.last, point)) {
      points.add(point);
    }
  }
}

int _trueTypeQuadraticSubdivisionSteps(
  _LoveTrueTypeRasterPoint start,
  _LoveTrueTypeRasterPoint control,
  _LoveTrueTypeRasterPoint end,
) {
  final approximateLength =
      _trueTypeRasterDistance(start, control) +
      _trueTypeRasterDistance(control, end);
  return math.max(4, approximateLength.ceil());
}

double _trueTypeRasterDistance(
  _LoveTrueTypeRasterPoint left,
  _LoveTrueTypeRasterPoint right,
) {
  final dx = right.x - left.x;
  final dy = right.y - left.y;
  return math.sqrt((dx * dx) + (dy * dy));
}

bool _sameTrueTypeRasterPoint(
  _LoveTrueTypeRasterPoint left,
  _LoveTrueTypeRasterPoint right,
) {
  const epsilon = 0.001;
  return (left.x - right.x).abs() < epsilon &&
      (left.y - right.y).abs() < epsilon;
}

bool _trueTypeContoursContainPoint(
  List<List<_LoveTrueTypeRasterPoint>> contours,
  double x,
  double y,
) {
  var winding = 0;
  for (final contour in contours) {
    for (var index = 0; index < contour.length; index++) {
      final start = contour[index];
      final end = contour[(index + 1) % contour.length];
      if (start.y <= y) {
        if (end.y > y && _trueTypeRasterIsLeft(start, end, x, y) > 0) {
          winding++;
        }
      } else if (end.y <= y && _trueTypeRasterIsLeft(start, end, x, y) < 0) {
        winding--;
      }
    }
  }

  return winding != 0;
}

double _trueTypeRasterIsLeft(
  _LoveTrueTypeRasterPoint start,
  _LoveTrueTypeRasterPoint end,
  double x,
  double y,
) {
  return ((end.x - start.x) * (y - start.y)) -
      ((x - start.x) * (end.y - start.y));
}

void _readTrueTypeFormat0KerningSubtable(
  List<int> bytes,
  int offset, {
  required int subtableLength,
  required Map<int, int> codepointByGlyphIndex,
  required Map<int, int> kerning,
  required bool overridePairs,
}) {
  if (offset + 14 > bytes.length || offset + subtableLength > bytes.length) {
    return;
  }

  final pairCount = _readUint16Be(bytes, offset + 6);
  final pairsOffset = offset + 14;
  if (pairsOffset + (pairCount * 6) > offset + subtableLength) {
    return;
  }

  for (var pairIndex = 0; pairIndex < pairCount; pairIndex++) {
    final pairOffset = pairsOffset + (pairIndex * 6);
    final leftGlyphIndex = _readUint16Be(bytes, pairOffset);
    final rightGlyphIndex = _readUint16Be(bytes, pairOffset + 2);
    final value = _readInt16Be(bytes, pairOffset + 4);
    if (value == 0) {
      continue;
    }

    final leftCodepoint = codepointByGlyphIndex[leftGlyphIndex];
    final rightCodepoint = codepointByGlyphIndex[rightGlyphIndex];
    if (leftCodepoint == null || rightCodepoint == null) {
      continue;
    }

    final packedPair = _packLoveGlyphPair(leftCodepoint, rightCodepoint);
    if (overridePairs || !kerning.containsKey(packedPair)) {
      kerning[packedPair] = value;
    }
  }
}

int _readInt16Be(List<int> bytes, int offset) {
  final value = _readUint16Be(bytes, offset);
  return value >= 0x8000 ? value - 0x10000 : value;
}

int _readInt8(List<int> bytes, int offset) {
  final value = bytes[offset];
  return value >= 0x80 ? value - 0x100 : value;
}

double _readTrueTypeF2Dot14(List<int> bytes, int offset) {
  return _readInt16Be(bytes, offset) / 16384.0;
}
