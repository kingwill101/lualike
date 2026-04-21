part of '../love_api_bindings.dart';

Value _wrapFont(LibraryRegistrationContext context, LoveFont font) {
  final cached = _loveFontWrapperCache[font];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Font', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveFontObjectKey: font,
    'getAscent': Value(
      builder.create((args) => _requireFont(args, 0, 'Font:getAscent').ascent),
      functionName: 'getAscent',
    ),
    'getBaseline': Value(
      builder.create(
        (args) => _requireFont(args, 0, 'Font:getBaseline').baseline,
      ),
      functionName: 'getBaseline',
    ),
    'getDPIScale': Value(
      builder.create(
        (args) => _requireFont(args, 0, 'Font:getDPIScale').dpiScale,
      ),
      functionName: 'getDPIScale',
    ),
    'getDescent': Value(
      builder.create(
        (args) => _requireFont(args, 0, 'Font:getDescent').descent,
      ),
      functionName: 'getDescent',
    ),
    'getFilter': Value(
      builder.create(
        (args) => _filterResult(_requireFont(args, 0, 'Font:getFilter').filter),
      ),
      functionName: 'getFilter',
    ),
    'getHeight': Value(
      builder.create((args) => _requireFont(args, 0, 'Font:getHeight').height),
      functionName: 'getHeight',
    ),
    'getKerning': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:getKerning');
        final kerningPair = _coerceKerningGlyphLookupPair(
          args,
          symbol: 'Font:getKerning',
          leftIndex: 1,
          rightIndex: 2,
        );
        return font.getKerning(kerningPair.left, kerningPair.right);
      }),
      functionName: 'getKerning',
    ),
    'getLineHeight': Value(
      builder.create(
        (args) => _requireFont(args, 0, 'Font:getLineHeight').lineHeight,
      ),
      functionName: 'getLineHeight',
    ),
    'getWidth': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:getWidth');
        final text =
            _strictFontTextSegmentLike(
              _valueAt(args, 1),
              symbol: 'Font:getWidth',
              argumentIndex: 2,
            ) ??
            (throw LuaError('Font:getWidth expected a string at argument 2'));
        return font.measureWidth(text);
      }),
      functionName: 'getWidth',
    ),
    'getWrap': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:getWrap');
        final text = _requireStrictFontTextLike(args, 1, 'Font:getWrap');
        final wrapLimit = _requireNumber(args, 2, 'Font:getWrap');
        final wrapped = font.wrapText(text, wrapLimit);
        final lines = <Object?, Object?>{};
        for (var i = 0; i < wrapped.lines.length; i++) {
          lines[i + 1] = wrapped.lines[i];
        }
        return Value.multi(<Object?>[wrapped.width, Value(lines)]);
      }),
      functionName: 'getWrap',
    ),
    'hasGlyphs': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:hasGlyphs');
        if (args.length < 2) {
          _requireNumber(args, 1, 'Font:hasGlyphs');
        }
        final glyphValues = <Object?>[];
        for (var index = 1; index < args.length; index++) {
          glyphValues.add(
            _coerceGlyphLookupArgument(args, symbol: 'Font:hasGlyphs', index),
          );
        }
        return font.hasGlyphValues(glyphValues);
      }),
      functionName: 'hasGlyphs',
    ),
    'release': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Object:release');
        if (_loveFontReleased[font] == true) {
          return false;
        }

        _loveFontReleased[font] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'setFilter': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:setFilter');
        font.filter = _filterFromArgs(
          args,
          1,
          'Font:setFilter',
          currentFilter: font.filter,
        );
        return null;
      }),
      functionName: 'setFilter',
    ),
    'setFallbacks': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:setFallbacks');
        final fallbacks = <LoveFont>[];
        for (var index = 1; index < args.length; index++) {
          fallbacks.add(_requireFont(args, index, 'Font:setFallbacks'));
        }
        try {
          font.setFallbacks(fallbacks);
        } on ArgumentError catch (error) {
          throw LuaError(error.message ?? 'Font:setFallbacks failed');
        }
        return null;
      }),
      functionName: 'setFallbacks',
    ),
    'setLineHeight': Value(
      builder.create((args) {
        final font = _requireFont(args, 0, 'Font:setLineHeight');
        final value = _requireNumber(args, 1, 'Font:setLineHeight');
        font.lineHeight = value;
        return null;
      }),
      functionName: 'setLineHeight',
    ),
    'type': Value(
      builder.create((args) {
        _requireFont(args, 0, 'Object:type');
        return 'Font';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireFont(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveFontWrapperCache[font] = table;
  return table;
}

Value _wrapTextDrawable(
  LibraryRegistrationContext context,
  LoveTextDrawable text,
) {
  final cached = _loveTextWrapperCache[text];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'Text', 'Drawable', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveTextObjectKey: text,
    'add': Value(
      builder.create((args) {
        final drawable = _requireTextDrawable(args, 0, 'Text:add');
        final index = drawable.add(
          _requireColoredTextSpans(args, 1, 'Text:add'),
          _matrixFromTransformArgumentOrStandardTransform(args, 2, 'Text:add'),
        );
        return index + 1;
      }),
      functionName: 'add',
    ),
    'addf': Value(
      builder.create((args) {
        final drawable = _requireTextDrawable(args, 0, 'Text:addf');
        final index = drawable.addf(
          _requireColoredTextSpans(args, 1, 'Text:addf'),
          _requireNumber(args, 2, 'Text:addf'),
          _textAlign(_requireString(args, 3, 'Text:addf'), 'Text:addf'),
          _matrixFromTransformArgumentOrStandardTransform(args, 4, 'Text:addf'),
        );
        return index + 1;
      }),
      functionName: 'addf',
    ),
    'clear': Value(
      builder.create((args) {
        _requireTextDrawable(args, 0, 'Text:clear').clear();
        return null;
      }),
      functionName: 'clear',
    ),
    'getDimensions': Value(
      builder.create((args) {
        final drawable = _requireTextDrawable(args, 0, 'Text:getDimensions');
        final index = _optionalTextEntryIndex(args, 1, 'Text:getDimensions');
        final dimensions = drawable.getDimensions(index);
        return Value.multi(<Object?>[dimensions.width, dimensions.height]);
      }),
      functionName: 'getDimensions',
    ),
    'getFont': Value(
      builder.create(
        (args) => _wrapFont(
          context,
          _requireTextDrawable(args, 0, 'Text:getFont').font,
        ),
      ),
      functionName: 'getFont',
    ),
    'getHeight': Value(
      builder.create((args) {
        final drawable = _requireTextDrawable(args, 0, 'Text:getHeight');
        final index = _optionalTextEntryIndex(args, 1, 'Text:getHeight');
        return drawable.getHeight(index);
      }),
      functionName: 'getHeight',
    ),
    'getWidth': Value(
      builder.create((args) {
        final drawable = _requireTextDrawable(args, 0, 'Text:getWidth');
        final index = _optionalTextEntryIndex(args, 1, 'Text:getWidth');
        return drawable.getWidth(index);
      }),
      functionName: 'getWidth',
    ),
    'set': Value(
      builder.create((args) {
        _requireTextDrawable(
          args,
          0,
          'Text:set',
        ).set(_requireColoredTextSpans(args, 1, 'Text:set'));
        return null;
      }),
      functionName: 'set',
    ),
    'setf': Value(
      builder.create((args) {
        _requireTextDrawable(args, 0, 'Text:setf').setf(
          _requireColoredTextSpans(args, 1, 'Text:setf'),
          _requireNumber(args, 2, 'Text:setf'),
          _textAlign(_requireString(args, 3, 'Text:setf'), 'Text:setf'),
        );
        return null;
      }),
      functionName: 'setf',
    ),
    'setFont': Value(
      builder.create((args) {
        final drawable = _requireTextDrawable(args, 0, 'Text:setFont');
        drawable.font = _requireFont(args, 1, 'Text:setFont');
        return null;
      }),
      functionName: 'setFont',
    ),
    'release': Value(
      builder.create((args) {
        final text = _requireTextDrawable(args, 0, 'Object:release');
        if (_loveTextReleased[text] == true) {
          return false;
        }

        _loveTextReleased[text] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireTextDrawable(args, 0, 'Object:type');
        return 'Text';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireTextDrawable(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveTextWrapperCache[text] = table;
  return table;
}

int _optionalTextEntryIndex(List<Object?> args, int index, String symbol) {
  if (args.length <= index || _valueAt(args, index) == null) {
    return -1;
  }

  return _requireRoundedInt(args, index, symbol) - 1;
}

String _requireStrictFontTextLike(
  List<Object?> args,
  int index,
  String symbol,
) {
  final direct = _strictFontTextSegmentLike(
    _valueAt(args, index),
    symbol: symbol,
    argumentIndex: index + 1,
  );
  if (direct != null) {
    return direct;
  }

  final table = _tableIfPresent(_valueAt(args, index));
  if (table != null) {
    final segments = <String>[];
    for (var i = 1; ; i++) {
      final entry = _tableIndexedEntry(table, i);
      if (entry == null) {
        break;
      }

      final colorTable = _tableIfPresent(entry);
      if (colorTable != null) {
        _tableIndexedNumber(colorTable, 1, symbol);
        _tableIndexedNumber(colorTable, 2, symbol);
        _tableIndexedNumber(colorTable, 3, symbol);
        _tableIndexedNumber(colorTable, 4, symbol, defaultValue: 1.0);
        continue;
      }

      final segment = _strictFontTextSegmentLike(
        entry,
        symbol: symbol,
        argumentIndex: index + 1,
      );
      if (segment == null) {
        throw LuaError(
          '$symbol expected a string or colored text at argument '
          '${index + 1}',
        );
      }

      segments.add(segment);
    }
    return segments.join();
  }

  throw LuaError(
    '$symbol expected a string or colored text at argument ${index + 1}',
  );
}

String? _strictFontTextSegmentLike(
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) {
  final direct = _strictFontStringLike(
    value,
    symbol: symbol,
    argumentIndex: argumentIndex,
  );
  if (direct != null) {
    return direct;
  }

  final raw = switch (value) {
    final Value wrapped => wrapped.raw,
    _ => value,
  };
  return switch (raw) {
    final num numericValue => _loveLuaJitNumberToString(numericValue),
    _ => null,
  };
}

Value _wrapImage(LibraryRegistrationContext context, LoveImage image) {
  final cached = _loveImageWrapperCache[image];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveImageObjectKey: image,
    ..._textureEntries(
      builder,
      requireTexture: (args, symbol) => _requireImage(args, 0, symbol),
      updateFilter: (args, filter) {
        final image = _requireImage(args, 0, 'Texture:setFilter');
        final table = _tableIdentityIfPresent(args.first);
        if (table == null) {
          throw LuaError('Texture:setFilter expected an Image receiver');
        }
        table[_loveImageObjectKey] = image.copyWith(filter: filter);
      },
      updateMipmapFilter: (args, filter, sharpness) {
        final image = _requireImage(args, 0, 'Texture:setMipmapFilter');
        final table = _tableIdentityIfPresent(args.first);
        if (table == null) {
          throw LuaError('Texture:setMipmapFilter expected an Image receiver');
        }
        table[_loveImageObjectKey] = image.copyWith(
          clearMipmapFilter: filter == null,
          mipmapFilter: filter,
          mipmapSharpness: sharpness,
        );
      },
      updateWrap: (args, wrap) {
        final image = _requireImage(args, 0, 'Texture:setWrap');
        final table = _tableIdentityIfPresent(args.first);
        if (table == null) {
          throw LuaError('Texture:setWrap expected an Image receiver');
        }
        table[_loveImageObjectKey] = image.copyWith(wrap: wrap);
        return true;
      },
      updateDepthSampleMode: (args, compareMode) {
        final image = _requireImage(args, 0, 'Texture:setDepthSampleMode');
        final table = _tableIdentityIfPresent(args.first);
        if (table == null) {
          throw LuaError(
            'Texture:setDepthSampleMode expected an Image receiver',
          );
        }
        table[_loveImageObjectKey] = image.copyWith(
          clearDepthSampleMode: compareMode == null,
          depthSampleMode: compareMode,
        );
      },
    ),
    'replacePixels': Value(
      builder.create((args) {
        final image = _requireImage(args, 0, 'Image:replacePixels');
        final replacement = _requireImageData(args, 1, 'Image:replacePixels');
        final slice = args.length >= 3
            ? _requireRoundedInt(args, 2, 'Image:replacePixels')
            : 1;
        if (slice != 1) {
          throw LuaError(
            'Image:replacePixels only supports 2D image slice 1 in the current runtime',
          );
        }

        final mipmap = args.length >= 4
            ? _textureMipmapLevel(args, 3, 'Image:replacePixels')
            : 1;
        if (mipmap > image.mipmapCount) {
          throw LuaError(
            'Image:replacePixels invalid image mipmap index $mipmap',
          );
        }

        final x = args.length >= 5
            ? _requireRoundedInt(args, 4, 'Image:replacePixels')
            : 0;
        final y = args.length >= 6
            ? _requireRoundedInt(args, 5, 'Image:replacePixels')
            : 0;

        final targetData = image.imageDataAtMipmap(mipmap);
        if (targetData == null) {
          throw LuaError('Image:replacePixels image does not store ImageData');
        }
        if (replacement.format != targetData.format) {
          throw LuaError('Image:replacePixels pixel formats must match');
        }

        final mipWidth = image.pixelWidthAtMipmap(mipmap);
        final mipHeight = image.pixelHeightAtMipmap(mipmap);
        if (x < 0 ||
            y < 0 ||
            replacement.width <= 0 ||
            replacement.height <= 0 ||
            x + replacement.width > mipWidth ||
            y + replacement.height > mipHeight) {
          throw LuaError(
            'Image:replacePixels invalid rectangle dimensions for target image',
          );
        }

        for (var row = 0; row < replacement.height; row++) {
          for (var column = 0; column < replacement.width; column++) {
            targetData.setPixel(
              x + column,
              y + row,
              replacement.getPixel(column, row),
            );
          }
        }

        final existingMipmaps = image.imageDataMipmaps;
        final reloadMipmaps = args.length >= 7
            ? _requireBoolean(args, 6, 'Image:replacePixels')
            : mipmap == 1 && (existingMipmaps?.length ?? 0) > 1;
        final updatedMipmaps = existingMipmaps == null
            ? <LoveImageData>[targetData]
            : List<LoveImageData>.from(existingMipmaps);
        updatedMipmaps[mipmap - 1] = targetData;
        final resolvedMipmaps =
            reloadMipmaps && mipmap == 1 && updatedMipmaps.length > 1
            ? targetData.generateMipmaps()
            : List<LoveImageData>.unmodifiable(updatedMipmaps);

        final table = _tableIdentityIfPresent(args.first);
        if (table != null) {
          table[_loveImageObjectKey] = image.copyWith(
            imageData: resolvedMipmaps.first,
            imageDataMipmaps: resolvedMipmaps,
            preferImageDataRendering: true,
          );
        }
        return null;
      }),
      functionName: 'replacePixels',
    ),
  });
  _loveImageWrapperCache[image] = table;
  return table;
}

final Expando<bool> _loveCanvasReleased = Expando<bool>('love2dCanvasReleased');

Value _wrapCanvas(LibraryRegistrationContext context, LoveCanvas canvas) {
  final cached = _loveCanvasWrapperCache[canvas];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No interpreter available for Canvas bindings');
  }
  final runtime = _runtimeContext(context);

  final table = ValueClass.table(<Object?, Object?>{
    _loveImageObjectKey: canvas,
    _loveCanvasObjectKey: canvas,
    ..._textureEntries(
      builder,
      requireTexture: (args, symbol) => _requireCanvas(args, 0, symbol),
      updateFilter: (args, filter) {
        _requireCanvas(args, 0, 'Texture:setFilter').setFilterValue(filter);
      },
      updateMipmapFilter: (args, filter, sharpness) {
        _requireCanvas(
          args,
          0,
          'Texture:setMipmapFilter',
        ).setMipmapFilterValue(filter, sharpness);
      },
      updateWrap: (args, wrap) {
        _requireCanvas(args, 0, 'Texture:setWrap').setWrapValue(wrap);
        return true;
      },
      updateDepthSampleMode: (args, compareMode) {
        _requireCanvas(
          args,
          0,
          'Texture:setDepthSampleMode',
        ).setDepthSampleModeValue(compareMode);
      },
    ),
    'getMSAA': Value(
      builder.create((args) => _requireCanvas(args, 0, 'Canvas:getMSAA').msaa),
      functionName: 'getMSAA',
    ),
    'generateMipmaps': Value(
      builder.create((args) {
        _requireCanvas(args, 0, 'Canvas:generateMipmaps').generateMipmaps();
        return null;
      }),
      functionName: 'generateMipmaps',
    ),
    'getMipmapMode': Value(
      builder.create(
        (args) => _canvasMipmapModeName(
          _requireCanvas(args, 0, 'Canvas:getMipmapMode').mipmapMode,
        ),
      ),
      functionName: 'getMipmapMode',
    ),
    'newImageData': Value(
      builder.create((args) {
        // Mirrors LOVE's Canvas.cpp / wrap_Canvas.cpp validation.
        final canvas = _requireCanvas(args, 0, 'Canvas:newImageData');
        if (!canvas.readable) {
          throw LuaError(
            'Canvas:newImageData cannot be called on non-readable Canvases',
          );
        }
        if (_isDepthStencilFormat(canvas.format)) {
          throw LuaError(
            'Canvas:newImageData cannot be called on Canvases with depth/stencil pixel formats',
          );
        }
        if (runtime.graphics.activeCanvas == canvas) {
          throw LuaError(
            'Canvas:newImageData cannot be called while that Canvas is currently active',
          );
        }

        final mipmap = args.length >= 2
            ? _textureMipmapLevel(args, 1, 'Canvas:newImageData')
            : 1;
        final pixelWidth = canvas.pixelWidthAtMipmap(mipmap);
        final pixelHeight = canvas.pixelHeightAtMipmap(mipmap);
        final x = args.length >= 3
            ? _requireRoundedInt(args, 2, 'Canvas:newImageData')
            : 0;
        final y = args.length >= 4
            ? _requireRoundedInt(args, 3, 'Canvas:newImageData')
            : 0;
        final width = args.length >= 5
            ? _requireRoundedInt(args, 4, 'Canvas:newImageData')
            : pixelWidth;
        final height = args.length >= 6
            ? _requireRoundedInt(args, 5, 'Canvas:newImageData')
            : pixelHeight;

        if (x < 0 ||
            y < 0 ||
            width <= 0 ||
            height <= 0 ||
            x + width > pixelWidth ||
            y + height > pixelHeight) {
          throw LuaError('Canvas:newImageData invalid rectangle dimensions');
        }

        return _wrapImageData(
          context,
          canvas.readbackImageData(
            mipmap: mipmap,
            x: x,
            y: y,
            width: width,
            height: height,
          ),
        );
      }),
      functionName: 'newImageData',
    ),
    'renderTo': Value(
      builder.create((args) async {
        final canvas = _requireCanvas(args, 0, 'Canvas:renderTo');
        var callbackIndex = 1;
        if (args.length >= 2 && _numberIfPresent(_valueAt(args, 1)) != null) {
          final slice = _textureMipmapLevel(args, 1, 'Canvas:renderTo');
          if (slice != 1) {
            throw LuaError(
              'Canvas:renderTo slice arguments are only supported for non-2D canvases',
            );
          }
          callbackIndex = 2;
        }

        final callback = _requireCallable(
          args,
          callbackIndex,
          'Canvas:renderTo',
        );
        final previousCanvas = runtime.graphics.activeCanvas;
        runtime.graphics.setCanvas(canvas);
        try {
          await interpreter.callFunction(
            callback,
            args.sublist(callbackIndex + 1),
          );
          return null;
        } finally {
          runtime.graphics.setCanvas(previousCanvas);
        }
      }),
      functionName: 'renderTo',
    ),
    'release': Value(
      builder.create((args) {
        final canvas = _requireCanvas(args, 0, 'Object:release');
        if (_loveCanvasReleased[canvas] == true) {
          return false;
        }
        _loveCanvasReleased[canvas] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(builder.create((args) => 'Canvas'), functionName: 'type'),
    'typeOf': Value(
      builder.create((args) {
        final queried = _requireString(args, 1, 'Object:typeOf');
        return queried == 'Canvas' ||
            queried == 'Texture' ||
            queried == 'Drawable' ||
            queried == 'Object';
      }),
      functionName: 'typeOf',
    ),
  });
  _loveCanvasWrapperCache[canvas] = table;
  return table;
}

Value _wrapImageData(
  LibraryRegistrationContext context,
  LoveImageData imageData,
) {
  final cached = _loveImageDataWrapperCache[imageData];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No interpreter available for ImageData bindings');
  }
  final table = ValueClass.table(<Object?, Object?>{
    _loveImageDataObjectKey: imageData,
    'encode': Value(
      builder.create((args) async {
        // Mirrors LOVE's wrap_ImageData.cpp: the first argument is the
        // encoded image format, and the optional second argument is a save
        // filename to write in addition to returning FileData.
        const symbol = 'ImageData:encode';
        final imageData = _requireImageData(args, 0, symbol);
        final format = _imageEncodeFormat(
          _requireString(args, 1, symbol),
          symbol,
        );
        final filename = switch (_valueAt(args, 2)) {
          null => null,
          final Object value when _rawValue(value) == null => null,
          final Object value => _stringLike(value),
        };
        if (args.length >= 3 &&
            _valueAt(args, 2) != null &&
            _rawValue(_valueAt(args, 2)) != null &&
            filename == null) {
          throw LuaError('$symbol expected a filename string at argument 3');
        }

        final encodedBytes = imageData.encode(format);
        final encodedFilename = filename ?? 'Image.$format';
        if (filename != null) {
          await _writeResourceBytesOrThrow(
            context,
            filename,
            encodedBytes,
            symbol: symbol,
          );
        }

        return _wrapFilesystemFileDataCompat(
          context,
          LoveFilesystemFileData(
            bytes: encodedBytes,
            filename: encodedFilename,
          ),
        );
      }),
      functionName: 'encode',
    ),
    'getDimensions': Value(
      builder.create(
        (args) => Value.multi(<Object?>[
          _requireImageData(args, 0, 'ImageData:getDimensions').width,
          _requireImageData(args, 0, 'ImageData:getDimensions').height,
        ]),
      ),
      functionName: 'getDimensions',
    ),
    'getFormat': Value(
      builder.create(
        (args) => _requireImageData(args, 0, 'ImageData:getFormat').format,
      ),
      functionName: 'getFormat',
    ),
    'getHeight': Value(
      builder.create(
        (args) => _requireImageData(args, 0, 'ImageData:getHeight').height,
      ),
      functionName: 'getHeight',
    ),
    'getPixel': Value(
      builder.create((args) {
        final imageData = _requireImageData(args, 0, 'ImageData:getPixel');
        final color = imageData.getPixel(
          _requireRoundedInt(args, 1, 'ImageData:getPixel'),
          _requireRoundedInt(args, 2, 'ImageData:getPixel'),
        );
        return _colorResult(color);
      }),
      functionName: 'getPixel',
    ),
    'getWidth': Value(
      builder.create(
        (args) => _requireImageData(args, 0, 'ImageData:getWidth').width,
      ),
      functionName: 'getWidth',
    ),
    'setPixel': Value(
      builder.create((args) {
        final imageData = _requireImageData(args, 0, 'ImageData:setPixel');
        imageData.setPixel(
          _requireRoundedInt(args, 1, 'ImageData:setPixel'),
          _requireRoundedInt(args, 2, 'ImageData:setPixel'),
          _requireColor(args, 3, 'ImageData:setPixel'),
        );
        return null;
      }),
      functionName: 'setPixel',
    ),
    'paste': Value(
      builder.create((args) {
        final imageData = _requireImageData(args, 0, 'ImageData:paste');
        final source = _requireImageData(args, 1, 'ImageData:paste');
        final dx = _requireRoundedInt(args, 2, 'ImageData:paste');
        final dy = _requireRoundedInt(args, 3, 'ImageData:paste');
        final sx = args.length >= 5
            ? _requireRoundedInt(args, 4, 'ImageData:paste')
            : 0;
        final sy = args.length >= 6
            ? _requireRoundedInt(args, 5, 'ImageData:paste')
            : 0;
        final sw = args.length >= 7
            ? _requireRoundedInt(args, 6, 'ImageData:paste')
            : source.width;
        final sh = args.length >= 8
            ? _requireRoundedInt(args, 7, 'ImageData:paste')
            : source.height;

        if (source.format != imageData.format) {
          throw LuaError('ImageData:paste pixel formats must match');
        }
        if (sx < 0 ||
            sy < 0 ||
            sw <= 0 ||
            sh <= 0 ||
            sx + sw > source.width ||
            sy + sh > source.height ||
            dx < 0 ||
            dy < 0 ||
            dx + sw > imageData.width ||
            dy + sh > imageData.height) {
          throw LuaError('ImageData:paste invalid rectangle dimensions');
        }

        for (var row = 0; row < sh; row++) {
          for (var column = 0; column < sw; column++) {
            imageData.setPixel(
              dx + column,
              dy + row,
              source.getPixel(sx + column, sy + row),
            );
          }
        }
        return null;
      }),
      functionName: 'paste',
    ),
    'mapPixel': Value(
      builder.create((args) async {
        // Mirrors LOVE's wrap_ImageData.lua / wrap_ImageData.cpp validation.
        const symbol = 'ImageData:mapPixel';
        final imageData = _requireImageData(args, 0, symbol);
        final callback = _requireCallable(args, 1, symbol);
        final x = args.length >= 3 ? _requireRoundedInt(args, 2, symbol) : 0;
        final y = args.length >= 4 ? _requireRoundedInt(args, 3, symbol) : 0;
        final width = args.length >= 5
            ? _requireRoundedInt(args, 4, symbol)
            : imageData.width;
        final height = args.length >= 6
            ? _requireRoundedInt(args, 5, symbol)
            : imageData.height;

        if (x < 0 ||
            y < 0 ||
            width <= 0 ||
            height <= 0 ||
            x + width > imageData.width ||
            y + height > imageData.height) {
          throw LuaError('ImageData:mapPixel invalid rectangle dimensions');
        }

        for (var row = y; row < y + height; row++) {
          for (var column = x; column < x + width; column++) {
            final pixel = imageData.getPixel(column, row);
            final mapped = await interpreter.callFunction(
              callback,
              <Object?>[column, row, pixel.r, pixel.g, pixel.b, pixel.a],
              debugName: 'love.image.mapPixel',
              debugNameWhat: 'method',
            );
            imageData.setPixel(
              column,
              row,
              _mapPixelColor(mapped, symbol: symbol),
            );
          }
        }
        return null;
      }),
      functionName: 'mapPixel',
    ),
  });
  _loveImageDataWrapperCache[imageData] = table;
  return table;
}

Value _wrapFilesystemFileDataCompat(
  LibraryRegistrationContext context,
  LoveFilesystemFileData data,
) {
  final cached = _loveFilesystemFileDataWrapperCache[data];
  if (cached != null) {
    return cached;
  }

  Value bindSymbol(String symbol, String publicName) {
    return bindLoveApiFunction(
      context,
      symbol: symbol,
      publicName: publicName,
      implementations: const <String, LoveApiImplementation>{},
    );
  }

  final builder = BuiltinFunctionBuilder(context);

  final table = ValueClass.table(<Object?, Object?>{
    _loveFilesystemFileDataObjectKeyCompat: data,
    _loveFilesystemObjectTypeKeyCompat: 'FileData',
    _loveFilesystemObjectHierarchyKeyCompat: const <String>{
      'FileData',
      'Data',
      'Object',
    },
    'clone': bindSymbol('Data:clone', 'clone'),
    'getExtension': bindSymbol('FileData:getExtension', 'getExtension'),
    'getFilename': bindSymbol('FileData:getFilename', 'getFilename'),
    'getPointer': Value(
      builder.create(
        (args) => _wrapDataPointer(context, identity: data, bytes: data.bytes),
      ),
      functionName: 'getPointer',
    ),
    'getFFIPointer': Value(
      builder.create(
        (args) => _wrapDataPointer(context, identity: data, bytes: data.bytes),
      ),
      functionName: 'getFFIPointer',
    ),
    'getSize': bindSymbol('Data:getSize', 'getSize'),
    'getString': bindSymbol('Data:getString', 'getString'),
    'release': bindSymbol('Object:release', 'release'),
    'type': bindSymbol('Object:type', 'type'),
    'typeOf': bindSymbol('Object:typeOf', 'typeOf'),
  });
  _loveFilesystemFileDataWrapperCache[data] = table;
  return table;
}

String _imageEncodeFormat(String value, String symbol) {
  final normalized = value.toLowerCase();
  return switch (normalized) {
    'png' || 'jpg' || 'bmp' || 'tga' => normalized,
    _ => throw LuaError('$symbol invalid encoded image format "$value"'),
  };
}

LoveColor _mapPixelColor(Object? value, {required String symbol}) {
  final raw = _rawValue(value);
  if (raw is List) {
    if (raw.length < 3 || raw[0] is! num || raw[1] is! num || raw[2] is! num) {
      throw LuaError('$symbol callback must return at least r, g, and b');
    }
    return LoveColor(
      (raw[0] as num).toDouble(),
      (raw[1] as num).toDouble(),
      (raw[2] as num).toDouble(),
      raw.length >= 4 && raw[3] is num ? (raw[3] as num).toDouble() : 1.0,
    );
  }

  throw LuaError('$symbol callback must return color components');
}

Map<Object?, Object?> _textureEntries(
  BuiltinFunctionBuilder builder, {
  required LoveImage Function(List<Object?> args, String symbol) requireTexture,
  required void Function(List<Object?> args, LoveGraphicsDefaultFilter filter)
  updateFilter,
  required void Function(
    List<Object?> args,
    LoveGraphicsFilterMode? filter,
    double sharpness,
  )
  updateMipmapFilter,
  required bool Function(List<Object?> args, LoveGraphicsWrap wrap) updateWrap,
  required void Function(
    List<Object?> args,
    LoveGraphicsCompareMode? compareMode,
  )
  updateDepthSampleMode,
}) {
  return <Object?, Object?>{
    'getDimensions': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:getDimensions');
        return Value.multi(<Object?>[texture.width, texture.height]);
      }),
      functionName: 'getDimensions',
    ),
    'getDepth': Value(
      builder.create((args) => requireTexture(args, 'Texture:getDepth').depth),
      functionName: 'getDepth',
    ),
    'getDPIScale': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:getDPIScale').dpiScale,
      ),
      functionName: 'getDPIScale',
    ),
    'getFilter': Value(
      builder.create(
        (args) =>
            _filterResult(requireTexture(args, 'Texture:getFilter').filter),
      ),
      functionName: 'getFilter',
    ),
    'getFormat': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:getFormat').format,
      ),
      functionName: 'getFormat',
    ),
    'getHeight': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:getHeight').height,
      ),
      functionName: 'getHeight',
    ),
    'getLayerCount': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:getLayerCount').layerCount,
      ),
      functionName: 'getLayerCount',
    ),
    'getMipmapCount': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:getMipmapCount').mipmapCount,
      ),
      functionName: 'getMipmapCount',
    ),
    'getMipmapFilter': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:getMipmapFilter');
        final filter = texture.mipmapFilter;
        return Value.multi(<Object?>[
          filter == null ? null : _filterModeName(filter),
          texture.mipmapSharpness,
        ]);
      }),
      functionName: 'getMipmapFilter',
    ),
    'getPixelDimensions': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:getPixelDimensions');
        final mipmap = _textureMipmapLevel(
          args,
          1,
          'Texture:getPixelDimensions',
        );
        return Value.multi(<Object?>[
          texture.pixelWidthAtMipmap(mipmap),
          texture.pixelHeightAtMipmap(mipmap),
        ]);
      }),
      functionName: 'getPixelDimensions',
    ),
    'getPixelHeight': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:getPixelHeight');
        final mipmap = _textureMipmapLevel(args, 1, 'Texture:getPixelHeight');
        return texture.pixelHeightAtMipmap(mipmap);
      }),
      functionName: 'getPixelHeight',
    ),
    'getPixelWidth': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:getPixelWidth');
        final mipmap = _textureMipmapLevel(args, 1, 'Texture:getPixelWidth');
        return texture.pixelWidthAtMipmap(mipmap);
      }),
      functionName: 'getPixelWidth',
    ),
    'getWidth': Value(
      builder.create((args) => requireTexture(args, 'Texture:getWidth').width),
      functionName: 'getWidth',
    ),
    'getTextureType': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:getTextureType').textureType,
      ),
      functionName: 'getTextureType',
    ),
    'getWrap': Value(
      builder.create(
        (args) => _wrapResult(requireTexture(args, 'Texture:getWrap').wrap),
      ),
      functionName: 'getWrap',
    ),
    'getDepthSampleMode': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:getDepthSampleMode');
        final compareMode = texture.depthSampleMode;
        return compareMode == null ? null : _compareModeName(compareMode);
      }),
      functionName: 'getDepthSampleMode',
    ),
    'isCompressed': Value(
      builder.create(
        (args) => requireTexture(args, 'Image:isCompressed').compressed,
      ),
      functionName: 'isCompressed',
    ),
    'isFormatLinear': Value(
      builder.create(
        (args) => requireTexture(args, 'Image:isFormatLinear').formatLinear,
      ),
      functionName: 'isFormatLinear',
    ),
    'isReadable': Value(
      builder.create(
        (args) => requireTexture(args, 'Texture:isReadable').readable,
      ),
      functionName: 'isReadable',
    ),
    'setFilter': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:setFilter');
        updateFilter(
          args,
          _filterFromArgs(
            args,
            1,
            'Texture:setFilter',
            currentFilter: texture.filter,
          ),
        );
        return null;
      }),
      functionName: 'setFilter',
    ),
    'setMipmapFilter': Value(
      builder.create((args) {
        // Mirrors LOVE's wrap_Texture.cpp / Texture.cpp validation.
        final texture = requireTexture(args, 'Texture:setMipmapFilter');
        final rawMode = _rawValue(_valueAt(args, 1));
        final filter = rawMode == null
            ? null
            : _filterMode(
                _requireString(args, 1, 'Texture:setMipmapFilter'),
                'Texture:setMipmapFilter',
              );
        if (filter != null && texture.mipmapCount <= 1) {
          throw LuaError(
            'Texture:setMipmapFilter non-mipmapped texture cannot have mipmap filtering',
          );
        }
        updateMipmapFilter(
          args,
          filter,
          args.length >= 3
              ? _requireNumber(args, 2, 'Texture:setMipmapFilter')
              : 0.0,
        );
        return null;
      }),
      functionName: 'setMipmapFilter',
    ),
    'setWrap': Value(
      builder.create((args) {
        final texture = requireTexture(args, 'Texture:setWrap');
        return updateWrap(
          args,
          _wrapFromArgs(args, 1, 'Texture:setWrap', currentWrap: texture.wrap),
        );
      }),
      functionName: 'setWrap',
    ),
    'setDepthSampleMode': Value(
      builder.create((args) {
        // Mirrors LOVE's wrap_Texture.cpp / Texture.cpp validation.
        final texture = requireTexture(args, 'Texture:setDepthSampleMode');
        final rawMode = _rawValue(_valueAt(args, 1));
        final compareMode = rawMode == null
            ? null
            : _compareMode(
                _requireString(args, 1, 'Texture:setDepthSampleMode'),
                'Texture:setDepthSampleMode',
              );
        if (compareMode != null &&
            (!texture.readable || !_isDepthStencilFormat(texture.format))) {
          throw LuaError(
            'Texture:setDepthSampleMode only readable depth textures can have a depth sample compare mode',
          );
        }
        updateDepthSampleMode(args, compareMode);
        return null;
      }),
      functionName: 'setDepthSampleMode',
    ),
  };
}

