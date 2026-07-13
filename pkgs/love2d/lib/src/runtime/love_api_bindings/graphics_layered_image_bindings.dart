part of '../love_api_bindings.dart';

/// Returns the 1-based sequential values from [table].
///
/// Throws a [LuaError] when the sequence is empty so callers can surface
/// LOVE-style argument failures.
List<Object?> _tableSequence(
  Map<dynamic, dynamic> table,
  String symbol, {
  required String emptyError,
}) {
  final values = <Object?>[];
  for (var index = 1; ; index++) {
    final entry = _tableIndexedEntry(table, index);
    if (entry == null) {
      break;
    }
    values.add(entry);
  }

  if (values.isEmpty) {
    throw LuaError('$symbol $emptyError');
  }

  return values;
}

/// Returns a copy of [settings] with mipmaps disabled.
///
/// This is used while loading per-slice sources for manual mipmap assembly so
/// the runtime does not generate additional mip levels automatically.
Map<dynamic, dynamic>? _settingsWithoutMipmaps(
  Map<dynamic, dynamic>? settings,
) {
  if (settings == null) {
    return const <dynamic, dynamic>{'mipmaps': false};
  }

  final copy = Map<dynamic, dynamic>.from(settings);
  copy['mipmaps'] = false;
  return copy;
}

/// Returns [value] when it is a non-empty 1-based source sequence table.
Map<dynamic, dynamic>? _indexedSourceSequenceTable(Object? value) {
  final table = _tableIfPresent(value);
  if (table == null || _tableIndexedEntry(table, 1) == null) {
    return null;
  }

  return table;
}

/// Resolves one layered-texture leaf source into a [LoveImage].
///
/// Leaf sources may be `ImageData`, compressed image data, filenames, or
/// file-backed objects accepted by the shared resource-loading helpers.
Future<LoveImage> _resolveLayeredTextureLeafImage(
  LibraryRegistrationContext context,
  Object? sourceValue, {
  required String symbol,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
  required LoveGraphicsFilterMode? defaultMipmapFilter,
  required double defaultMipmapSharpness,
}) async {
  final imageData = _imageDataIfPresent(sourceValue);
  if (imageData != null) {
    return _resolveImageFromImageData(
      imageData: imageData,
      source: 'ImageData',
      defaultFilter: defaultFilter,
      defaultMipmapFilter: defaultMipmapFilter,
      defaultMipmapSharpness: defaultMipmapSharpness,
      settings: settings,
    );
  }

  final compressedImageData = _compressedImageDataIfPresent(sourceValue);
  if (compressedImageData != null) {
    return _resolveImageFromCompressedImageData(
      imageData: compressedImageData,
      symbol: symbol,
      defaultFilter: defaultFilter,
      defaultMipmapFilter: defaultMipmapFilter,
      defaultMipmapSharpness: defaultMipmapSharpness,
      settings: settings,
    );
  }

  final source = _stringLike(sourceValue);
  if (source != null) {
    try {
      return await _loadImageFromSource(
        context,
        source,
        symbol: symbol,
        settings: settings,
        defaultFilter: defaultFilter,
        defaultMipmapFilter: defaultMipmapFilter,
        defaultMipmapSharpness: defaultMipmapSharpness,
      );
    } catch (error) {
      if (error is LuaError) {
        rethrow;
      }
      throw LuaError('$symbol failed to load "$source": $error');
    }
  }

  try {
    final fileData = await _requireResourceFileData(
      context,
      sourceValue,
      symbol,
      expectedKinds: 'filename, FileData, File, or ImageData',
    );
    try {
      final imageData = LoveImageData.decodeEncodedBytes(
        bytes: fileData.bytes,
        source: fileData.filename,
      );
      return _resolveImageFromImageData(
        imageData: imageData,
        source: fileData.filename,
        defaultFilter: defaultFilter,
        defaultMipmapFilter: defaultMipmapFilter,
        defaultMipmapSharpness: defaultMipmapSharpness,
        settings: settings,
      );
    } catch (error) {
      throw LuaError('$symbol failed to load "${fileData.filename}": $error');
    }
  } on LuaError {
    rethrow;
  }
}

