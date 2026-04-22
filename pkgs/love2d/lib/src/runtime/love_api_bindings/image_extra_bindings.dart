part of '../love_api_bindings.dart';

final Expando<bool> _loveImageExtrasInstalled = Expando<bool>(
  'love2dImageExtrasInstalled',
);

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
