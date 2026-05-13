part of '../love_api_bindings.dart';

/// Installation state for the extra `love.image` bindings on each runtime.
final Expando<bool> _loveImageExtrasInstalled = Expando<bool>(
  'love2dImageExtrasInstalled',
);

/// Installs the non-core `love.image` compatibility bindings on [runtime].
///
/// This currently exposes `love.image.newCubeFaces`, matching the helper API
/// used to split packed cubemap source data into six [LoveImageData] faces.
void installLoveImageExtraBindings(LuaRuntime runtime) {
  if (_loveImageExtrasInstalled[runtime] == true) {
    return;
  }

  final imageTable = _imageModuleTable(runtime);
  if (imageTable == null) {
    return;
  }

  final context = LibraryContext(
    environment: runtime.getCurrentEnv(),
    interpreter: runtime,
  );
  final builder = BuiltinFunctionBuilder(context);

  imageTable['newCubeFaces'] = Value(
    builder.create((args) {
      const symbol = 'love.image.newCubeFaces';
      final imageData = _requireImageData(args, 0, symbol);
      final faces = _extractPackedCubemapFaceImageData(
        imageData,
        symbol: symbol,
      );
      return Value.multi(<Object?>[
        for (final face in faces) _wrapImageData(context, face),
      ]);
    }),
    functionName: 'newCubeFaces',
  );

  _loveImageExtrasInstalled[runtime] = true;
}

/// Returns the raw `love.image` module table from [runtime], if available.
Map<dynamic, dynamic>? _imageModuleTable(LuaRuntime runtime) {
  final love = runtime.getCurrentEnv().get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final image = loveTable['image'];
  final imageTable = image is Value ? image.raw : image;
  if (imageTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return imageTable;
}
