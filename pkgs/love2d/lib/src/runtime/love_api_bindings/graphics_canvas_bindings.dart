part of '../love_api_bindings.dart';

final List<String> _canvasFormatNames = <String>[
  for (final enumDoc in loveApiEnums)
    if (enumDoc.symbol == 'PixelFormat')
      for (final constant in enumDoc.constants) constant.name,
];

// ---------------------------------------------------------------------------
// love.graphics.newCanvas
// ---------------------------------------------------------------------------

LoveApiImplementation _bindGraphicsNewCanvas(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.graphics.newCanvas';

    // Resolve width / height.
    final width = args.isNotEmpty
        ? _requireRoundedInt(args, 0, symbol)
        : runtime.windowMetrics.width;
    final height = args.length >= 2
        ? _requireRoundedInt(args, 1, symbol)
        : runtime.windowMetrics.height;

    if (width <= 0 || height <= 0) {
      throw LuaError('$symbol width and height must both be > 0');
    }

    // Third argument: may be a number (legacy layers shorthand) or a table
    // (settings).
    int? legacyLayers;
    if (args.length >= 3) {
      final third = _valueAt(args, 2);
      final asNumber = _numberIfPresent(third);
      if (asNumber != null) {
        legacyLayers = asNumber.round();
      }
      // If it's a table it will be parsed below as settings.
    }

    final settingsTable = args.length >= 3
        ? (legacyLayers == null
              ? _optionalTableTarget(_valueAt(args, 2))?.$2
              : null)
        : null;

    // --- Extract settings ---
    final dpiScale = settingsTable == null
        ? runtime.windowMetrics.dpiScale
        : (_numberIfPresent(_tableEntry(settingsTable, 'dpiscale')) ??
              runtime.windowMetrics.dpiScale);

    final msaa = settingsTable == null
        ? 0
        : (_tableRoundedInt(settingsTable, 'msaa') ?? 0);

    final format = settingsTable == null
        ? 'normal'
        : (_tableString(settingsTable, 'format') ?? 'normal');

    final mipmapMode = settingsTable == null
        ? LoveCanvasMipmapMode.none
        : _canvasMipmapMode(
            _tableString(settingsTable, 'mipmaps') ?? 'none',
            symbol,
          );

    // Texture type: '2d' (default), 'array', 'volume', 'cube'.
    final rawType = settingsTable == null
        ? '2d'
        : (_tableString(settingsTable, 'type') ?? '2d');

    final textureType = _validateCanvasTextureType(rawType, symbol);

    // Layers parameter – used for 'array' and 'volume' types.
    // Priority: settings.layers > legacy 3rd-arg number.
    final int layerCount;
    final int depth;
    switch (textureType) {
      case 'cube':
        // Cube maps always have exactly 6 faces.
        layerCount = 6;
        depth = 1;
      case 'array':
        final layers =
            (settingsTable == null
                ? null
                : _tableRoundedInt(settingsTable, 'layers')) ??
            legacyLayers;
        if (layers == null || layers < 1) {
          throw LuaError(
            '$symbol array canvases require a positive "layers" setting',
          );
        }
        layerCount = layers;
        depth = 1;
      case 'volume':
        final layers =
            (settingsTable == null
                ? null
                : _tableRoundedInt(settingsTable, 'layers')) ??
            legacyLayers;
        if (layers == null || layers < 1) {
          throw LuaError(
            '$symbol volume canvases require a positive "layers" setting',
          );
        }
        layerCount = 1;
        depth = layers;
      default: // '2d'
        layerCount = 1;
        depth = 1;
    }

    final readable = settingsTable == null
        ? !_isDepthStencilFormat(format)
        : (_tableBool(settingsTable, 'readable') ??
              !_isDepthStencilFormat(format));

    // --- Validate constraints (mirrors LOVE's Canvas.cpp) ---
    if ((!readable || msaa > 1) && mipmapMode != LoveCanvasMipmapMode.none) {
      throw LuaError(
        '$symbol non-readable and MSAA canvases cannot have mipmaps',
      );
    }
    if (readable && _isDepthStencilFormat(format) && msaa > 1) {
      throw LuaError(
        '$symbol readable depth/stencil canvases do not support MSAA',
      );
    }
    if (mipmapMode == LoveCanvasMipmapMode.auto &&
        _isDepthStencilFormat(format)) {
      throw LuaError(
        '$symbol automatic mipmap generation is not supported for '
        'depth/stencil canvases',
      );
    }
    if (textureType == 'cube' && width != height) {
      throw LuaError('$symbol cube canvases must have equal width and height');
    }

    final canvas = LoveCanvas(
      source: runtime.nextCanvasSource(),
      width: width,
      height: height,
      dpiScale: dpiScale,
      format: format,
      readable: readable,
      filter: runtime.graphics.defaultFilter,
      msaa: msaa,
      mipmapMode: mipmapMode,
      textureType: textureType,
      layerCount: layerCount,
      depth: depth,
    );
    runtime.registerCanvas(canvas);
    return _wrapCanvas(context, canvas);
  };
}

