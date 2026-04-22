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

// love.graphics.isCreated
// Upstream exposes this lightweight initialization-state query even though the
// vendored love-api inventory omits it. The runtime always has a graphics
// context once installed, so this reports true.
LoveApiImplementation _bindGraphicsIsCreated(
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
  'array': true,
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
// Validates shader source through the same input-resolution path as newShader.
// The Flutter backend does not have a general-purpose GLSL compiler, so we
// report success only for the compatibility-emulated shader subset that the
// runtime can actually execute and return (false, message) for unsupported
// runtime shader source.
LoveApiImplementation _bindGraphicsValidateShader(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.graphics.validateShader';
    if (args.length < 2) {
      throw LuaError(
        '$symbol requires at least 2 arguments '
        '(gles: boolean, code: string)',
      );
    }

    final gles = _requireBoolean(args, 0, symbol);

    final shader = await _createShaderFromSourceArguments(
      context,
      firstValue: _valueAt(args, 1),
      secondValue: args.length >= 3 ? _valueAt(args, 2) : null,
      symbol: symbol,
      firstArgumentIndex: 2,
      gles: gles,
    );
    final unsupportedMessage = _unsupportedShaderSourceMessage(
      shader,
      symbol: symbol,
    );
    if (unsupportedMessage != null) {
      return Value.multi(<Object?>[false, unsupportedMessage]);
    }

    // Mirrors upstream by returning a single true value on success.
    return true;
  };
}

// love.graphics.drawInstanced(mesh, count [, drawparams...])
//
// Hardware geometry instancing is emulated by replaying the queued Mesh command
// multiple times during rasterization while preserving a single queued draw
// command and drawcall stat. Per-instance attributes are not yet rasterized.
LoveApiImplementation _bindGraphicsDrawInstanced(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.graphics.drawInstanced';
    final mesh = _requireMesh(args, 0, symbol);
    final instanceCount = _requireRoundedInt(args, 1, symbol);
    _queueMeshDrawCommand(
      runtime,
      mesh: mesh,
      args: args,
      transformIndex: 2,
      symbol: symbol,
      instanceCount: instanceCount,
    );
    return null;
  };
}

// love.graphics.stencil(stencilfunction [, action [, value [, keepvals]]])
//
LoveGraphicsStencilAction _stencilAction(String value, String symbol) {
  return switch (value) {
    'replace' => LoveGraphicsStencilAction.replace,
    'increment' => LoveGraphicsStencilAction.increment,
    'decrement' => LoveGraphicsStencilAction.decrement,
    'incrementwrap' => LoveGraphicsStencilAction.incrementWrap,
    'decrementwrap' => LoveGraphicsStencilAction.decrementWrap,
    'invert' => LoveGraphicsStencilAction.invert,
    _ => throw LuaError('$symbol invalid stencil draw action "$value"'),
  };
}

// Records stencil-writing draw commands by replaying the supplied callback with
// temporary stencil-write state enabled. CPU readback paths such as
// Canvas:newImageData and captureScreenshot then replay the commands against a
// software stencil buffer.
LoveApiImplementation _bindGraphicsStencil(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for love.graphics.stencil');
  }

  return (args) async {
    const symbol = 'love.graphics.stencil';
    final callback = _requireCallable(args, 0, symbol);
    final action = args.length >= 2 && _rawValue(args[1]) != null
        ? _stencilAction(_requireString(args, 1, symbol), symbol)
        : LoveGraphicsStencilAction.replace;
    final value = args.length >= 3 ? _requireRoundedInt(args, 2, symbol) : 1;
    final keepArg = args.length >= 4 ? _rawValue(args[3]) : null;

    if (keepArg == null || keepArg == false) {
      runtime.graphics.clearStencil();
    } else if (keepArg is num) {
      runtime.graphics.clearStencil(keepArg.round());
    } else if (keepArg is! bool) {
      throw LuaError('$symbol expected a boolean or number at argument 4');
    }

    runtime.graphics.beginStencilWrite(action, value);
    try {
      await interpreter.callFunction(
        callback,
        const <Object?>[],
        debugName: symbol,
        debugNameWhat: 'function',
      );
    } finally {
      runtime.graphics.endStencilWrite();
    }

    return null;
  };
}
