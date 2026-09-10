import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:love2d/love2d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'gpu_api_compat.dart';
import 'gpu_draw_state.dart';
import 'gpu_host_buffer_pool.dart';
import 'gpu_pipeline_cache.dart';
import 'gpu_texture_cache.dart';
import 'gpu_texture_samplers.dart';

const int _textGeometryCacheCapacity = 256;
const bool _formattedAtlasTextEnabled = bool.fromEnvironment(
  'LOVE2D_GPU_FORMATTED_ATLAS_TEXT',
  defaultValue: true,
);
const List<int> _triangleOrder = <int>[0, 1, 2, 1, 3, 2];
const List<({double x, double y})> _quadCorners = <({double x, double y})>[
  (x: 0, y: 0),
  (x: 1, y: 0),
  (x: 0, y: 1),
  (x: 1, y: 1),
];

/// Whether [command] can use the direct atlas-backed GPU text path.
bool supportsGpuAtlasTextCommand(LoveDrawCommand command) {
  return switch (command) {
    LoveTextCommand(:final font, :final spans, :final limit, :final align) =>
      _supportsAtlasText(font, spans, wrapLimit: limit, align: align),
    LoveTextObjectCommand(:final textObject) => textObject.entries.every(
      (entry) => _supportsAtlasText(
        textObject.font,
        entry.spans,
        wrapLimit: entry.wrapLimit,
        align: entry.align,
      ),
    ),
    _ => false,
  };
}

/// Whether adjacent atlas text commands preserve texture and GPU draw state
/// when combined into one ordered vertex stream.
bool canBatchGpuAtlasTextCommands(LoveDrawCommand left, LoveDrawCommand right) {
  if (!supportsGpuAtlasTextCommand(left) ||
      !supportsGpuAtlasTextCommand(right)) {
    return false;
  }
  return identical(_atlasImageForCommand(left), _atlasImageForCommand(right)) &&
      left.blendMode == right.blendMode &&
      left.blendAlphaMode == right.blendAlphaMode &&
      left.colorMask == right.colorMask &&
      left.wireframe == right.wireframe &&
      left.scissor == right.scissor &&
      identical(left.shader, right.shader) &&
      left.stencilCompare == right.stencilCompare &&
      left.stencilValue == right.stencilValue &&
      left.stencilAction == right.stencilAction &&
      left.stencilWriteValue == right.stencilWriteValue;
}

LoveImage? _atlasImageForCommand(LoveDrawCommand command) {
  return switch (command) {
    LoveTextCommand(:final font) => font.glyphAtlas?.image,
    LoveTextObjectCommand(:final textObject) =>
      textObject.font.glyphAtlas?.image,
    _ => null,
  };
}

/// Renders atlas-backed LOVE text directly inside the GPU pass.
///
/// Left, center, and right formatted text share the same atlas metrics used by
/// [LoveFont]. Justified text, fallback-font, and missing-codepoint cases remain
/// on the existing Canvas fallback. Cached vertex payloads make steady-state
/// HUD text a texture bind plus one draw instead of per-frame glyph layout.
final class GpuTextHandler {
  GpuTextHandler({
    required GpuPipelineCache pipelineCache,
    required GpuTextureCache textureCache,
    required GpuHostBufferPool hostBufferPool,
  }) : _pipelineCache = pipelineCache,
       _textureCache = textureCache,
       _hostBufferPool = hostBufferPool;

  final GpuPipelineCache _pipelineCache;
  final GpuTextureCache _textureCache;
  final GpuHostBufferPool _hostBufferPool;
  final LinkedHashMap<_TextGeometryKey, Float32List> _geometryCache =
      LinkedHashMap<_TextGeometryKey, Float32List>();
  final List<Float32List> _batchParts = <Float32List>[];
  Float32List _batchScratch = Float32List(0);

  bool supportsCommand(LoveDrawCommand command) =>
      supportsGpuAtlasTextCommand(command);

  LoveImage? atlasImageFor(LoveDrawCommand command) {
    return _atlasImageForCommand(command);
  }

  /// Whether two adjacent commands can share one ordered atlas draw.
  bool canBatch(LoveDrawCommand left, LoveDrawCommand right) {
    return canBatchGpuAtlasTextCommands(left, right);
  }

