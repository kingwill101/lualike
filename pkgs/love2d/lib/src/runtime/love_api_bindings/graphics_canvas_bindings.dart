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
      mipmapFilter: runtime.graphics.defaultMipmapFilter,
      mipmapSharpness: runtime.graphics.defaultMipmapSharpness,
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

String? _canvasSliceFieldName(LoveCanvas canvas) {
  return switch (canvas.textureType) {
    'array' || 'volume' => 'layer',
    'cube' => 'face',
    _ => null,
  };
}

int _validateCanvasTargetSlice(
  LoveCanvas canvas,
  int slice,
  String symbol, {
  String? fieldName,
}) {
  final maxSlice = canvas.renderTargetSliceCount;
  if (slice < 1 || slice > maxSlice) {
    final label = fieldName ?? 'slice';
    throw LuaError('$symbol $label must be between 1 and $maxSlice');
  }
  return slice;
}

int _validateCanvasTargetMipmap(LoveCanvas canvas, int mipmap, String symbol) {
  if (mipmap != 1) {
    throw LuaError(
      '$symbol does not yet support rendering to mipmap levels other than 1',
    );
  }
  return mipmap;
}

LoveCanvasRenderTarget _renderTargetFromSetupTable(
  Map<dynamic, dynamic> table,
  String symbol,
) {
  final canvasEntry =
      _tableIndexedEntry(table, 1) ?? _tableEntry(table, 'canvas');
  final canvas = _canvasIfPresent(canvasEntry);
  if (canvas == null) {
    throw LuaError(
      '$symbol setup table does not contain a valid Canvas target',
    );
  }

  final sliceField = _canvasSliceFieldName(canvas);
  final slice = sliceField == null
      ? 1
      : _validateCanvasTargetSlice(
          canvas,
          _tableRoundedInt(table, sliceField) ?? 1,
          symbol,
          fieldName: sliceField,
        );
  final mipmap = _validateCanvasTargetMipmap(
    canvas,
    _tableRoundedInt(table, 'mipmap') ?? 1,
    symbol,
  );
  return LoveCanvasRenderTarget(canvas: canvas, slice: slice, mipmap: mipmap);
}

Value _wrapCanvasRenderTargetTable(
  LibraryRegistrationContext context,
  LoveCanvasRenderTarget target,
) {
  final renderTarget = <Object?, Object?>{
    1: _wrapCanvas(context, target.canvas),
  };
  if (_canvasSliceFieldName(target.canvas) case final fieldName?) {
    renderTarget[fieldName] = target.slice;
  }
  renderTarget['mipmap'] = target.mipmap;
  return ValueClass.table(renderTarget);
}

// ---------------------------------------------------------------------------
// love.graphics.setCanvas
// ---------------------------------------------------------------------------

LoveApiImplementation _bindGraphicsSetCanvas(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty || _rawValue(args.first) == null) {
      runtime.graphics.setCanvas(null);
      return null;
    }

    const symbol = 'love.graphics.setCanvas';
    final firstArg = _valueAt(args, 0);
    LoveCanvasRenderTarget? target;

    final directCanvas = _canvasIfPresent(firstArg);
    if (directCanvas != null) {
      if (directCanvas.textureType == '2d') {
        final mipmap =
            args.length >= 2 && _numberIfPresent(_valueAt(args, 1)) != null
            ? _textureMipmapLevel(args, 1, symbol)
            : 1;
        target = LoveCanvasRenderTarget(
          canvas: directCanvas,
          mipmap: _validateCanvasTargetMipmap(directCanvas, mipmap, symbol),
        );
      } else {
        if (args.length < 2 || _numberIfPresent(_valueAt(args, 1)) == null) {
          throw LuaError(
            '$symbol non-2D canvases require an explicit slice argument',
          );
        }
        final slice = _validateCanvasTargetSlice(
          directCanvas,
          _textureMipmapLevel(args, 1, symbol),
          symbol,
        );
        final mipmap =
            args.length >= 3 && _numberIfPresent(_valueAt(args, 2)) != null
            ? _textureMipmapLevel(args, 2, symbol)
            : 1;
        target = LoveCanvasRenderTarget(
          canvas: directCanvas,
          slice: slice,
          mipmap: _validateCanvasTargetMipmap(directCanvas, mipmap, symbol),
        );
      }
    } else if (_tableIfPresent(firstArg) case final table?) {
      final firstEntry = _tableIndexedEntry(table, 1);
      final directSetupCanvas = _canvasIfPresent(_tableEntry(table, 'canvas'));
      final firstEntryCanvas = _canvasIfPresent(firstEntry);
      final firstEntryTable = firstEntryCanvas == null
          ? _tableIfPresent(firstEntry)
          : null;
      if (directSetupCanvas != null) {
        target = _renderTargetFromSetupTable(table, symbol);
      } else if (firstEntryTable != null) {
        target = _renderTargetFromSetupTable(firstEntryTable, symbol);
      } else {
        final canvases = _tableSequence(
          table,
          symbol,
          emptyError: 'requires at least one Canvas target',
        );
        for (final entry in canvases) {
          final canvas = _canvasIfPresent(entry);
          if (canvas == null) {
            throw LuaError(
              '$symbol expected Canvas objects in the plain table variant',
            );
          }
          if (canvas.textureType != '2d') {
            throw LuaError(
              'Non-2D canvases must use the table-of-tables variant of setCanvas.',
            );
          }
        }
        target = LoveCanvasRenderTarget(
          canvas: _canvasIfPresent(canvases.first)!,
        );
      }
    } else {
      throw LuaError('$symbol expected a Canvas or setup table at argument 1');
    }

    runtime.graphics.setCanvas(
      target.canvas,
      slice: target.slice,
      mipmap: target.mipmap,
    );
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
    final target = runtime.graphics.activeCanvasTarget;
    if (target == null) {
      return null;
    }
    if (target.mipmap == 1 && target.canvas.textureType == '2d') {
      return _wrapCanvas(context, target.canvas);
    }
    return ValueClass.table(<Object?, Object?>{
      1: _wrapCanvasRenderTargetTable(context, target),
    });
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
