part of '../love_runtime.dart';

// ignore_for_file: unused_import

enum LoveSpriteBatchUsage { dynamicUsage, staticUsage, stream }

class LoveSpriteBatchSprite {
  LoveSpriteBatchSprite({
    required Matrix4 transform,
    LoveQuad? quad,
    this.color,
    this.layer = 0,
  }) : transform = Matrix4.copy(transform),
       quad = quad?.copy();

  final Matrix4 transform;
  final LoveQuad? quad;
  final LoveColor? color;
  final int layer;

  LoveSpriteBatchSprite copy() {
    return LoveSpriteBatchSprite(
      transform: transform,
      quad: quad,
      color: color,
      layer: layer,
    );
  }
}

class LoveSpriteBatch {
  LoveSpriteBatch({
    required LoveImage texture,
    int bufferSize = 1000,
    this.usage = LoveSpriteBatchUsage.dynamicUsage,
  }) : _texture = texture,
       _bufferSize = math.max(1, bufferSize),
       _sprites = <LoveSpriteBatchSprite>[];

  LoveSpriteBatch._copy({
    required LoveImage texture,
    required int bufferSize,
    required this.usage,
    required List<LoveSpriteBatchSprite> sprites,
    required LoveColor? color,
    required int drawRangeStart,
    required int drawRangeCount,
  }) : _texture = texture,
       _bufferSize = bufferSize,
       _sprites = sprites.map((sprite) => sprite.copy()).toList(growable: true),
       _color = color,
       _drawRangeStart = drawRangeStart,
       _drawRangeCount = drawRangeCount;

  LoveImage _texture;
  int _bufferSize;
  final LoveSpriteBatchUsage usage;
  final List<LoveSpriteBatchSprite> _sprites;
  final Map<String, LoveMesh> _attachedAttributes = <String, LoveMesh>{};
  LoveColor? _color;
  int _drawRangeStart = -1;
  int _drawRangeCount = -1;

  LoveImage get texture => _texture;

  int get bufferSize => _bufferSize;

  int get count => _sprites.length;

  LoveColor? get color => _color;

  ({int start, int count})? get drawRange {
    if (_drawRangeStart < 0 || _drawRangeCount <= 0) {
      return null;
    }

    return (start: _drawRangeStart, count: _drawRangeCount);
  }

  List<LoveSpriteBatchSprite> get sprites =>
      List<LoveSpriteBatchSprite>.unmodifiable(_sprites);

  void clear() {
    _sprites.clear();
  }

  void flush() {}

  void setTexture(LoveImage texture) {
    _texture = texture;
  }

  void setColor([LoveColor? color]) {
    _color = color?.clamped();
  }

  int add(Matrix4 transform, {LoveQuad? quad, int layer = 0}) {
    _ensureCapacityForAdd();
    _sprites.add(
      LoveSpriteBatchSprite(
        transform: transform,
        quad: quad,
        color: _color,
        layer: layer,
      ),
    );
    return _sprites.length - 1;
  }

  /// Adds a sprite that draws a specific [layer] of an array/volume texture.
  /// Returns the 0-based internal index of the new sprite.
  int addLayer(int layer, Matrix4 transform, {LoveQuad? quad}) {
    return add(transform, quad: quad, layer: layer);
  }

  void set(int index, Matrix4 transform, {LoveQuad? quad, int? layer}) {
    if (index < 0 || index >= _sprites.length) {
      throw RangeError.range(index + 1, 1, _sprites.length, 'spriteindex');
    }

    _sprites[index] = LoveSpriteBatchSprite(
      transform: transform,
      quad: quad,
      color: _color,
      layer: layer ?? _sprites[index].layer,
    );
  }

  /// Updates the sprite at [index] to draw [layer] of an array/volume texture.
  void setLayer(int index, int layer, Matrix4 transform, {LoveQuad? quad}) {
    set(index, transform, quad: quad, layer: layer);
  }

  /// Attaches a custom vertex attribute [mesh] under [name] for use in shaders.
  /// The mesh data is stored but not currently used during rendering.
  void attachAttribute(String name, LoveMesh mesh) {
    _attachedAttributes[name] = mesh;
  }

  /// Returns a copy of the currently attached vertex attribute meshes.
  Map<String, LoveMesh> get attachedAttributes =>
      Map<String, LoveMesh>.unmodifiable(_attachedAttributes);

  void setDrawRange([int? start, int? count]) {
    if (start == null || count == null) {
      _drawRangeStart = -1;
      _drawRangeCount = -1;
      return;
    }

    if (start < 0 || count <= 0) {
      throw ArgumentError('Invalid draw range.');
    }

    _drawRangeStart = start;
    _drawRangeCount = count;
  }

  List<LoveSpriteBatchSprite> spritesToDraw() {
    final range = drawRange;
    if (range == null) {
      return sprites;
    }

    if (range.start >= _sprites.length) {
      return const <LoveSpriteBatchSprite>[];
    }

    final end = math.min(_sprites.length, range.start + range.count);
    return List<LoveSpriteBatchSprite>.unmodifiable(
      _sprites.sublist(range.start, end),
    );
  }

  LoveSpriteBatch copyForDraw() {
    // Snapshot Canvas textures at draw time so later render-to-canvas commands
    // don't retroactively change already queued SpriteBatch draws.
    final texture = switch (_texture) {
      final LoveCanvas canvas => canvas.snapshot(),
      final LoveImage image => image,
    };
    return LoveSpriteBatch._copy(
      texture: texture,
      bufferSize: _bufferSize,
      usage: usage,
      sprites: _sprites,
      color: _color,
      drawRangeStart: _drawRangeStart,
      drawRangeCount: _drawRangeCount,
    );
  }

  void _ensureCapacityForAdd() {
    if (_sprites.length < _bufferSize) {
      return;
    }

    _bufferSize = math.max(1, _bufferSize * 2);
  }
}
