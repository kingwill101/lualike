part of '../love_api_bindings.dart';

/// Whether extra graphics bindings have already been installed for a runtime.
final Expando<bool> _loveGraphicsExtrasInstalled = Expando<bool>(
  'love2dGraphicsExtrasInstalled',
);

/// Installs graphics bindings that wrap precompiled Flutter fragment assets as
/// LOVE shaders.
///
/// This keeps the public `love.graphics.newShader` path focused on supported
/// source translation while still letting examples and compatibility layers
/// bind against shader assets that Flutter has already compiled.
void installLoveGraphicsExtraBindings(LuaRuntime runtime) {
  if (_loveGraphicsExtrasInstalled[runtime] == true) {
    return;
  }

  loveInstallModuleBindings(
    runtime: runtime,
    installed: _loveGraphicsExtrasInstalled,
    moduleName: 'graphics',
    install: _installLoveGraphicsExtraBindings,
  );
}

void _installLoveGraphicsExtraBindings(
  LuaRuntime runtime,
  Map<dynamic, dynamic> graphicsTable,
) {
  final context = loveBindingContext(runtime);
  final builder = loveBindingBuilderForContext(context);

  graphicsTable['_newRegisteredFragmentShader'] = Value(
    builder.create((args) async {
      const symbol = 'love.graphics._newRegisteredFragmentShader';
      final assetKey = _requireString(args, 0, symbol);
      final source = _requireString(args, 1, symbol);
      final shader = LoveShader(
        pixelCode: source,
        kind: LoveShaderKind.generic,
        flutterFragmentAssetKey: assetKey,
      );
      final validationError = await _registeredFragmentShaderValidationError(
        context,
        shader,
      );
      if (validationError != null) {
        throw LuaError(validationError);
      }
      return _wrapShader(context, shader);
    }),
    functionName: '_newRegisteredFragmentShader',
  );
}