  /// Renders the adjacent supported text commands in `[start, end)` as one
  /// ordered vertex stream. The caller must establish [canBatch] across the
  /// range so texture and draw state remain valid for every command.
  bool renderTextRange(
    gpu.RenderPass renderPass,
    List<LoveDrawCommand> commands,
    int start,
    int end,
    ui.Size viewportSize,
  ) {
    if (start < 0 || end > commands.length || start >= end) {
      throw RangeError.range(start, 0, commands.length, 'start');
    }
    final command = commands[start];
    final atlasImage = atlasImageFor(command);
    if (atlasImage == null) {
      return false;
    }
    final texture = _textureCache.getCachedLoveImage(atlasImage);
    if (texture == null) {
      return false;
    }

    final parts = _batchParts..clear();
    var floatCount = 0;
    for (var index = start; index < end; index++) {
      _appendCommandGeometry(commands[index], parts);
    }
    for (final part in parts) {
      floatCount += part.length;
    }
    if (floatCount == 0) {
      return true;
    }
    if (_batchScratch.length < floatCount) {
      var capacity = _batchScratch.isEmpty ? 256 : _batchScratch.length;
      while (capacity < floatCount) {
        capacity *= 2;
      }
      _batchScratch = Float32List(capacity);
    }
    var offset = 0;
    for (final part in parts) {
      _batchScratch.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    _bindAndDraw(
      renderPass,
      command: command,
      atlasImage: atlasImage,
      texture: texture,
      vertices: _batchScratch,
      floatCount: floatCount,
      viewportSize: viewportSize,
    );
    return true;
  }

  bool renderText(
    gpu.RenderPass renderPass,
    LoveTextCommand command,
    ui.Size viewportSize,
  ) {
    final transform = vm.Matrix4.copy(command.transform)
      ..multiply(command.textTransform);
    return _renderSpans(
      renderPass,
      command: command,
      font: command.font,
      spans: command.spans,
      baseColor: command.color,
      transform: transform,
      wrapLimit: command.limit,
      align: command.align,
      viewportSize: viewportSize,
    );
  }

  bool renderTextObject(
    gpu.RenderPass renderPass,
    LoveTextObjectCommand command,
    ui.Size viewportSize,
  ) {
    final baseTransform = vm.Matrix4.copy(command.transform)
      ..multiply(command.drawTransform);
    var rendered = false;
    for (final entry in command.textObject.entries) {
      if (entry.spans.isEmpty) {
        continue;
      }
      final transform = vm.Matrix4.copy(baseTransform)
        ..multiply(entry.transform);
      rendered =
          _renderSpans(
            renderPass,
            command: command,
            font: command.textObject.font,
            spans: entry.spans,
            baseColor: command.color,
            transform: transform,
            wrapLimit: entry.wrapLimit,
            align: entry.align,
            viewportSize: viewportSize,
          ) ||
          rendered;
    }
    return rendered || command.textObject.entries.isEmpty;
  }

  bool _renderSpans(
    gpu.RenderPass renderPass, {
    required LoveDrawCommand command,
    required LoveFont font,
    required List<LoveTextSpan> spans,
    required LoveColor baseColor,
    required vm.Matrix4 transform,
    required double? wrapLimit,
    required String align,
    required ui.Size viewportSize,
  }) {
    final atlasImage = font.glyphAtlas?.image;
    if (atlasImage == null) {
      return false;
    }
    final texture = _textureCache.getCachedLoveImage(atlasImage);
    if (texture == null) {
      return false;
    }
    final vertices = _verticesForSpans(
      font: font,
      spans: spans,
      baseColor: baseColor,
      transform: transform,
      wrapLimit: wrapLimit,
      align: align,
    );
    if (vertices == null) {
      return false;
    }
    if (vertices.isEmpty) {
      return true;
    }
    _bindAndDraw(
      renderPass,
      command: command,
      atlasImage: atlasImage,
      texture: texture,
      vertices: vertices,
      floatCount: vertices.length,
      viewportSize: viewportSize,
    );
    return true;
  }

  Float32List? _verticesForSpans({
    required LoveFont font,
    required List<LoveTextSpan> spans,
    required LoveColor baseColor,
    required vm.Matrix4 transform,
    required double? wrapLimit,
    required String align,
  }) {
    final atlas = font.glyphAtlas;
    if (atlas == null) {
      return null;
    }
    final segmentKeys = <_TextSegmentKey>[
      for (final span in spans)
        _TextSegmentKey(
          text: span.text,
          color: baseColor.modulate(span.color ?? LoveColor.white),
        ),
    ];
    final key = _TextGeometryKey(
      atlasIdentity: identityHashCode(atlas),
      baseline: font.baseline,
      height: font.height,
      lineHeight: font.lineHeight,
      dpiScale: font.dpiScale,
      glyphKerningsIdentity: identityHashCode(font.glyphKernings),
      transform: List<double>.unmodifiable(transform.storage),
      segments: List<_TextSegmentKey>.unmodifiable(segmentKeys),
      wrapLimit: _effectiveWrapLimit(wrapLimit),
      align: align,
    );
    var vertices = _geometryCache.remove(key);
    vertices ??= _buildVertices(
      atlas: atlas,
      font: font,
      segments: segmentKeys,
      transform: transform,
      wrapLimit: _effectiveWrapLimit(wrapLimit),
      align: align,
    );
    _geometryCache[key] = vertices;
    if (_geometryCache.length > _textGeometryCacheCapacity) {
      _geometryCache.remove(_geometryCache.keys.first);
    }
    return vertices;
  }

  void _bindAndDraw(
    gpu.RenderPass renderPass, {
    required LoveDrawCommand command,
    required LoveImage atlasImage,
    required gpu.Texture texture,
    required Float32List vertices,
    required int floatCount,
    required ui.Size viewportSize,
  }) {
    final pipeline = _pipelineCache.getSpriteBatchPipeline();
    renderPass.bindPipeline(pipeline);
    applyGpuDrawState(renderPass, command, viewportSize);
    final textureSlot = pipeline.fragmentShader.getUniformSlot(
      'texture_sampler',
    );
    renderPass.bindTexture(
      textureSlot,
      texture,
      sampler: gpuSamplerForLoveImage(atlasImage),
    );
    final vertInfo = _hostBufferPool.emplaceVertInfo(
      _screenSpaceMvp(viewportSize),
      vm.Vector4(1, 1, 1, 1),
      mipBias: 0,
    );
    renderPass.bindUniform(
      pipeline.vertexShader.getUniformSlot('VertInfo'),
      vertInfo,
    );
    bindVertexBufferCompat(
      renderPass,
      _hostBufferPool.emplaceFloat32List(vertices, length: floatCount),
    );
    drawVerticesCompat(renderPass, floatCount ~/ 8);
  }

  void _appendCommandGeometry(
    LoveDrawCommand command,
    List<Float32List> parts,
  ) {
    switch (command) {
      case LoveTextCommand cmd:
        final transform = vm.Matrix4.copy(cmd.transform)
          ..multiply(cmd.textTransform);
        final vertices = _verticesForSpans(
          font: cmd.font,
          spans: cmd.spans,
          baseColor: cmd.color,
          transform: transform,
          wrapLimit: cmd.limit,
          align: cmd.align,
        );
        if (vertices != null && vertices.isNotEmpty) {
          parts.add(vertices);
        }
      case LoveTextObjectCommand cmd:
        final baseTransform = vm.Matrix4.copy(cmd.transform)
          ..multiply(cmd.drawTransform);
        for (final entry in cmd.textObject.entries) {
          if (entry.spans.isEmpty) {
            continue;
          }
          final transform = vm.Matrix4.copy(baseTransform)
            ..multiply(entry.transform);
          final vertices = _verticesForSpans(
            font: cmd.textObject.font,
            spans: entry.spans,
            baseColor: cmd.color,
            transform: transform,
            wrapLimit: entry.wrapLimit,
            align: entry.align,
          );
          if (vertices != null && vertices.isNotEmpty) {
            parts.add(vertices);
          }
        }
      default:
        throw ArgumentError.value(command, 'command', 'must be atlas text');
    }
  }

  Float32List _buildVertices({
    required LoveFontGlyphAtlas atlas,
    required LoveFont font,
    required List<_TextSegmentKey> segments,
    required vm.Matrix4 transform,
    required double? wrapLimit,
    required String align,
  }) {
    final values = <double>[];
    final dpiScale = font.dpiScale <= 0 ? 1.0 : font.dpiScale;
    final glyphScale = 1 / dpiScale;
    final baseline = font.baseline.roundToDouble();
    final lineAdvance = font.height * font.lineHeight;
    final imageWidth = atlas.image.width.toDouble();
    final imageHeight = atlas.image.height.toDouble();
    final lines = _layoutStyledLines(
      font: font,
      segments: segments,
      wrapLimit: wrapLimit,
    );

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final lineY = lineIndex * lineAdvance;
      var penX = loveGpuAtlasLineOffset(
        align: align,
        wrapLimit: wrapLimit,
        lineWidth: line.width,
      );
      int? previous;
      for (final styledCodepoint in line.codepoints) {
        final codepoint = styledCodepoint.codepoint;
        final color = styledCodepoint.color;
        final glyph = atlas.glyphs[codepoint]!;
        if (previous != null) {
          penX += font.getKerning(previous, codepoint);
        }
        if (glyph.width > 0 && glyph.height > 0) {
          final quad = loveFontAtlasGlyphQuad(
            atlas: atlas,
            glyph: glyph,
            penX: penX,
            lineY: lineY,
            baseline: baseline,
            dpiScale: dpiScale,
          );
          final uvLeft = quad.sourceX / imageWidth;
          final uvTop = quad.sourceY / imageHeight;
          final uvWidth = quad.sourceWidth / imageWidth;
          final uvHeight = quad.sourceHeight / imageHeight;
          for (final index in _triangleOrder) {
            final corner = _quadCorners[index];
            final point = _transformPoint(
              transform,
              quad.left + (corner.x * quad.width),
              quad.top + (corner.y * quad.height),
            );
            values
              ..add(point.dx)
              ..add(point.dy)
              ..add(uvLeft + (corner.x * uvWidth))
              ..add(uvTop + (corner.y * uvHeight))
              ..add(color.r)
              ..add(color.g)
              ..add(color.b)
              ..add(color.a);
          }
        }
        penX += glyph.advance * glyphScale;
        previous = codepoint;
      }
    }
    return Float32List.fromList(values);
  }

