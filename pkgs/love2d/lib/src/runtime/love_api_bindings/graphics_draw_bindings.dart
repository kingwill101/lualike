part of '../love_api_bindings.dart';

/// Queues a mesh draw command using the current graphics state snapshot.
///
/// Zero-vertex meshes and non-positive instance counts are ignored so the
/// runtime matches LOVE's effectively no-op behavior for empty draws.
void _queueMeshDrawCommand(
  LoveRuntimeContext runtime, {
  required LoveMesh mesh,
  required List<Object?> args,
  required int transformIndex,
  required String symbol,
  int instanceCount = 1,
}) {
  if (mesh.vertexCount <= 0 || instanceCount <= 0) {
    return;
  }

  runtime.graphics.addCommand(
    LoveMeshCommand(
      color: runtime.graphics.color,
      lineWidth: runtime.graphics.lineWidth,
      lineStyle: runtime.graphics.lineStyle,
      lineJoin: runtime.graphics.lineJoin,
      blendMode: runtime.graphics.blendMode,
      blendAlphaMode: runtime.graphics.blendAlphaMode,
      colorMask: runtime.graphics.colorMask,
      wireframe: runtime.graphics.wireframe,
      scissor: runtime.graphics.scissor,
      shader: runtime.graphics.shader,
      transform: runtime.graphics.copyTransform(),
      drawTransform: _matrixFromTransformArgumentOrStandardTransform(
        args,
        transformIndex,
        symbol,
      ),
      mesh: mesh,
      instanceCount: instanceCount,
      pointSize: runtime.graphics.pointSize,
      frontFaceWinding: runtime.graphics.frontFaceWinding,
      cullMode: runtime.graphics.meshCullMode,
    ),
  );
}

