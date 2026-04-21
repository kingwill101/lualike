part of '../love_runtime.dart';

enum LoveMeshDrawMode { fan, strip, triangles, points }

enum LoveMeshUsage { dynamicUsage, staticUsage, stream }

class LoveMeshAttributeFormat {
  const LoveMeshAttributeFormat({
    required this.name,
    required this.dataType,
    required this.components,
  });

  final String name;

  /// One of: 'float', 'byte', 'unorm8', 'snorm8', 'unorm16', 'snorm16',
  /// 'int8', 'int16', 'uint8', 'uint16', 'int32', 'uint32', 'float16',
  /// 'float32'.
  final String dataType;

  /// Number of components (1–4).
  final int components;

  /// Whether this attribute is stored with byte precision.
  ///
  /// LOVE 11.x still exposes normalized color components in Lua even when the
  /// underlying vertex format stores `VertexColor` as bytes.
  bool get isByteColor => dataType == 'byte' || dataType == 'unorm8';
}

/// The default LOVE vertex format used when no explicit format is supplied.
const List<LoveMeshAttributeFormat> defaultVertexFormat =
    <LoveMeshAttributeFormat>[
      LoveMeshAttributeFormat(
        name: 'VertexPosition',
        dataType: 'float',
        components: 2,
      ),
      LoveMeshAttributeFormat(
        name: 'VertexTexCoord',
        dataType: 'float',
        components: 2,
      ),
      LoveMeshAttributeFormat(
        name: 'VertexColor',
        dataType: 'byte',
        components: 4,
      ),
    ];

class LoveMeshVertex {
  const LoveMeshVertex({
    required this.x,
    required this.y,
    this.u = 0,
    this.v = 0,
    this.color = LoveColor.white,
  });

  final double x;
  final double y;
  final double u;
  final double v;
  final LoveColor color;

  LoveMeshVertex copy() {
    return LoveMeshVertex(x: x, y: y, u: u, v: v, color: color);
  }
}

class LoveMesh {
  LoveMesh({
    required List<LoveMeshVertex> vertices,
    this.drawMode = LoveMeshDrawMode.fan,
    this.usage = LoveMeshUsage.dynamicUsage,
    List<LoveMeshAttributeFormat>? vertexFormat,
  }) : _vertices = vertices.map((vertex) => vertex.copy()).toList(),
       vertexFormat = vertexFormat != null
           ? List<LoveMeshAttributeFormat>.unmodifiable(vertexFormat)
           : List<LoveMeshAttributeFormat>.unmodifiable(defaultVertexFormat);

  final List<LoveMeshVertex> _vertices;

  /// The draw mode for this mesh. Mutable via Mesh:setDrawMode.
  LoveMeshDrawMode drawMode;

  final LoveMeshUsage usage;

  /// The vertex attribute format for this mesh. Defaults to
  /// [defaultVertexFormat] when not explicitly specified.
  final List<LoveMeshAttributeFormat> vertexFormat;

  // ---------------------------------------------------------------------------
  // Texture (either image or canvas)
  // ---------------------------------------------------------------------------

  LoveImage? _texture;
  LoveCanvas? _canvasTexture;

  Object? get textureObject => (_canvasTexture as Object?) ?? _texture;

  void setImageTexture(LoveImage? image) {
    _texture = image;
    _canvasTexture = null;
  }

  void setCanvasTexture(LoveCanvas? canvas) {
    _canvasTexture = canvas;
    _texture = null;
  }

  void clearTexture() {
    _texture = null;
    _canvasTexture = null;
  }

  // ---------------------------------------------------------------------------
  // Vertex map (stored as 1-indexed Lua indices)
  // ---------------------------------------------------------------------------

  List<int>? _vertexMap;

  List<int>? get vertexMap =>
      _vertexMap == null ? null : List<int>.unmodifiable(_vertexMap!);

  void setVertexMapData(List<int>? map) {
    _vertexMap = map == null ? null : List<int>.of(map);
  }

