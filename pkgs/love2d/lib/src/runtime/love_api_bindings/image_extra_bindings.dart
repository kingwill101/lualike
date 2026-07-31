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

  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveImageExtrasInstalled,
    moduleName: 'image',
    install: _installLoveImageExtraBindings,
  );
}

void _installLoveImageExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> imageTable,
) {
  final context = loveBindingContext(runtime);
  final builder = loveBindingBuilderForContext(context);

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
}