  vm.Matrix4 _screenSpaceMvp(ui.Size viewportSize) {
    final width = viewportSize.width;
    final height = viewportSize.height;
    if (width <= 0 || height <= 0) {
      return vm.Matrix4.identity();
    }
    return vm.Matrix4(
      2 / width,
      0,
      0,
      0,
      0,
      -2 / height,
      0,
      0,
      0,
      0,
      1,
      0,
      -1,
      1,
      0,
      1,
    );
  }

  ui.Offset _transformPoint(vm.Matrix4 matrix, double x, double y) {
    final storage = matrix.storage;
    return ui.Offset(
      (storage[0] * x) + (storage[4] * y) + storage[12],
      (storage[1] * x) + (storage[5] * y) + storage[13],
    );
  }
}

bool _supportsAtlasText(
  LoveFont font,
  List<LoveTextSpan> spans, {
  required double? wrapLimit,
  required String align,
}) {
  final atlas = font.glyphAtlas;
  if (atlas == null ||
      !_supportedAtlasAlignment(align) ||
      (!_formattedAtlasTextEnabled &&
          (_effectiveWrapLimit(wrapLimit) != null || align != 'left')) ||
      font.fallbacks.isNotEmpty) {
    return false;
  }
  for (final span in spans) {
    for (final codepoint in span.text.runes) {
      if (codepoint != 0x0a &&
          codepoint != 0x0d &&
          !atlas.glyphs.containsKey(codepoint)) {
        return false;
      }
    }
  }
  return true;
}