Value _wrapQuad(LibraryRegistrationContext context, LoveQuad quad) {
  final cached = _loveQuadWrapperCache[quad];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveQuadObjectKey: quad,
    'getTextureDimensions': Value(
      builder.create((args) {
        final quad = _requireQuad(args, 0, 'Quad:getTextureDimensions');
        return Value.multi(<Object?>[quad.textureWidth, quad.textureHeight]);
      }),
      functionName: 'getTextureDimensions',
    ),
    'getViewport': Value(
      builder.create((args) {
        final quad = _requireQuad(args, 0, 'Quad:getViewport');
        return Value.multi(<Object?>[quad.x, quad.y, quad.width, quad.height]);
      }),
      functionName: 'getViewport',
    ),
    'setViewport': Value(
      builder.create((args) {
        final quad = _requireQuad(args, 0, 'Quad:setViewport');
        quad.setViewport(
          _requireNumber(args, 1, 'Quad:setViewport'),
          _requireNumber(args, 2, 'Quad:setViewport'),
          _requireNumber(args, 3, 'Quad:setViewport'),
          _requireNumber(args, 4, 'Quad:setViewport'),
        );
        return null;
      }),
      functionName: 'setViewport',
    ),
  });
  _loveQuadWrapperCache[quad] = table;
  return table;
}