/// Resolves one layered-texture leaf source into readable [LoveImageData].
///
/// This is used by packed cubemap and packed volume extraction paths that need
/// direct pixel access before constructing final images.
Future<LoveImageData> _resolveLayeredTextureLeafImageData(
  LibraryRegistrationContext context,
  Object? sourceValue, {
  required String symbol,
}) async {
  final imageData = _imageDataIfPresent(sourceValue);
  if (imageData != null) {
    return imageData.clone();
  }

  final compressedImageData = _compressedImageDataIfPresent(sourceValue);
  if (compressedImageData != null) {
    throw LuaError(
      '$symbol does not yet support CompressedImageData layered sources in the current runtime',
    );
  }

  final source = _stringLike(sourceValue);
  if (source != null) {
    try {
      return await _loadImageDataFromSource(context, source, symbol: symbol);
    } catch (error) {
      if (error is LuaError) {
        rethrow;
      }
      throw LuaError('$symbol failed to load "$source": $error');
    }
  }

  try {
    final fileData = await _requireResourceFileData(
      context,
      sourceValue,
      symbol,
      expectedKinds: 'filename, FileData, File, or ImageData',
    );
    try {
      return LoveImageData.decodeEncodedBytes(
        bytes: fileData.bytes,
        source: fileData.filename,
      );
    } catch (error) {
      throw LuaError('$symbol failed to load "${fileData.filename}": $error');
    }
  } on LuaError {
    rethrow;
  }
}