bool _supportedAtlasAlignment(String align) =>
    align == 'left' || align == 'center' || align == 'right';

double? _effectiveWrapLimit(double? wrapLimit) =>
    wrapLimit != null && wrapLimit > 0 ? wrapLimit : null;

/// Returns LOVE's horizontal offset for one formatted atlas-text row.
///
/// Public within `src` so the native half-pixel tie break can be regression
/// tested without constructing a Flutter GPU render pass.
double loveGpuAtlasLineOffset({
  required String align,
  required double? wrapLimit,
  required double lineWidth,
}) {
  if (wrapLimit == null) {
    return 0;
  }
  return switch (align) {
    // Native LOVE places centered rows on an integral pixel when the spare
    // width is odd, rather than filtering the glyph atlas at a half pixel.
    'center' => ((wrapLimit - lineWidth) / 2).floorToDouble(),
    'right' => wrapLimit - lineWidth,
    _ => 0,
  };
}

List<_StyledTextLine> _layoutStyledLines({
  required LoveFont font,
  required List<_TextSegmentKey> segments,
  required double? wrapLimit,
}) {
  final codepoints = <_StyledCodepoint>[
    for (final segment in segments)
      for (final codepoint in segment.text.runes)
        _StyledCodepoint(codepoint: codepoint, color: segment.color),
  ];
  final lines = <_StyledTextLine>[];
  final lineCodepoints = <_StyledCodepoint>[];
  var width = 0.0;
  var widthBeforeLastSpace = 0.0;
  var widthOfTrailingSpace = 0.0;
  int? previous;
  var lastSpaceIndex = -1;

  void finishLine(double lineWidth) {
    lines.add(
      _StyledTextLine(
        codepoints: List<_StyledCodepoint>.unmodifiable(lineCodepoints),
        width: lineWidth,
      ),
    );
    width = 0;
    widthBeforeLastSpace = 0;
    widthOfTrailingSpace = 0;
    previous = null;
    lastSpaceIndex = -1;
    lineCodepoints.clear();
  }

  var index = 0;
  while (index < codepoints.length) {
    final styledCodepoint = codepoints[index];
    final codepoint = styledCodepoint.codepoint;
    if (codepoint == 0x0a) {
      finishLine(width - widthOfTrailingSpace);
      index++;
      continue;
    }
    if (codepoint == 0x0d) {
      index++;
      continue;
    }

    final charWidth =
        font.measureWidth(String.fromCharCode(codepoint)) +
        (previous == null ? 0 : font.getKerning(previous, codepoint));
    final newWidth = width + charWidth;
    if (wrapLimit != null && codepoint != 0x20 && newWidth > wrapLimit) {
      if (lineCodepoints.isEmpty) {
        index++;
      } else if (lastSpaceIndex != -1) {
        while (lineCodepoints.isNotEmpty &&
            lineCodepoints.last.codepoint != 0x20) {
          lineCodepoints.removeLast();
        }
        width = widthBeforeLastSpace;
        index = lastSpaceIndex + 1;
      }
      finishLine(width);
      continue;
    }

    if (previous != 0x20 && codepoint == 0x20) {
      widthBeforeLastSpace = width;
    }
    width = newWidth;
    previous = codepoint;
    lineCodepoints.add(styledCodepoint);
    if (codepoint == 0x20) {
      lastSpaceIndex = index;
      widthOfTrailingSpace += charWidth;
    } else {
      widthOfTrailingSpace = 0;
    }
    index++;
  }
  finishLine(width - widthOfTrailingSpace);
  return lines;
}