/// Binds `love.graphics.rectangle`.
///
/// This records a rectangle draw command with LOVE's optional rounded-corner
/// radius arguments.
LoveApiImplementation _bindGraphicsRectangle(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final mode = _requireDrawMode(args, 0, 'love.graphics.rectangle');
    final x = _requireNumber(args, 1, 'love.graphics.rectangle');
    final y = _requireNumber(args, 2, 'love.graphics.rectangle');
    final width = _requireNumber(args, 3, 'love.graphics.rectangle');
    final height = _requireNumber(args, 4, 'love.graphics.rectangle');
    final radiusX = args.length >= 6
        ? _requireNumber(args, 5, 'love.graphics.rectangle')
        : 0.0;
    final radiusY = args.length >= 7
        ? _requireNumber(args, 6, 'love.graphics.rectangle')
        : radiusX;

    runtime.graphics.addCommand(
      LoveRectangleCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        mode: mode,
        x: x,
        y: y,
        width: width,
        height: height,
        cornerRadiusX: radiusX,
        cornerRadiusY: radiusY,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.circle`.
///
/// This records a circle draw command using the current graphics state.
LoveApiImplementation _bindGraphicsCircle(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final mode = _requireDrawMode(args, 0, 'love.graphics.circle');
    final x = _requireNumber(args, 1, 'love.graphics.circle');
    final y = _requireNumber(args, 2, 'love.graphics.circle');
    final radius = _requireNumber(args, 3, 'love.graphics.circle');

    runtime.graphics.addCommand(
      LoveCircleCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        mode: mode,
        x: x,
        y: y,
        radius: radius,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.line`.
///
/// LOVE accepts either flat coordinate lists or point tables, both of which
/// are normalized through [_coordinateSequence].
LoveApiImplementation _bindGraphicsLine(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final coordinates = _coordinateSequence(args, 'love.graphics.line');
    if (coordinates.length < 2) {
      throw LuaError('love.graphics.line needs at least two vertices');
    }

    runtime.graphics.addCommand(
      LoveLineCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        points: coordinates,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.polygon`.
///
/// The first argument selects fill or line mode and the remaining arguments are
/// parsed as a polygon vertex sequence.
LoveApiImplementation _bindGraphicsPolygon(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final mode = _requireDrawMode(args, 0, 'love.graphics.polygon');
    final coordinates = _coordinateSequence(
      args.skip(1).toList(growable: false),
      'love.graphics.polygon',
    );
    if (coordinates.length < 3) {
      throw LuaError('love.graphics.polygon needs at least three vertices');
    }

    runtime.graphics.addCommand(
      LovePolygonCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        mode: mode,
        points: coordinates,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.points`.
///
/// This preserves LOVE's mixed point-input forms, including per-point color
/// data when the source arguments encode it.
LoveApiImplementation _bindGraphicsPoints(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final points = _pointSequence(
      args,
      'love.graphics.points',
      currentColor: runtime.graphics.color,
    );
    runtime.graphics.addCommand(
      LovePointsCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        pointSize: runtime.graphics.pointSize,
        points: points,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.ellipse`.
///
/// LOVE accepts a second radius override, otherwise this uses the x radius for
/// both axes.
LoveApiImplementation _bindGraphicsEllipse(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final mode = _requireDrawMode(args, 0, 'love.graphics.ellipse');
    final x = _requireNumber(args, 1, 'love.graphics.ellipse');
    final y = _requireNumber(args, 2, 'love.graphics.ellipse');
    final radiusX = _requireNumber(args, 3, 'love.graphics.ellipse');
    final radiusY = args.length >= 5
        ? _requireNumber(args, 4, 'love.graphics.ellipse')
        : radiusX;

    runtime.graphics.addCommand(
      LoveEllipseCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        mode: mode,
        x: x,
        y: y,
        radiusX: radiusX,
        radiusY: radiusY,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.arc`.
///
/// This supports the optional arc-mode argument before the standard geometry
/// parameters.
LoveApiImplementation _bindGraphicsArc(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final drawMode = _requireDrawMode(args, 0, 'love.graphics.arc');
    var startIndex = 1;
    var arcMode = LoveGraphicsArcMode.pie;

    if (_stringLike(_valueAt(args, 1)) case final String modeString) {
      arcMode = _requireArcMode(modeString, 'love.graphics.arc');
      startIndex = 2;
    }

    final x = _requireNumber(args, startIndex + 0, 'love.graphics.arc');
    final y = _requireNumber(args, startIndex + 1, 'love.graphics.arc');
    final radius = _requireNumber(args, startIndex + 2, 'love.graphics.arc');
    final angle1 = _requireNumber(args, startIndex + 3, 'love.graphics.arc');
    final angle2 = _requireNumber(args, startIndex + 4, 'love.graphics.arc');

    runtime.graphics.addCommand(
      LoveArcCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        drawMode: drawMode,
        arcMode: arcMode,
        x: x,
        y: y,
        radius: radius,
        angle1: angle1,
        angle2: angle2,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.draw`.
///
/// This is the central drawable dispatcher for images, canvases, meshes,
/// sprite batches, particle systems, and text drawables. Unsupported drawable
/// combinations surface LOVE-style argument errors before any command is
/// queued.
LoveApiImplementation _bindGraphicsDraw(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (_textDrawableIfPresent(_valueAt(args, 0))
        case final LoveTextDrawable text) {
      if (_quadIfPresent(_valueAt(args, 1)) != null) {
        throw LuaError(
          'love.graphics.draw does not accept Quad arguments when drawing Text',
        );
      }

      runtime.graphics.addCommand(
        LoveTextObjectCommand(
          color: runtime.graphics.color,
          lineWidth: runtime.graphics.lineWidth,
          lineStyle: runtime.graphics.lineStyle,
          lineJoin: runtime.graphics.lineJoin,
          blendMode: runtime.graphics.blendMode,
          blendAlphaMode: runtime.graphics.blendAlphaMode,
          colorMask: runtime.graphics.colorMask,
          wireframe: runtime.graphics.wireframe,
          scissor: runtime.graphics.scissor,
          shader: runtime.graphics.shader,
          transform: runtime.graphics.copyTransform(),
          drawTransform: _matrixFromTransformArgumentOrStandardTransform(
            args,
            1,
            'love.graphics.draw',
          ),
          textObject: text,
        ),
      );
      return null;
    }

    if (_meshIfPresent(_valueAt(args, 0)) case final LoveMesh mesh) {
      _queueMeshDrawCommand(
        runtime,
        mesh: mesh,
        args: args,
        transformIndex: 1,
        symbol: 'love.graphics.draw',
      );
      return null;
    }

    if (_spriteBatchIfPresent(_valueAt(args, 0))
        case final LoveSpriteBatch spriteBatch) {
      runtime.graphics.addCommand(
        LoveSpriteBatchCommand(
          color: runtime.graphics.color,
          lineWidth: runtime.graphics.lineWidth,
          lineStyle: runtime.graphics.lineStyle,
          lineJoin: runtime.graphics.lineJoin,
          blendMode: runtime.graphics.blendMode,
          blendAlphaMode: runtime.graphics.blendAlphaMode,
          colorMask: runtime.graphics.colorMask,
          wireframe: runtime.graphics.wireframe,
          scissor: runtime.graphics.scissor,
          shader: runtime.graphics.shader,
          transform: runtime.graphics.copyTransform(),
          drawTransform: _matrixFromTransformArgumentOrStandardTransform(
            args,
            1,
            'love.graphics.draw',
          ),
          spriteBatch: spriteBatch,
        ),
      );
      return null;
    }

    if (_particleSystemIfPresent(_valueAt(args, 0))
        case final LoveParticleSystem particleSystem) {
      runtime.graphics.addCommand(
        LoveParticleSystemCommand(
          color: runtime.graphics.color,
          lineWidth: runtime.graphics.lineWidth,
          lineStyle: runtime.graphics.lineStyle,
          lineJoin: runtime.graphics.lineJoin,
          blendMode: runtime.graphics.blendMode,
          blendAlphaMode: runtime.graphics.blendAlphaMode,
          colorMask: runtime.graphics.colorMask,
          wireframe: runtime.graphics.wireframe,
          scissor: runtime.graphics.scissor,
          shader: runtime.graphics.shader,
          transform: runtime.graphics.copyTransform(),
          drawTransform: _matrixFromTransformArgumentOrStandardTransform(
            args,
            1,
            'love.graphics.draw',
          ),
          particleSystem: particleSystem.snapshotForDraw(),
        ),
      );
      return null;
    }

    if (_videoIfPresent(_valueAt(args, 0)) case final LoveVideo video) {
      final quad = _quadIfPresent(_valueAt(args, 1));
      final startIndex = quad == null ? 1 : 2;
      if (_canUseLiveVideoCommand(runtime, video, quad: quad)) {
        runtime.graphics.addCommand(
          LoveVideoCommand(
            color: runtime.graphics.color,
            lineWidth: runtime.graphics.lineWidth,
            lineStyle: runtime.graphics.lineStyle,
            lineJoin: runtime.graphics.lineJoin,
            blendMode: runtime.graphics.blendMode,
            blendAlphaMode: runtime.graphics.blendAlphaMode,
            colorMask: runtime.graphics.colorMask,
            wireframe: runtime.graphics.wireframe,
            scissor: runtime.graphics.scissor,
            shader: runtime.graphics.shader,
            transform: runtime.graphics.copyTransform(),
            drawTransform: _videoDrawTransform(
              video,
              args,
              transformIndex: startIndex,
              symbol: 'love.graphics.draw',
            ),
            video: video,
            quad: quad,
          ),
        );
        return null;
      }

      return _snapshotDrawableImageForVideo(runtime, video).then((resolvedImage) {
        if (resolvedImage == null) {
          return null;
        }

        runtime.graphics.addCommand(
          LoveImageCommand(
            color: runtime.graphics.color,
            lineWidth: runtime.graphics.lineWidth,
            lineStyle: runtime.graphics.lineStyle,
            lineJoin: runtime.graphics.lineJoin,
            blendMode: runtime.graphics.blendMode,
            blendAlphaMode: runtime.graphics.blendAlphaMode,
            colorMask: runtime.graphics.colorMask,
            wireframe: runtime.graphics.wireframe,
            scissor: runtime.graphics.scissor,
            shader: runtime.graphics.shader,
            transform: runtime.graphics.copyTransform(),
            drawTransform: _videoDrawTransform(
              video,
              args,
              transformIndex: startIndex,
              symbol: 'love.graphics.draw',
            ),
            image: resolvedImage,
            quad: quad,
          ),
        );
        return null;
      });
    }

    final image = _requireImage(args, 0, 'love.graphics.draw');
    final quad = _quadIfPresent(_valueAt(args, 1));
    final startIndex = quad == null ? 1 : 2;
    final resolvedImage = switch (image) {
      final LoveCanvas canvas => canvas.snapshot(),
      _ => image,
    };
    final layer = _directTextureDrawLayer(
      resolvedImage,
      quad,
      'love.graphics.draw',
    );

    runtime.graphics.addCommand(
      LoveImageCommand(
        color: runtime.graphics.color,
        lineWidth: runtime.graphics.lineWidth,
        lineStyle: runtime.graphics.lineStyle,
        lineJoin: runtime.graphics.lineJoin,
        blendMode: runtime.graphics.blendMode,
        blendAlphaMode: runtime.graphics.blendAlphaMode,
        colorMask: runtime.graphics.colorMask,
        wireframe: runtime.graphics.wireframe,
        scissor: runtime.graphics.scissor,
        shader: runtime.graphics.shader,
        transform: runtime.graphics.copyTransform(),
        drawTransform: _matrixFromTransformArgumentOrStandardTransform(
          args,
          startIndex,
          'love.graphics.draw',
        ),
        image: resolvedImage,
        quad: quad,
        layer: layer,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.print`.
///
/// This queues unwrapped text using either an explicit font argument or the
/// current graphics font, while preserving LOVE's transform-object overload.
LoveApiImplementation _bindGraphicsPrint(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final spans = _requireColoredTextSpans(args, 0, 'love.graphics.print');
    final explicitFont = _fontIfPresent(_valueAt(args, 1));
    final startIndex = _graphicsTextArgumentStartIndex(args);
    final transform = _transformIfPresent(_valueAt(args, startIndex));
    final x = transform == null
        ? _optionalNumber(
            args,
            startIndex,
            'love.graphics.print',
            defaultValue: 0.0,
          )
        : 0.0;
    final y = transform == null
        ? _optionalNumber(
            args,
            startIndex + 1,
            'love.graphics.print',
            defaultValue: 0.0,
          )
        : 0.0;

    void addCommand(LoveFont font) {
      runtime.graphics.addCommand(
        LoveTextCommand(
          color: runtime.graphics.color,
          lineWidth: runtime.graphics.lineWidth,
          lineStyle: runtime.graphics.lineStyle,
          lineJoin: runtime.graphics.lineJoin,
          blendMode: runtime.graphics.blendMode,
          blendAlphaMode: runtime.graphics.blendAlphaMode,
          colorMask: runtime.graphics.colorMask,
          wireframe: runtime.graphics.wireframe,
          scissor: runtime.graphics.scissor,
          shader: runtime.graphics.shader,
          transform: runtime.graphics.copyTransform(),
          textTransform: transform == null
              ? _standardTransform(args, startIndex, 'love.graphics.print')
              : Matrix4.copy(transform.matrix),
          font: font,
          spans: spans,
          x: x,
          y: y,
        ),
      );
    }

    if (explicitFont case final LoveFont font) {
      addCommand(font);
      return null;
    }

    final fontOrFuture = runtime.ensureCurrentGraphicsFontOrFuture();
    if (fontOrFuture is Future<LoveFont>) {
      return fontOrFuture.then((font) {
        addCommand(font);
        return null;
      });
    }

    addCommand(fontOrFuture as LoveFont);
    return null;
  };
}

/// Binds `love.graphics.printf`.
///
/// This mirrors [love.graphics.print] but also records wrap width and text
/// alignment for formatted layout.
LoveApiImplementation _bindGraphicsPrintf(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final spans = _requireColoredTextSpans(args, 0, 'love.graphics.printf');
    final explicitFont = _fontIfPresent(_valueAt(args, 1));
    final startIndex = _graphicsTextArgumentStartIndex(args);
    final transform = _transformIfPresent(_valueAt(args, startIndex));
    final x = transform == null
        ? _requireNumber(args, startIndex, 'love.graphics.printf')
        : 0.0;
    final y = transform == null
        ? _requireNumber(args, startIndex + 1, 'love.graphics.printf')
        : 0.0;
    final formatIndex = transform == null ? startIndex + 2 : startIndex + 1;
    final limit = _requireNumber(args, formatIndex, 'love.graphics.printf');
    final align = args.length > formatIndex + 1
        ? _valueAt(args, formatIndex + 1) == null
              ? 'left'
              : _textAlign(
                  _requireString(args, formatIndex + 1, 'love.graphics.printf'),
                )
        : 'left';

    void addCommand(LoveFont font) {
      runtime.graphics.addCommand(
        LoveTextCommand(
          color: runtime.graphics.color,
          lineWidth: runtime.graphics.lineWidth,
          lineStyle: runtime.graphics.lineStyle,
          lineJoin: runtime.graphics.lineJoin,
          blendMode: runtime.graphics.blendMode,
          blendAlphaMode: runtime.graphics.blendAlphaMode,
          colorMask: runtime.graphics.colorMask,
          wireframe: runtime.graphics.wireframe,
          scissor: runtime.graphics.scissor,
          shader: runtime.graphics.shader,
          transform: runtime.graphics.copyTransform(),
          textTransform: transform == null
              ? _standardTransform(
                  args,
                  startIndex,
                  'love.graphics.printf',
                  transformOffset: 4,
                )
              : Matrix4.copy(transform.matrix),
          font: font,
          spans: spans,
          x: x,
          y: y,
          limit: limit,
          align: align,
        ),
      );
    }

    if (explicitFont case final LoveFont font) {
      addCommand(font);
      return null;
    }

    final fontOrFuture = runtime.ensureCurrentGraphicsFontOrFuture();
    if (fontOrFuture is Future<LoveFont>) {
      return fontOrFuture.then((font) {
        addCommand(font);
        return null;
      });
    }

    addCommand(fontOrFuture as LoveFont);
    return null;
  };
}