/// Extracts six cubemap faces from a packed cubemap atlas image.
///
/// Several common LOVE cubemap layouts are supported, including vertical and
/// horizontal strips and cross layouts.
List<LoveImageData> _extractPackedCubemapFaceImageData(
  LoveImageData source, {
  required String symbol,
}) {
  final totalWidth = source.width;
  final totalHeight = source.height;

  LoveImageData extract({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return source.copyRegion(x: x, y: y, width: width, height: height);
  }

  if (totalWidth % 3 == 0 &&
      totalHeight % 4 == 0 &&
      totalWidth ~/ 3 == totalHeight ~/ 4) {
    final faceSize = totalWidth ~/ 3;
    return <LoveImageData>[
      extract(x: faceSize, y: faceSize, width: faceSize, height: faceSize),
      extract(x: faceSize, y: faceSize * 3, width: faceSize, height: faceSize),
      extract(x: faceSize, y: 0, width: faceSize, height: faceSize),
      extract(x: faceSize, y: faceSize * 2, width: faceSize, height: faceSize),
      extract(x: 0, y: faceSize, width: faceSize, height: faceSize),
      extract(x: faceSize * 2, y: faceSize, width: faceSize, height: faceSize),
    ];
  }

  if (totalWidth % 4 == 0 &&
      totalHeight % 3 == 0 &&
      totalWidth ~/ 4 == totalHeight ~/ 3) {
    final faceSize = totalWidth ~/ 4;
    return <LoveImageData>[
      extract(x: faceSize * 2, y: faceSize, width: faceSize, height: faceSize),
      extract(x: 0, y: faceSize, width: faceSize, height: faceSize),
      extract(x: faceSize, y: 0, width: faceSize, height: faceSize),
      extract(x: faceSize, y: faceSize * 2, width: faceSize, height: faceSize),
      extract(x: faceSize, y: faceSize, width: faceSize, height: faceSize),
      extract(x: faceSize * 3, y: faceSize, width: faceSize, height: faceSize),
    ];
  }

  if (totalHeight % 6 == 0 && totalWidth == totalHeight ~/ 6) {
    final faceSize = totalWidth;
    return <LoveImageData>[
      for (var index = 0; index < 6; index++)
        extract(x: 0, y: faceSize * index, width: faceSize, height: faceSize),
    ];
  }

  if (totalWidth % 6 == 0 && totalWidth ~/ 6 == totalHeight) {
    final faceSize = totalHeight;
    return <LoveImageData>[
      for (var index = 0; index < 6; index++)
        extract(x: faceSize * index, y: 0, width: faceSize, height: faceSize),
    ];
  }

  throw LuaError('$symbol unknown cubemap image dimensions');
}

/// Resolves a packed cubemap source into six face images.
Future<List<LoveImage>> _resolvePackedCubemapFaces(
  LibraryRegistrationContext context,
  Object? sourceValue, {
  required String symbol,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
  required LoveGraphicsFilterMode? defaultMipmapFilter,
  required double defaultMipmapSharpness,
}) async {
  final sourceImageData = await _resolveLayeredTextureLeafImageData(
    context,
    sourceValue,
    symbol: symbol,
  );
  final faceImageData = _extractPackedCubemapFaceImageData(
    sourceImageData,
    symbol: symbol,
  );
  return List<LoveImage>.unmodifiable([
    for (var face = 0; face < faceImageData.length; face++)
      _resolveImageFromImageData(
        imageData: faceImageData[face],
        source: 'CubeImageFace${face + 1}',
        defaultFilter: defaultFilter,
        defaultMipmapFilter: defaultMipmapFilter,
        defaultMipmapSharpness: defaultMipmapSharpness,
        settings: settings,
      ),
  ]);
}

/// Returns whether [sources] represent packed cubemap images for manual
/// mipmaps.
Future<bool> _isPackedCubemapMipmapTable(
  LibraryRegistrationContext context,
  List<Object?> sources, {
  required String symbol,
}) async {
  if (sources.isEmpty) {
    return false;
  }

  final first = sources.first;
  if (!await _isLayeredTextureLeafSourceValue(context, first, symbol: symbol)) {
    return false;
  }
  if (_compressedImageDataIfPresent(first) != null) {
    return false;
  }

  try {
    _extractPackedCubemapFaceImageData(
      await _resolveLayeredTextureLeafImageData(context, first, symbol: symbol),
      symbol: symbol,
    );
    return true;
  } on LuaError catch (error) {
    if (error.message.contains('unknown cubemap image dimensions')) {
      return false;
    }
    rethrow;
  }
}

/// Resolves manual packed cubemap mipmaps into six cubemap-face images with
/// assembled mip chains.
Future<List<LoveImage>> _resolvePackedCubemapMipmappedFaces(
  LibraryRegistrationContext context,
  List<Object?> sources, {
  required String symbol,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
  required LoveGraphicsFilterMode? defaultMipmapFilter,
  required double defaultMipmapSharpness,
}) async {
  final leafSettings = _settingsWithoutMipmaps(settings);
  final perFaceMipmaps = List<List<LoveImage>>.generate(
    6,
    (_) => <LoveImage>[],
    growable: false,
  );

  for (final source in sources) {
    final faces = await _resolvePackedCubemapFaces(
      context,
      source,
      symbol: symbol,
      settings: leafSettings,
      defaultFilter: defaultFilter,
      defaultMipmapFilter: defaultMipmapFilter,
      defaultMipmapSharpness: defaultMipmapSharpness,
    );
    if (faces.length != 6) {
      throw LuaError(
        '$symbol packed cubemap mipmap sources must resolve to 6 faces',
      );
    }
    for (var face = 0; face < 6; face++) {
      perFaceMipmaps[face].add(faces[face]);
    }
  }

  return List<LoveImage>.unmodifiable(
    perFaceMipmaps
        .map(
          (mipmaps) => _buildManualMipmapImage(
            mipmaps: mipmaps,
            symbol: symbol,
            textureType: 'cube',
          ),
        )
        .toList(growable: false),
  );
}

/// Returns whether [sourceValue] is a valid leaf layered-texture source.
Future<bool> _isLayeredTextureLeafSourceValue(
  LibraryRegistrationContext context,
  Object? sourceValue, {
  required String symbol,
}) async {
  if (_stringLike(sourceValue) != null ||
      _imageDataIfPresent(sourceValue) != null ||
      _compressedImageDataIfPresent(sourceValue) != null ||
      _filesystemFileDataCompatIfPresent(sourceValue) != null) {
    return true;
  }

  return await _resourceFileDataIfPresent(context, sourceValue, symbol) != null;
}

/// Extracts square volume layers from a packed strip image.
List<LoveImageData> _extractPackedVolumeLayerImageData(
  LoveImageData source, {
  required String symbol,
}) {
  final totalWidth = source.width;
  final totalHeight = source.height;

  if (totalWidth % totalHeight == 0) {
    final layerSize = totalHeight;
    return <LoveImageData>[
      for (var index = 0; index < totalWidth ~/ layerSize; index++)
        source.copyRegion(
          x: layerSize * index,
          y: 0,
          width: layerSize,
          height: layerSize,
        ),
    ];
  }

  if (totalHeight % totalWidth == 0) {
    final layerSize = totalWidth;
    return <LoveImageData>[
      for (var index = 0; index < totalHeight ~/ layerSize; index++)
        source.copyRegion(
          x: 0,
          y: layerSize * index,
          width: layerSize,
          height: layerSize,
        ),
    ];
  }

  throw LuaError('$symbol cannot extract volume layers from source ImageData');
}

/// Resolves a packed volume source into one image per volume layer.
Future<List<LoveImage>> _resolvePackedVolumeLayers(
  LibraryRegistrationContext context,
  Object? sourceValue, {
  required String symbol,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
  required LoveGraphicsFilterMode? defaultMipmapFilter,
  required double defaultMipmapSharpness,
}) async {
  final sourceImageData = await _resolveLayeredTextureLeafImageData(
    context,
    sourceValue,
    symbol: symbol,
  );
  final layerImageData = _extractPackedVolumeLayerImageData(
    sourceImageData,
    symbol: symbol,
  );
  return List<LoveImage>.unmodifiable([
    for (var layer = 0; layer < layerImageData.length; layer++)
      _resolveImageFromImageData(
        imageData: layerImageData[layer],
        source: 'VolumeLayer${layer + 1}',
        defaultFilter: defaultFilter,
        defaultMipmapFilter: defaultMipmapFilter,
        defaultMipmapSharpness: defaultMipmapSharpness,
        settings: settings,
      ),
  ]);
}

/// Builds one image that exposes [mipmaps] as manual mip levels.
LoveImage _buildManualMipmapImage({
  required List<LoveImage> mipmaps,
  required String symbol,
  required String textureType,
}) {
  if (mipmaps.isEmpty) {
    throw LuaError('$symbol requires at least one $textureType mipmap level');
  }

  final first = mipmaps.first;
  final mipmapData = <LoveImageData>[];
  for (var mip = 0; mip < mipmaps.length; mip++) {
    final image = mipmaps[mip];
    final data = image.imageData;
    if (data == null) {
      throw LuaError(
        '$symbol does not yet support non-readable manual mipmap sources for $textureType textures',
      );
    }

    final expectedWidth = first.pixelWidthAtMipmap(mip + 1);
    final expectedHeight = first.pixelHeightAtMipmap(mip + 1);
    if (data.width != expectedWidth || data.height != expectedHeight) {
      throw LuaError(
        '$symbol invalid manual mipmap dimensions for $textureType textures at mipmap ${mip + 1}',
      );
    }
    if (image.format != first.format) {
      throw LuaError(
        '$symbol expected every $textureType mipmap level to use the same pixel format',
      );
    }

    mipmapData.add(data);
  }

  return first.copyWith(
    mipmapCount: mipmaps.length,
    imageData: mipmapData.first,
    imageDataMipmaps: List<LoveImageData>.unmodifiable(mipmapData),
    preferImageDataRendering: true,
  );
}

/// Resolves one array/cube/volume slice source.
///
/// A slice can be a single leaf source or a table of manual mipmap sources for
/// that slice.
Future<LoveImage> _resolveLayeredTextureSliceImage(
  LibraryRegistrationContext context,
  Object? sourceValue, {
  required String symbol,
  required String textureType,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
  required LoveGraphicsFilterMode? defaultMipmapFilter,
  required double defaultMipmapSharpness,
}) async {
  final mipmapTable = _indexedSourceSequenceTable(sourceValue);
  if (mipmapTable == null) {
    return _resolveLayeredTextureLeafImage(
      context,
      sourceValue,
      symbol: symbol,
      settings: settings,
      defaultFilter: defaultFilter,
      defaultMipmapFilter: defaultMipmapFilter,
      defaultMipmapSharpness: defaultMipmapSharpness,
    );
  }

  final mipmapSources = _tableSequence(
    mipmapTable,
    symbol,
    emptyError: 'requires at least one $textureType mipmap source',
  );
  final mipmaps = <LoveImage>[];
  final leafSettings = _settingsWithoutMipmaps(settings);
  for (final mipmapSource in mipmapSources) {
    mipmaps.add(
      await _resolveLayeredTextureLeafImage(
        context,
        mipmapSource,
        symbol: symbol,
        settings: leafSettings,
        defaultFilter: defaultFilter,
        defaultMipmapFilter: defaultMipmapFilter,
        defaultMipmapSharpness: defaultMipmapSharpness,
      ),
    );
  }

  return _buildManualMipmapImage(
    mipmaps: mipmaps,
    symbol: symbol,
    textureType: textureType,
  );
}

/// Validates that layered texture [slices] are dimensionally compatible.
void _validateLayeredTextureSlices(
  List<LoveImage> slices, {
  required String symbol,
  required String textureType,
  int? expectedCount,
}) {
  if (slices.isEmpty) {
    throw LuaError('$symbol requires at least one $textureType slice');
  }
  if (expectedCount != null && slices.length != expectedCount) {
    throw LuaError(
      '$symbol requires exactly $expectedCount $textureType images',
    );
  }

  final first = slices.first;
  for (var index = 1; index < slices.length; index++) {
    final slice = slices[index];
    if (slice.pixelWidth != first.pixelWidth ||
        slice.pixelHeight != first.pixelHeight) {
      throw LuaError(
        '$symbol expected every $textureType slice to have matching pixel dimensions',
      );
    }
    if (slice.width != first.width || slice.height != first.height) {
      throw LuaError(
        '$symbol expected every $textureType slice to have matching logical dimensions',
      );
    }
    if (slice.format != first.format) {
      throw LuaError(
        '$symbol expected every $textureType slice to use the same pixel format',
      );
    }
    if (slice.mipmapCount != first.mipmapCount) {
      throw LuaError(
        '$symbol expected every $textureType slice to have the same mipmap count',
      );
    }

    for (var mip = 1; mip <= first.mipmapCount; mip++) {
      final firstMipmap = first.imageDataAtMipmap(mip);
      final sliceMipmap = slice.imageDataAtMipmap(mip);
      if (firstMipmap == null || sliceMipmap == null) {
        continue;
      }

      if (sliceMipmap.width != firstMipmap.width ||
          sliceMipmap.height != firstMipmap.height ||
          sliceMipmap.format != firstMipmap.format) {
        throw LuaError(
          '$symbol expected every $textureType slice mipmap level to match dimensions and format',
        );
      }
    }
  }
}

/// Builds the final layered [LoveImage] wrapper state from validated [slices].
LoveImage _buildLayeredTextureImage({
  required String source,
  required String textureType,
  required List<LoveImage> slices,
  required int layerCount,
  required int depth,
}) {
  final first = slices.first;
  return LoveImage(
    source: source,
    width: first.width,
    height: first.height,
    pixelWidth: first.pixelWidth,
    pixelHeight: first.pixelHeight,
    dpiScale: first.dpiScale,
    format: first.format,
    readable: slices.every((slice) => slice.readable),
    depth: depth,
    layerCount: layerCount,
    textureType: textureType,
    mipmapCount: first.mipmapCount,
    filter: first.filter,
    mipmapFilter: first.mipmapFilter,
    mipmapSharpness: first.mipmapSharpness,
    wrap: first.wrap,
    depthSampleMode: first.depthSampleMode,
    compressed: first.compressed,
    formatLinear: first.formatLinear,
    sliceImages: slices,
  );
}

/// Resolves the source table passed to `love.graphics.newVolumeImage`.
///
/// LOVE supports either a flat layer list or a table-of-layer-tables for
/// manual mipmaps.
Future<List<LoveImage>> _resolveVolumeTextureLayers(
  LibraryRegistrationContext context,
  Map<dynamic, dynamic> outerTable, {
  required String symbol,
  required Map<dynamic, dynamic>? settings,
  required LoveGraphicsDefaultFilter defaultFilter,
  required LoveGraphicsFilterMode? defaultMipmapFilter,
  required double defaultMipmapSharpness,
}) async {
  final firstEntryTable = _indexedSourceSequenceTable(
    _tableIndexedEntry(outerTable, 1),
  );
  if (firstEntryTable == null) {
    final sources = _tableSequence(
      outerTable,
      symbol,
      emptyError: 'requires at least one layer source',
    );
    final slices = <LoveImage>[];
    for (final source in sources) {
      slices.add(
        await _resolveLayeredTextureSliceImage(
          context,
          source,
          symbol: symbol,
          textureType: 'volume',
          settings: settings,
          defaultFilter: defaultFilter,
          defaultMipmapFilter: defaultMipmapFilter,
          defaultMipmapSharpness: defaultMipmapSharpness,
        ),
      );
    }
    return slices;
  }

  final mipmapTables = _tableSequence(
    outerTable,
    symbol,
    emptyError: 'requires at least one mipmap layer table',
  );
  final leafSettings = _settingsWithoutMipmaps(settings);
  final perLayerMipmaps = <List<LoveImage>>[];
  int? expectedLayerCount;

  for (var mip = 0; mip < mipmapTables.length; mip++) {
    final mipmapTable = _indexedSourceSequenceTable(mipmapTables[mip]);
    if (mipmapTable == null) {
      throw LuaError(
        '$symbol manual volume mipmap entries must be tables of layer sources',
      );
    }

    final layerSources = _tableSequence(
      mipmapTable,
      symbol,
      emptyError:
          'requires at least one layer source for each manual mipmap level',
    );
    expectedLayerCount ??= layerSources.length;
    if (layerSources.length != expectedLayerCount) {
      throw LuaError(
        '$symbol expected every manual volume mipmap level to contain the same number of layers',
      );
    }

    if (perLayerMipmaps.isEmpty) {
      for (var index = 0; index < layerSources.length; index++) {
        perLayerMipmaps.add(<LoveImage>[]);
      }
    }

    for (var layer = 0; layer < layerSources.length; layer++) {
      perLayerMipmaps[layer].add(
        await _resolveLayeredTextureLeafImage(
          context,
          layerSources[layer],
          symbol: symbol,
          settings: leafSettings,
          defaultFilter: defaultFilter,
          defaultMipmapFilter: defaultMipmapFilter,
          defaultMipmapSharpness: defaultMipmapSharpness,
        ),
      );
    }
  }

  return List<LoveImage>.unmodifiable(
    perLayerMipmaps
        .map(
          (mipmaps) => _buildManualMipmapImage(
            mipmaps: mipmaps,
            symbol: symbol,
            textureType: 'volume',
          ),
        )
        .toList(growable: false),
  );
}

/// Returns copies of [image]'s slice images with selected sampler state
/// overrides applied.
List<LoveImage>? _copyImageSliceImages(
  LoveImage image, {
  LoveGraphicsDefaultFilter? filter,
  bool clearMipmapFilter = false,
  LoveGraphicsFilterMode? mipmapFilter,
  double? mipmapSharpness,
  LoveGraphicsWrap? wrap,
  bool clearDepthSampleMode = false,
  LoveGraphicsCompareMode? depthSampleMode,
}) {
  final slices = image.sliceImages;
  if (slices == null) {
    return null;
  }

  return List<LoveImage>.unmodifiable(
    slices
        .map((slice) {
          return slice.copyWith(
            filter: filter ?? slice.filter,
            clearMipmapFilter: clearMipmapFilter,
            mipmapFilter: clearMipmapFilter
                ? null
                : (mipmapFilter ?? slice.mipmapFilter),
            mipmapSharpness: mipmapSharpness ?? slice.mipmapSharpness,
            wrap: wrap ?? slice.wrap,
            clearDepthSampleMode: clearDepthSampleMode,
            depthSampleMode: clearDepthSampleMode
                ? null
                : (depthSampleMode ?? slice.depthSampleMode),
          );
        })
        .toList(growable: false),
  );
}

/// Returns the layer index that should be drawn directly for [image].
///
/// Only array textures are currently drawable in the runtime's direct draw
/// path.
int? _directTextureDrawLayer(LoveImage image, LoveQuad? quad, String symbol) {
  switch (image.textureType) {
    case '2d':
      return null;
    case 'array':
      final layer = quad?.layer ?? 0;
      _validateLayeredTextureDraw(image, layer, symbol);
      return layer;
    case 'volume':
      throw LuaError(
        '$symbol does not yet support drawing volume textures in the current runtime',
      );
    case 'cube':
      throw LuaError(
        '$symbol does not yet support drawing cube textures in the current runtime',
      );
    default:
      return null;
  }
}

/// Validates that [image] can be drawn through `love.graphics.drawLayer`.
void _validateLayeredTextureDraw(
  LoveImage image,
  int layerIndex,
  String symbol,
) {
  if (layerIndex < 0) {
    throw LuaError('$symbol layer index must be >= 1');
  }

  switch (image.textureType) {
    case 'array':
      final slices = image.sliceImages;
      if (slices == null || slices.isEmpty) {
        throw LuaError(
          '$symbol does not yet support drawing array Canvas textures in the current runtime',
        );
      }
      if (layerIndex >= slices.length) {
        throw LuaError(
          '$symbol invalid array texture layer index ${layerIndex + 1}',
        );
      }
      return;
    case 'volume':
      throw LuaError(
        '$symbol does not yet support drawing volume textures in the current runtime',
      );
    case 'cube':
      throw LuaError(
        '$symbol does not yet support drawing cube textures in the current runtime',
      );
    default:
      throw LuaError('$symbol requires an array texture at argument 1');
  }
}

/// Binds `love.graphics.drawLayer`.
///
/// This currently supports array textures by selecting one slice to draw
/// through the standard image command path.
LoveApiImplementation _bindGraphicsDrawLayer(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.graphics.drawLayer';
    final texture = _requireImage(args, 0, symbol);
    final layerIndex = _requireRoundedInt(args, 1, symbol) - 1;
    final quad = _quadIfPresent(_valueAt(args, 2));
    final startIndex = quad == null ? 2 : 3;
    final resolvedTexture = switch (texture) {
      final LoveCanvas canvas => canvas.snapshot(),
      _ => texture,
    };

    _validateLayeredTextureDraw(resolvedTexture, layerIndex, symbol);

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
          symbol,
        ),
        image: resolvedTexture,
        quad: quad,
        layer: layerIndex,
      ),
    );
    return null;
  };
}

