part of '../love_runtime.dart';

// ignore_for_file: unused_import

/// The update pattern hint supplied when constructing a sprite batch.
enum LoveSpriteBatchUsage { dynamicUsage, staticUsage, stream }

/// A single sprite entry stored inside a [LoveSpriteBatch].
class LoveSpriteBatchSprite {
  /// Creates a sprite batch entry from [transform] and optional draw state.
  LoveSpriteBatchSprite({
    required Matrix4 transform,
    LoveQuad? quad,
    this.color,
    this.layer = 0,
  }) : transform = Matrix4.copy(transform),
       quad = quad?.copy();

  /// The transform applied when this sprite is drawn.
  final Matrix4 transform;

  /// The optional quad used to crop the batch texture for this sprite.
  final LoveQuad? quad;

  /// The color captured for this sprite at insertion time.
  final LoveColor? color;

  /// The texture layer selected for array and volume textures.
  final int layer;

  /// Returns a deep copy of this sprite batch entry.
  LoveSpriteBatchSprite copy() {
    return LoveSpriteBatchSprite(
      transform: transform,
      quad: quad,
      color: color,
      layer: layer,
    );
  }
}

/// Stores many textured sprites for repeated batch drawing.
class LoveSpriteBatch {
  /// Creates an empty sprite batch that draws from [texture].
  LoveSpriteBatch({
    required LoveImage texture,
    int bufferSize = 1000,
    this.usage = LoveSpriteBatchUsage.dynamicUsage,
  }) : _texture = texture,
       _bufferSize = math.max(1, bufferSize),
       _sprites = <LoveSpriteBatchSprite>[];

  /// Creates a drawable snapshot copy of an existing sprite batch.
  LoveSpriteBatch._copy({
    required LoveImage texture,
    required int bufferSize,
    required this.usage,
    required List<LoveSpriteBatchSprite> sprites,
    required Map<String, LoveMesh> attachedAttributes,
    required LoveColor? color,
    required int drawRangeStart,
    required int drawRangeCount,
  }) : _texture = texture,
       _bufferSize = bufferSize,
       _sprites = sprites.map((sprite) => sprite.copy()).toList(growable: true),
       _color = color,
       _drawRangeStart = drawRangeStart,
       _drawRangeCount = drawRangeCount {
    _attachedAttributes.addAll(
      attachedAttributes.map((name, mesh) => MapEntry(name, mesh.copy())),
    );
  }

  /// The source texture used by sprites in this batch.
  LoveImage _texture;

  /// The current storage capacity before the batch grows automatically.
  int _bufferSize;

  /// The usage hint supplied when this batch was created.
  final LoveSpriteBatchUsage usage;

  /// The sprites currently stored in insertion order.
  final List<LoveSpriteBatchSprite> _sprites;

  /// The custom vertex attribute meshes attached for shader access.
  final Map<String, LoveMesh> _attachedAttributes = <String, LoveMesh>{};

  /// The color applied to newly inserted or updated sprites.
  LoveColor? _color;

  /// The inclusive start of the optional draw range.
  int _drawRangeStart = -1;

  /// The number of sprites included in the optional draw range.
  int _drawRangeCount = -1;

  /// The texture currently used by this sprite batch.
  LoveImage get texture => _texture;

  /// The current sprite capacity before automatic growth.
  int get bufferSize => _bufferSize;

  /// The number of sprites stored in this batch.
  int get count => _sprites.length;

  /// The color captured by future `add` and `set` operations.
  LoveColor? get color => _color;

  /// The active draw range, or `null` when all sprites are drawn.
  ({int start, int count})? get drawRange {
    if (_drawRangeStart < 0 || _drawRangeCount <= 0) {
      return null;
    }

    return (start: _drawRangeStart, count: _drawRangeCount);
  }

  /// The sprites currently stored in this batch.
  List<LoveSpriteBatchSprite> get sprites =>
      List<LoveSpriteBatchSprite>.unmodifiable(_sprites);

  /// Removes every sprite from this batch.
  void clear() {
    _sprites.clear();
  }

  /// Flushes pending sprite updates.
  ///
  /// This software implementation applies updates immediately, so this is a
  /// no-op kept for LOVE API compatibility.
  void flush() {}

  /// Replaces the texture used by this sprite batch.
  void setTexture(LoveImage texture) {
    _texture = texture;
  }

  /// Sets the color captured by subsequent `add` and `set` calls.
  void setColor([LoveColor? color]) {
    _color = color?.clamped();
  }

  /// The texture layer that should be stored for a new sprite.
  int _resolvedLayer({LoveQuad? quad, int? explicitLayer}) {
    if (explicitLayer != null) {
      return explicitLayer;
    }

    if (_texture.textureType == 'array') {
      return quad?.layer ?? 0;
    }

    return 0;
  }

  /// Adds a sprite with [transform] and optional [quad] or [layer].
  ///
  /// Returns the zero-based index of the inserted sprite.
  int add(Matrix4 transform, {LoveQuad? quad, int? layer}) {
    _ensureCapacityForAdd();
    _sprites.add(
      LoveSpriteBatchSprite(
        transform: transform,
        quad: quad,
        color: _color,
        layer: _resolvedLayer(quad: quad, explicitLayer: layer),
      ),
    );
    return _sprites.length - 1;
  }

  /// Adds a sprite that draws a specific [layer] of an array/volume texture.
  /// Returns the 0-based internal index of the new sprite.
  int addLayer(int layer, Matrix4 transform, {LoveQuad? quad}) {
    return add(transform, quad: quad, layer: layer);
  }

  /// Replaces the sprite stored at [index].
  void set(int index, Matrix4 transform, {LoveQuad? quad, int? layer}) {
    if (index < 0 || index >= _sprites.length) {
      throw RangeError.range(index + 1, 1, _sprites.length, 'spriteindex');
    }

    _sprites[index] = LoveSpriteBatchSprite(
      transform: transform,
      quad: quad,
      color: _color,
      layer: _resolvedLayer(quad: quad, explicitLayer: layer),
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

  /// Restricts drawing to a contiguous sprite range.
  ///
  /// Passing `null` for either argument clears the draw range so every sprite
  /// is eligible for drawing.
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

  /// The sprites currently selected for drawing.
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

  /// Returns a draw-safe snapshot of this sprite batch.
  ///
  /// Canvas textures are snapshotted immediately so later render-to-canvas work
  /// does not affect already queued sprite batch draws.
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
      attachedAttributes: _attachedAttributes,
      color: _color,
      drawRangeStart: _drawRangeStart,
      drawRangeCount: _drawRangeCount,
    );
  }

  /// Grows the internal batch capacity when another sprite is about to be added.
  void _ensureCapacityForAdd() {
    if (_sprites.length < _bufferSize) {
      return;
    }

    _bufferSize = math.max(1, _bufferSize * 2);
  }
}
