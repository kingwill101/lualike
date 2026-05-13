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

  final graphicsTable = _graphicsExtraModuleTable(runtime);
  if (graphicsTable == null) {
    return;
  }

  final context = LibraryContext(
    environment: runtime.getCurrentEnv(),
    interpreter: runtime,
  );
  final builder = BuiltinFunctionBuilder(context);

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

  _loveGraphicsExtrasInstalled[runtime] = true;
}

/// Returns the current `love.graphics` module table when it is available.
Map<dynamic, dynamic>? _graphicsExtraModuleTable(LuaRuntime runtime) {
  final love = runtime.getCurrentEnv().get('love');
  final loveTable = love is Value ? love.raw : love;
  if (loveTable is! Map<dynamic, dynamic>) {
    return null;
  }

  final graphics = loveTable['graphics'];
  final graphicsTable = graphics is Value ? graphics.raw : graphics;
  if (graphicsTable is! Map<dynamic, dynamic>) {
    return null;
  }

  return graphicsTable;
}