/// Binds `love.graphics.newArrayImage`.
///
/// The first argument is a table of slice sources, where each slice may itself
/// be a single source or a manual mipmap table.
LoveApiImplementation _bindGraphicsNewArrayImage(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.graphics.newArrayImage';
    final sliceTable = _tableIfPresent(_valueAt(args, 0));
    if (sliceTable == null) {
      throw LuaError('$symbol expected a table of slice sources at argument 1');
    }

    final settings = args.length >= 2
        ? _optionalTableTarget(_valueAt(args, 1))?.$2
        : null;
    final sources = _tableSequence(
      sliceTable,
      symbol,
      emptyError: 'requires at least one slice source',
    );
    final slices = <LoveImage>[];
    for (final source in sources) {
      slices.add(
        await _resolveLayeredTextureSliceImage(
          context,
          source,
          symbol: symbol,
          textureType: 'array',
          settings: settings,
          defaultFilter: runtime.graphics.defaultFilter,
          defaultMipmapFilter: runtime.graphics.defaultMipmapFilter,
          defaultMipmapSharpness: runtime.graphics.defaultMipmapSharpness,
        ),
      );
    }

    _validateLayeredTextureSlices(slices, symbol: symbol, textureType: 'array');

    return _wrapImage(
      context,
      _buildLayeredTextureImage(
        source: 'ArrayImage',
        textureType: 'array',
        slices: slices,
        layerCount: slices.length,
        depth: 1,
      ),
    );
  };
}

