part of '../love_api_bindings.dart';

Value _wrapCompressedImageData(
  LibraryRegistrationContext context,
  LoveCompressedImageData imageData,
) {
  final cached = _loveCompressedImageDataWrapperCache[imageData];
  if (cached != null) {
    return cached;
  }

  final builder = BuiltinFunctionBuilder(context);
  const hierarchy = <String>{'CompressedImageData', 'Data', 'Object'};
  final table = ValueClass.table(<Object?, Object?>{
    _loveCompressedImageDataObjectKey: imageData,
    'clone': Value(
      builder.create((args) {
        return _wrapCompressedImageData(
          context,
          _requireCompressedImageData(
            args,
            0,
            'CompressedImageData:clone',
          ).clone(),
        );
      }),
      functionName: 'clone',
    ),
    'getDimensions': Value(
      builder.create((args) {
        final imageData = _requireCompressedImageData(
          args,
          0,
          'CompressedImageData:getDimensions',
        );
        final level = args.length >= 2
            ? _textureMipmapLevel(args, 1, 'CompressedImageData:getDimensions')
            : 1;
        return Value.multi(<Object?>[
          imageData.getWidth(level),
          imageData.getHeight(level),
        ]);
      }),
      functionName: 'getDimensions',
    ),
    'getFormat': Value(
      builder.create(
        (args) => _requireCompressedImageData(
          args,
          0,
          'CompressedImageData:getFormat',
        ).format,
      ),
      functionName: 'getFormat',
    ),
    'getHeight': Value(
      builder.create((args) {
        final imageData = _requireCompressedImageData(
          args,
          0,
          'CompressedImageData:getHeight',
        );
        final level = args.length >= 2
            ? _textureMipmapLevel(args, 1, 'CompressedImageData:getHeight')
            : 1;
        return imageData.getHeight(level);
      }),
      functionName: 'getHeight',
    ),
    'getMipmapCount': Value(
      builder.create(
        (args) => _requireCompressedImageData(
          args,
          0,
          'CompressedImageData:getMipmapCount',
        ).mipmapCount,
      ),
      functionName: 'getMipmapCount',
    ),
    'getWidth': Value(
      builder.create((args) {
        final imageData = _requireCompressedImageData(
          args,
          0,
          'CompressedImageData:getWidth',
        );
        final level = args.length >= 2
            ? _textureMipmapLevel(args, 1, 'CompressedImageData:getWidth')
            : 1;
        return imageData.getWidth(level);
      }),
      functionName: 'getWidth',
    ),
    'release': Value(
      builder.create((args) {
        final imageData = _requireCompressedImageData(
          args,
          0,
          'Object:release',
        );
        if (_loveDataReleased[imageData] == true) {
          return false;
        }

        _loveDataReleased[imageData] = true;
        return true;
      }),
      functionName: 'release',
    ),
    'type': Value(
      builder.create((args) {
        _requireCompressedImageData(args, 0, 'Object:type');
        return 'CompressedImageData';
      }),
      functionName: 'type',
    ),
    'typeOf': Value(
      builder.create((args) {
        _requireCompressedImageData(args, 0, 'Object:typeOf');
        final queried = _requireString(args, 1, 'Object:typeOf');
        return hierarchy.contains(queried);
      }),
      functionName: 'typeOf',
    ),
  });
  _loveCompressedImageDataWrapperCache[imageData] = table;
  return table;
}
