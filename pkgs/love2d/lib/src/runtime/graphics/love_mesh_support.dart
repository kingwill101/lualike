part of '../love_runtime.dart';

/// Primitive layouts supported when drawing a [LoveMesh].
enum LoveMeshDrawMode {
  /// Connects vertices into a triangle fan.
  fan,

  /// Connects vertices into a strip of linked triangles.
  strip,

  /// Draws vertices as independent triangles.
  triangles,

  /// Draws vertices as points.
  points,
}

/// Usage hints for mesh vertex data.
enum LoveMeshUsage {
  /// Prefers data that changes frequently.
  dynamicUsage,

  /// Prefers data that stays mostly unchanged.
  staticUsage,

  /// Prefers data that is rewritten as a stream.
  stream,
}

/// Describes one attribute in a mesh vertex format.
class LoveMeshAttributeFormat {
  /// Creates a mesh attribute format descriptor.
  const LoveMeshAttributeFormat({
    required this.name,
    required this.dataType,
    required this.components,
  });

  /// The LOVE attribute name, such as `VertexPosition`.
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

/// One vertex in LOVE's default mesh format.
class LoveMeshVertex {
  /// Creates a mesh vertex with position, texture coordinates, and color.
  const LoveMeshVertex({
    required this.x,
    required this.y,
    this.u = 0,
    this.v = 0,
    this.color = LoveColor.white,
  });

  /// The horizontal position component.
  final double x;

  /// The vertical position component.
  final double y;

  /// The horizontal texture coordinate.
  final double u;

  /// The vertical texture coordinate.
  final double v;

  /// The per-vertex color multiplier.
  final LoveColor color;

  /// Returns a copy of this vertex.
  LoveMeshVertex copy() {
    return LoveMeshVertex(x: x, y: y, u: u, v: v, color: color);
  }
}

/// A mutable mesh object that stores vertices and draw state.
class LoveMesh {
  /// Creates a mesh from [vertices] and optional draw settings.
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

  /// The usage hint assigned when this mesh was created.
  final LoveMeshUsage usage;

  /// The vertex attribute format for this mesh. Defaults to
  /// [defaultVertexFormat] when not explicitly specified.
  final List<LoveMeshAttributeFormat> vertexFormat;

  // ---------------------------------------------------------------------------
  // Texture (either image or canvas)
  // ---------------------------------------------------------------------------

  LoveImage? _texture;
  LoveCanvas? _canvasTexture;

  /// The currently assigned texture object, if any.
  ///
  /// Canvas textures take precedence over image textures when both storage
  /// slots have been populated internally.
  Object? get textureObject => (_canvasTexture as Object?) ?? _texture;

  /// Assigns [image] as the mesh texture.
  void setImageTexture(LoveImage? image) {
    _texture = image;
    _canvasTexture = null;
  }

  /// Assigns [canvas] as the mesh texture.
  void setCanvasTexture(LoveCanvas? canvas) {
    _canvasTexture = canvas;
    _texture = null;
  }

  /// Removes any assigned texture object from this mesh.
  void clearTexture() {
    _texture = null;
    _canvasTexture = null;
  }

  // ---------------------------------------------------------------------------
  // Vertex map (stored as 1-indexed Lua indices)
  // ---------------------------------------------------------------------------

  List<int>? _vertexMap;

  /// The optional 1-indexed vertex map applied when drawing.
  List<int>? get vertexMap =>
      _vertexMap == null ? null : List<int>.unmodifiable(_vertexMap!);

  /// Replaces the optional vertex map with [map].
  void setVertexMapData(List<int>? map) {
    _vertexMap = map == null ? null : List<int>.of(map);
  }

  // ---------------------------------------------------------------------------
  // Draw range (min/max are 1-indexed Lua indices)
  // ---------------------------------------------------------------------------

  int? _drawRangeMin;
  int? _drawRangeMax;

  /// The optional 1-indexed draw range applied after vertex mapping.
  ({int min, int max})? get drawRange =>
      _drawRangeMin == null ? null : (min: _drawRangeMin!, max: _drawRangeMax!);

  /// Sets the active 1-indexed draw range to `[min, max]`.
  void setDrawRange(int? min, int? max) {
    _drawRangeMin = min;
    _drawRangeMax = max;
  }

  /// Clears any active draw range restriction.
  void clearDrawRange() {
    _drawRangeMin = null;
    _drawRangeMax = null;
  }

  // ---------------------------------------------------------------------------
  // Attribute enabled state (defaults to true for all attributes)
  // ---------------------------------------------------------------------------

  final Map<String, bool> _attributeEnabled = {};

  /// Returns whether the attribute named [name] is enabled for drawing.
  bool isAttributeEnabled(String name) => _attributeEnabled[name] ?? true;

  /// Sets whether the attribute named [name] is enabled for drawing.
  void setAttributeEnabled(String name, bool enabled) =>
      _attributeEnabled[name] = enabled;

  // ---------------------------------------------------------------------------
  // flush – no-op in the command-based runtime
  // ---------------------------------------------------------------------------

  /// Flushes pending mesh data updates.
  ///
  /// This is a no-op in the command-based runtime.
  void flush() {}

  // ---------------------------------------------------------------------------
  // Vertex access
  // ---------------------------------------------------------------------------

  List<LoveMeshVertex> get vertices =>
      List<LoveMeshVertex>.unmodifiable(_vertices);

  /// The number of stored vertices.
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

  /// Returns a copy of this mesh and its mutable draw state.
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

  /// Returns a draw-ready copy of this mesh.
  ///
  /// Canvas textures are snapshotted into images so the result can be rendered
  /// without retaining a live canvas dependency.
  LoveMesh copyForDraw() {
    final result = copy();
    if (result._canvasTexture case final LoveCanvas canvas?) {
      result._texture = canvas.snapshot();
      result._canvasTexture = null;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // setVertices
  // ---------------------------------------------------------------------------

  /// Replaces a range of vertices starting at [startVertex].
  ///
  /// When [count] is omitted, every vertex in [vertices] is written. The mesh
  /// grows as needed to fit the requested range.
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