Value _wrapTransform(
  LibraryRegistrationContext context,
  LoveTransform transform,
) {
  final cached = _loveTransformWrapperCache[transform];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  final table = ValueClass.table(<Object?, Object?>{
    _loveTransformObjectKey: transform,
    'apply': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:apply');
        final other = _requireTransform(args, 1, 'Transform:apply');
        transform.apply(other);
        return _wrapTransform(context, transform);
      }),
      functionName: 'apply',
    ),
    'clone': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:clone');
        return _wrapTransform(context, transform.clone());
      }),
      functionName: 'clone',
    ),
    'getMatrix': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:getMatrix');
        return Value.multi(transform.getMatrixRowMajor().cast<Object?>());
      }),
      functionName: 'getMatrix',
    ),
    'inverse': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:inverse');
        return _wrapTransform(context, transform.inverse());
      }),
      functionName: 'inverse',
    ),
    'inverseTransformPoint': Value(
      builder.create((args) {
        final transform = _requireTransform(
          args,
          0,
          'Transform:inverseTransformPoint',
        );
        final point = transform.inverseTransformPoint(
          _requireNumber(args, 1, 'Transform:inverseTransformPoint'),
          _requireNumber(args, 2, 'Transform:inverseTransformPoint'),
        );
        return Value.multi(<Object?>[point.x, point.y]);
      }),
      functionName: 'inverseTransformPoint',
    ),
    'isAffine2DTransform': Value(
      builder.create(
        (args) => _requireTransform(
          args,
          0,
          'Transform:isAffine2DTransform',
        ).isAffine2DTransform,
      ),
      functionName: 'isAffine2DTransform',
    ),
    'reset': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:reset');
        transform.reset();
        return _wrapTransform(context, transform);
      }),
      functionName: 'reset',
    ),
    'rotate': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:rotate');
        transform.rotate(_requireNumber(args, 1, 'Transform:rotate'));
        return _wrapTransform(context, transform);
      }),
      functionName: 'rotate',
    ),
    'scale': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:scale');
        final scaleX = _requireNumber(args, 1, 'Transform:scale');
        final scaleY = args.length >= 3
            ? _requireNumber(args, 2, 'Transform:scale')
            : scaleX;
        transform.scale(scaleX, scaleY);
        return _wrapTransform(context, transform);
      }),
      functionName: 'scale',
    ),
    'setMatrix': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:setMatrix');
        var index = 1;
        var columnMajor = false;

        final layout = _stringLike(_valueAt(args, index));
        if (layout != null) {
          columnMajor = _matrixLayout(layout, 'Transform:setMatrix');
          index++;
        }

        final tableTarget = _tableTargetIfPresent(_valueAt(args, index));
        if (tableTarget != null) {
          final elements = _matrixElementsFromTable(
            tableTarget.$2,
            columnMajor: columnMajor,
            symbol: 'Transform:setMatrix',
          );
          transform.setMatrixFromColumnMajor(elements);
          return _wrapTransform(context, transform);
        }

        if (args.length - index < 16) {
          throw LuaError(
            'Transform:setMatrix expected 16 matrix elements at argument ${index + 1}',
          );
        }

        final elements = List<double>.generate(
          16,
          (offset) =>
              _requireNumber(args, index + offset, 'Transform:setMatrix'),
          growable: false,
        );
        if (columnMajor) {
          transform.setMatrixFromColumnMajor(elements);
        } else {
          transform.setMatrixFromRowMajor(elements);
        }
        return _wrapTransform(context, transform);
      }),
      functionName: 'setMatrix',
    ),
    'setTransformation': Value(
      builder.create((args) {
        final transform = _requireTransform(
          args,
          0,
          'Transform:setTransformation',
        );
        final x = _optionalNumber(
          args,
          1,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        final y = _optionalNumber(
          args,
          2,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        final angle = _optionalNumber(
          args,
          3,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        final scaleX = _optionalNumber(
          args,
          4,
          'Transform:setTransformation',
          defaultValue: 1.0,
        );
        final scaleY = _optionalNumber(
          args,
          5,
          'Transform:setTransformation',
          defaultValue: scaleX,
        );
        final originX = _optionalNumber(
          args,
          6,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        final originY = _optionalNumber(
          args,
          7,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        final shearX = _optionalNumber(
          args,
          8,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        final shearY = _optionalNumber(
          args,
          9,
          'Transform:setTransformation',
          defaultValue: 0.0,
        );
        transform.setTransformation(
          x: x,
          y: y,
          angle: angle,
          scaleX: scaleX,
          scaleY: scaleY,
          originX: originX,
          originY: originY,
          shearX: shearX,
          shearY: shearY,
        );
        return _wrapTransform(context, transform);
      }),
      functionName: 'setTransformation',
    ),
    'shear': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:shear');
        transform.shear(
          _requireNumber(args, 1, 'Transform:shear'),
          _requireNumber(args, 2, 'Transform:shear'),
        );
        return _wrapTransform(context, transform);
      }),
      functionName: 'shear',
    ),
    'transformPoint': Value(
      builder.create((args) {
        final transform = _requireTransform(
          args,
          0,
          'Transform:transformPoint',
        );
        final point = transform.transformPoint(
          _requireNumber(args, 1, 'Transform:transformPoint'),
          _requireNumber(args, 2, 'Transform:transformPoint'),
        );
        return Value.multi(<Object?>[point.x, point.y]);
      }),
      functionName: 'transformPoint',
    ),
    'translate': Value(
      builder.create((args) {
        final transform = _requireTransform(args, 0, 'Transform:translate');
        transform.translate(
          _requireNumber(args, 1, 'Transform:translate'),
          _requireNumber(args, 2, 'Transform:translate'),
        );
        return _wrapTransform(context, transform);
      }),
      functionName: 'translate',
    ),
  });
  _loveTransformWrapperCache[transform] = table;
  return table;
}