  // ---------------------------------------------------------------------------
  // Draw range (min/max are 1-indexed Lua indices)
  // ---------------------------------------------------------------------------

  int? _drawRangeMin;
  int? _drawRangeMax;

  ({int min, int max})? get drawRange =>
      _drawRangeMin == null ? null : (min: _drawRangeMin!, max: _drawRangeMax!);

  void setDrawRange(int? min, int? max) {
    _drawRangeMin = min;
    _drawRangeMax = max;
  }

  void clearDrawRange() {
    _drawRangeMin = null;
    _drawRangeMax = null;
  }

  // ---------------------------------------------------------------------------
  // Attribute enabled state (defaults to true for all attributes)
  // ---------------------------------------------------------------------------

  final Map<String, bool> _attributeEnabled = {};

  bool isAttributeEnabled(String name) => _attributeEnabled[name] ?? true;

  void setAttributeEnabled(String name, bool enabled) =>
      _attributeEnabled[name] = enabled;

  // ---------------------------------------------------------------------------
  // flush – no-op in the command-based runtime
  // ---------------------------------------------------------------------------

  void flush() {}

  // ---------------------------------------------------------------------------
  // Vertex access
  // ---------------------------------------------------------------------------

  List<LoveMeshVertex> get vertices =>
      List<LoveMeshVertex>.unmodifiable(_vertices);

  int get vertexCount => _vertices.length;

  /// Returns the effective vertex stream used for drawing after applying the
  /// optional vertex map and draw range.
  List<LoveMeshVertex> verticesForDraw() {
    final mapped = _vertexMap == null
        ? _vertices
        : _vertexMap!
              .where((index) => index >= 1 && index <= _vertices.length)
              .map((index) => _vertices[index - 1])
              .toList(growable: false);

    if (_drawRangeMin == null || mapped.isEmpty) {
      return List<LoveMeshVertex>.unmodifiable(
        mapped.map((vertex) => vertex.copy()),
      );
    }

    final start = (_drawRangeMin! - 1).clamp(0, mapped.length);
    final end = _drawRangeMax!.clamp(start, mapped.length);
    return List<LoveMeshVertex>.unmodifiable(
      mapped.sublist(start, end).map((vertex) => vertex.copy()),
    );
  }

  // ---------------------------------------------------------------------------
  // copy
  // ---------------------------------------------------------------------------

  LoveMesh copy() {
    final result = LoveMesh(
      vertices: _vertices,
      drawMode: drawMode,
      usage: usage,
      vertexFormat: vertexFormat,
    );
    result._texture = _texture;
    result._canvasTexture = _canvasTexture;
    result.setVertexMapData(_vertexMap);
    result.setDrawRange(_drawRangeMin, _drawRangeMax);
    for (final entry in _attributeEnabled.entries) {
      result._attributeEnabled[entry.key] = entry.value;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // setVertices
  // ---------------------------------------------------------------------------

  void setVertices(
    List<LoveMeshVertex> vertices, {
    int startVertex = 1,
    int? count,
  }) {
    if (startVertex < 1) {
      throw RangeError.range(startVertex, 1, null, 'startVertex');
    }

    final resolvedCount = count ?? vertices.length;
    if (resolvedCount <= 0) {
      throw ArgumentError.value(
        resolvedCount,
        'count',
        'Vertex count must be greater than 0.',
      );
    }
    if (_vertices.isNotEmpty && startVertex > _vertices.length) {
      throw RangeError.range(startVertex, 1, _vertices.length, 'startVertex');
    }
    if (vertices.length < resolvedCount) {
      throw ArgumentError.value(
        vertices.length,
        'vertices',
        'Not enough vertices were provided for the requested count.',
      );
    }

    final startIndex = startVertex - 1;
    final requiredLength = startIndex + resolvedCount;
    while (_vertices.length < requiredLength) {
      _vertices.add(const LoveMeshVertex(x: 0, y: 0));
    }

    for (var index = 0; index < resolvedCount; index++) {
      _vertices[startIndex + index] = vertices[index].copy();
    }
  }
}