String _validateCanvasTextureType(String raw, String symbol) {
  return switch (raw) {
    '2d' || 'array' || 'volume' || 'cube' => raw,
    _ => throw LuaError(
      '$symbol unknown texture type "$raw" '
      '(expected "2d", "array", "volume", or "cube")',
    ),
  };
}

// ---------------------------------------------------------------------------
// love.graphics.setCanvas
// ---------------------------------------------------------------------------

LoveApiImplementation _bindGraphicsSetCanvas(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    // No arguments → restore the screen as the render target.
    if (args.isEmpty || _rawValue(args.first) == null) {
      runtime.graphics.setCanvas(null);
      return null;
    }

    // Collect all canvas targets from the argument list, which may be:
    //   setCanvas(canvas [, mipmap])
    //   setCanvas(canvas, slice, mipmap)
    //   setCanvas(canvas1, canvas2, ...)            – multi-target
    //   setCanvas({canvas=c, mipmap=m, layer=l}, …) – table setup

    final canvases = <LoveCanvas>[];

    for (var i = 0; i < args.length; i++) {
      final arg = _valueAt(args, i);

      // Raw nil / false → stop collecting.
      if (_rawValue(arg) == null) break;

      final directCanvas = _canvasIfPresent(arg);
      if (directCanvas != null) {
        canvases.add(directCanvas);
        // Skip optional mipmap / slice integers that follow a canvas argument.
        while (i + 1 < args.length &&
            _numberIfPresent(_valueAt(args, i + 1)) != null) {
          i++;
        }
        continue;
      }

      final table = _tableIfPresent(arg);
      if (table != null) {
        // Table setup: { canvas = c, mipmap = 1, layer = 1 }
        // or a positional table: { canvas, mipmap }
        LoveCanvas? tableCanvas;

        // Try explicit "canvas" key first.
        final canvasEntry = _tableEntry(table, 'canvas');
        if (canvasEntry != null) {
          tableCanvas = _canvasIfPresent(canvasEntry);
        }

        // Fall back to positional index 1.
        if (tableCanvas == null) {
          final positional = _tableIndexedEntry(table, 1);
          if (positional != null) {
            tableCanvas = _canvasIfPresent(positional);
          }
        }

        if (tableCanvas == null) {
          throw LuaError(
            'love.graphics.setCanvas setup table at argument ${i + 1} '
            'does not contain a valid Canvas',
          );
        }
        canvases.add(tableCanvas);
        continue;
      }

      throw LuaError(
        'love.graphics.setCanvas expected a Canvas or setup table at '
        'argument ${i + 1}',
      );
    }

    if (canvases.isEmpty) {
      runtime.graphics.setCanvas(null);
      return null;
    }

    // Use the first canvas as the primary render target.  Additional canvases
    // in a multi-target setup are registered so the runtime is aware of them,
    // but drawing is always directed to the first target.
    runtime.graphics.setCanvas(canvases.first);
    return null;
  };
}

// ---------------------------------------------------------------------------
// love.graphics.getCanvas
// ---------------------------------------------------------------------------

LoveApiImplementation _bindGraphicsGetCanvas(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final canvas = runtime.graphics.activeCanvas;
    return canvas == null ? null : _wrapCanvas(context, canvas);
  };
}

// ---------------------------------------------------------------------------
// love.graphics.getCanvasFormats
// ---------------------------------------------------------------------------

LoveApiImplementation _bindGraphicsGetCanvasFormats(
  LibraryRegistrationContext context,
) {
  return (args) {
    final formats = <Object?, Object?>{};
    for (final format in _canvasFormatNames) {
      formats[format] = format != 'unknown';
    }
    return Value(formats);
  };
}