/// Binds `love.graphics.newVolumeImage`.
///
/// LOVE accepts either a packed source image or a table of per-layer sources,
/// with optional manual mipmap tables for each layer.
LoveApiImplementation _bindGraphicsNewVolumeImage(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.graphics.newVolumeImage';
    final first = _valueAt(args, 0);

    final settings = args.length >= 2
        ? _optionalTableTarget(_valueAt(args, 1))?.$2
        : null;

    if (await _isLayeredTextureLeafSourceValue(
      context,
      first,
      symbol: symbol,
    )) {
      final slices = await _resolvePackedVolumeLayers(
        context,
        first,
        symbol: symbol,
        settings: settings,
        defaultFilter: runtime.graphics.defaultFilter,
        defaultMipmapFilter: runtime.graphics.defaultMipmapFilter,
        defaultMipmapSharpness: runtime.graphics.defaultMipmapSharpness,
      );

      _validateLayeredTextureSlices(
        slices,
        symbol: symbol,
        textureType: 'volume',
      );

      return _wrapImage(
        context,
        _buildLayeredTextureImage(
          source: 'VolumeImage',
          textureType: 'volume',
          slices: slices,
          layerCount: 1,
          depth: slices.length,
        ),
      );
    }

    final layerTable = _tableIfPresent(first);
    if (layerTable == null) {
      throw LuaError(
        '$symbol expected a volume source or table of layer sources at argument 1',
      );
    }

    final slices = await _resolveVolumeTextureLayers(
      context,
      layerTable,
      symbol: symbol,
      settings: settings,
      defaultFilter: runtime.graphics.defaultFilter,
      defaultMipmapFilter: runtime.graphics.defaultMipmapFilter,
      defaultMipmapSharpness: runtime.graphics.defaultMipmapSharpness,
    );

    _validateLayeredTextureSlices(
      slices,
      symbol: symbol,
      textureType: 'volume',
    );

    return _wrapImage(
      context,
      _buildLayeredTextureImage(
        source: 'VolumeImage',
        textureType: 'volume',
        slices: slices,
        layerCount: 1,
        depth: slices.length,
      ),
    );
  };
}

