part of '../love_api_bindings.dart';

// love.graphics.present
// Frame submission is managed by the Flame/Flutter harness, so this is a
// deliberate no-op shim that lets Lua code call it without error.
LoveApiImplementation _bindGraphicsPresent(LibraryRegistrationContext context) {
  return (args) => null;
}

// love.graphics.flushBatch
// Automatic draw-call batching is handled internally; there is no explicit
// batch to flush in this runtime, so this is a no-op shim.
LoveApiImplementation _bindGraphicsFlushBatch(
  LibraryRegistrationContext context,
) {
  return (args) => null;
}

// love.graphics.discard([discardcolor, discardstencil])
// This is a GPU-driver performance hint with no observable effect on output.
// Shimmed as a no-op so games that call it don't error.
LoveApiImplementation _bindGraphicsDiscard(LibraryRegistrationContext context) {
  return (args) => null;
}

// love.graphics.isActive
// Returns whether the graphics module is currently active (i.e. the window
// is open and the render context is live).  We always return true since the
// runtime cannot be partially initialised.
LoveApiImplementation _bindGraphicsIsActive(
  LibraryRegistrationContext context,
) {
  return (args) => true;
}

// love.graphics.isGammaCorrect
// Returns whether gamma-correct rendering is enabled.  The Flutter/Flame
// backend does not currently enable automatic gamma correction, so this
// returns false.
LoveApiImplementation _bindGraphicsIsGammaCorrect(
  LibraryRegistrationContext context,
) {
  return (args) => false;
}

// love.graphics.getTextureTypes
// Returns a table of supported texture types.  Only 2D textures are fully
// supported in the current runtime; array / cube / volume textures are
// tracked in state but cannot be rasterised yet.
const Map<String, bool> _loveGraphicsTextureTypeSupport = <String, bool>{
  '2d': true,
  'array': false,
  'cube': false,
  'volume': false,
};

LoveApiImplementation _bindGraphicsGetTextureTypes(
  LibraryRegistrationContext context,
) {
  return (args) {
    final target = _optionalTableTarget(_valueAt(args, 0));
    final table = _fillGraphicsInfoTable(
      target: target?.$2,
      source: _loveGraphicsTextureTypeSupport,
    );
    return target?.$1 ?? Value(table);
  };
}

// love.graphics.validateShader(gles, code)
// love.graphics.validateShader(gles, pixelcode, vertexcode)
//
// Validates GLSL shader source.  No GLSL compiler is available in the Dart
// runtime, so this shim always reports the shader as valid.  Games that use
// this function to guard optional shader features will work correctly; games
// that rely on the error message to diagnose broken shaders will not receive
// compile diagnostics.
LoveApiImplementation _bindGraphicsValidateShader(
  LibraryRegistrationContext context,
) {
  return (args) {
    // Validate argument count: at minimum (gles, code).
    if (args.length < 2) {
      throw LuaError(
        'love.graphics.validateShader requires at least 2 arguments '
        '(gles: boolean, code: string)',
      );
    }
    // Return (true, nil) — always valid in this shim.
    return Value.multi(<Object?>[true, null]);
  };
}

// love.graphics.captureScreenshot(callback)
//
// Enqueues an async screenshot capture; the callback is invoked with an
// ImageData object once the current frame has finished rendering.  This
// requires deep integration with the host's render pipeline and is not
// yet implemented.
LoveApiImplementation _bindGraphicsCaptureScreenshot(
  LibraryRegistrationContext context,
) {
  return (args) => loveApiUnimplemented('love.graphics.captureScreenshot');
}

// love.graphics.drawInstanced(mesh, count [, drawparams...])
//
// Hardware geometry instancing requires per-instance vertex attributes and
// shader support that is not yet available in this runtime.
LoveApiImplementation _bindGraphicsDrawInstanced(
  LibraryRegistrationContext context,
) {
  return (args) => loveApiUnimplemented('love.graphics.drawInstanced');
}

// love.graphics.drawLayer(texture, layerindex [, drawparams...])
//
// Drawing individual layers of an Array or Volume texture requires multi-
// layer texture support which is not yet rasterised by this runtime.
LoveApiImplementation _bindGraphicsDrawLayer(
  LibraryRegistrationContext context,
) {
  return (args) => loveApiUnimplemented('love.graphics.drawLayer');
}

// love.graphics.newArrayImage(slices [, settings])
//
// Array textures are tracked in state but cannot be decoded or rasterised
// yet.
LoveApiImplementation _bindGraphicsNewArrayImage(
  LibraryRegistrationContext context,
) {
  return (args) => loveApiUnimplemented('love.graphics.newArrayImage');
}

// love.graphics.newVolumeImage(layers [, settings])
//
// Volume textures are tracked in state but cannot be decoded or rasterised
// yet.
LoveApiImplementation _bindGraphicsNewVolumeImage(
  LibraryRegistrationContext context,
) {
  return (args) => loveApiUnimplemented('love.graphics.newVolumeImage');
}

// love.graphics.newCubeImage(filename | slices [, settings])
//
// Cubemap textures are tracked in state but cannot be decoded or rasterised
// yet.
LoveApiImplementation _bindGraphicsNewCubeImage(
  LibraryRegistrationContext context,
) {
  return (args) => loveApiUnimplemented('love.graphics.newCubeImage');
}

// love.graphics.stencil(stencilfunction [, action [, value [, keepvals]]])
//
// Drawing into the stencil buffer requires stencil-aware command types and
// host-side pipeline support which are not yet implemented.
LoveApiImplementation _bindGraphicsStencil(LibraryRegistrationContext context) {
  return (args) => loveApiUnimplemented('love.graphics.stencil');
}