final class _StyledCodepoint {
  const _StyledCodepoint({required this.codepoint, required this.color});

  final int codepoint;
  final LoveColor color;
}

final class _StyledTextLine {
  const _StyledTextLine({required this.codepoints, required this.width});

  final List<_StyledCodepoint> codepoints;
  final double width;
}

final class _TextSegmentKey {
  const _TextSegmentKey({required this.text, required this.color});

  final String text;
  final LoveColor color;

  @override
  bool operator ==(Object other) =>
      other is _TextSegmentKey && other.text == text && other.color == color;

  @override
  int get hashCode => Object.hash(text, color);
}

final class _TextGeometryKey {
  const _TextGeometryKey({
    required this.atlasIdentity,
    required this.baseline,
    required this.height,
    required this.lineHeight,
    required this.dpiScale,
    required this.glyphKerningsIdentity,
    required this.transform,
    required this.segments,
    required this.wrapLimit,
    required this.align,
  });

  final int atlasIdentity;
  final double baseline;
  final double height;
  final double lineHeight;
  final double dpiScale;
  final int glyphKerningsIdentity;
  final List<double> transform;
  final List<_TextSegmentKey> segments;
  final double? wrapLimit;
  final String align;

  @override
  bool operator ==(Object other) {
    return other is _TextGeometryKey &&
        other.atlasIdentity == atlasIdentity &&
        other.baseline == baseline &&
        other.height == height &&
        other.lineHeight == lineHeight &&
        other.dpiScale == dpiScale &&
        other.glyphKerningsIdentity == glyphKerningsIdentity &&
        other.wrapLimit == wrapLimit &&
        other.align == align &&
        _listEquals(other.transform, transform) &&
        _listEquals(other.segments, segments);
  }

  @override
  int get hashCode => Object.hash(
    atlasIdentity,
    baseline,
    height,
    lineHeight,
    dpiScale,
    glyphKerningsIdentity,
    wrapLimit,
    align,
    Object.hashAll(transform),
    Object.hashAll(segments),
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