/// Binds `love.graphics.newCubeImage`.
///
/// LOVE accepts a packed cubemap source image or a table of six face sources.
/// The table form also supports packed cubemap mipmap atlases.
LoveApiImplementation _bindGraphicsNewCubeImage(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) async {
    const symbol = 'love.graphics.newCubeImage';
    final first = _valueAt(args, 0);
    final settings = args.length >= 2
        ? _optionalTableTarget(_valueAt(args, 1))?.$2
        : null;

    if (await _isLayeredTextureLeafSourceValue(
      context,
      first,
      symbol: symbol,
    )) {
      final faces = await _resolvePackedCubemapFaces(
        context,
        first,
        symbol: symbol,
        settings: settings,
        defaultFilter: runtime.graphics.defaultFilter,
        defaultMipmapFilter: runtime.graphics.defaultMipmapFilter,
        defaultMipmapSharpness: runtime.graphics.defaultMipmapSharpness,
      );
      return _wrapImage(
        context,
        _buildLayeredTextureImage(
          source: 'CubeImage',
          textureType: 'cube',
          slices: faces,
          layerCount: 6,
          depth: 1,
        ),
      );
    }

    final faceTable = _tableIfPresent(first);
    if (faceTable == null) {
      throw LuaError(
        '$symbol expected a cubemap source or table of 6 face sources at argument 1',
      );
    }

    final sources = _tableSequence(
      faceTable,
      symbol,
      emptyError: 'requires 6 face sources',
    );
    List<LoveImage> faces;
    if (await _isPackedCubemapMipmapTable(context, sources, symbol: symbol)) {
      faces = await _resolvePackedCubemapMipmappedFaces(
        context,
        sources,
        symbol: symbol,
        settings: settings,
        defaultFilter: runtime.graphics.defaultFilter,
        defaultMipmapFilter: runtime.graphics.defaultMipmapFilter,
        defaultMipmapSharpness: runtime.graphics.defaultMipmapSharpness,
      );
    } else {
      final resolvedFaces = <LoveImage>[];
      for (final source in sources) {
        resolvedFaces.add(
          await _resolveLayeredTextureSliceImage(
            context,
            source,
            symbol: symbol,
            textureType: 'cube',
            settings: settings,
            defaultFilter: runtime.graphics.defaultFilter,
            defaultMipmapFilter: runtime.graphics.defaultMipmapFilter,
            defaultMipmapSharpness: runtime.graphics.defaultMipmapSharpness,
          ),
        );
      }
      faces = resolvedFaces;
    }

    _validateLayeredTextureSlices(
      faces,
      symbol: symbol,
      textureType: 'cube',
      expectedCount: 6,
    );
    if (faces.first.pixelWidth != faces.first.pixelHeight) {
      throw LuaError('$symbol cube faces must have equal width and height');
    }

    return _wrapImage(
      context,
      _buildLayeredTextureImage(
        source: 'CubeImage',
        textureType: 'cube',
        slices: faces,
        layerCount: 6,
        depth: 1,
      ),
    );
  };
}
