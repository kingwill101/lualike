part of '../love_api_bindings.dart';

/// Binds `love.graphics.present`.
///
/// Frame submission is managed by the Flame and Flutter harness, so this is a
/// deliberate no-op shim that lets Lua code call it without error.
LoveApiImplementation _bindGraphicsPresent(LibraryRegistrationContext context) {
  return (args) => null;
}

/// Binds `love.graphics.flushBatch`.
///
/// Automatic draw-call batching is handled internally, so there is no explicit
/// batch to flush in this runtime.
LoveApiImplementation _bindGraphicsFlushBatch(
  LibraryRegistrationContext context,
) {
  return (args) => null;
}

/// Binds `love.graphics.discard`.
///
/// This is a GPU-driver performance hint with no observable effect on output,
/// so it is shimmed as a no-op.
LoveApiImplementation _bindGraphicsDiscard(LibraryRegistrationContext context) {
  return (args) => null;
}

/// Binds `love.graphics.isActive`.
///
/// The runtime cannot be partially initialized, so this always reports `true`.
LoveApiImplementation _bindGraphicsIsActive(
  LibraryRegistrationContext context,
) {
  return (args) => true;
}

/// Binds `love.graphics.isCreated`.
///
/// Upstream exposes this lightweight initialization-state query even though the
/// vendored LOVE API inventory omits it. Once the runtime is installed, the
/// graphics context always exists, so this reports `true`.
LoveApiImplementation _bindGraphicsIsCreated(
  LibraryRegistrationContext context,
) {
  return (args) => true;
}

/// Binds `love.graphics.isGammaCorrect`.
///
/// The Flutter and Flame backend does not currently enable automatic gamma
/// correction, so this returns `false`.
LoveApiImplementation _bindGraphicsIsGammaCorrect(
  LibraryRegistrationContext context,
) {
  return (args) => false;
}

/// Supported texture-type flags returned by `love.graphics.getTextureTypes`.
///
/// Only 2D textures are fully supported in the current runtime. Array, cube,
/// and volume textures may be tracked in state but are not fully rasterized.
const Map<String, bool> _loveGraphicsTextureTypeSupport = <String, bool>{
  '2d': true,
  'array': true,
  'cube': false,
  'volume': false,
};

/// Binds `love.graphics.getTextureTypes`.
///
/// LOVE optionally accepts a destination table to populate, so this binding
/// preserves that in-place fill behavior.
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

/// Binds `love.graphics.validateShader`.
///
/// Validation goes through the same source-resolution path as `newShader`.
/// Since the Flutter backend does not expose a general-purpose GLSL compiler,
/// this reports success only for the compatibility-emulated shader subset that
/// the runtime can execute and returns `(false, message)` for unsupported
/// runtime shader source.
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

    final validationError = await _registeredFragmentShaderValidationError(
      context,
      shader,
    );
    if (validationError != null) {
      return Value.multi(<Object?>[false, validationError]);
    }

    // Mirrors upstream by returning a single true value on success.
    return true;
  };
}

/// Binds `love.graphics.drawInstanced`.
///
/// Hardware geometry instancing is emulated by replaying the queued mesh draw
/// command multiple times during rasterization while preserving a single queued
/// draw command and draw-call statistic.
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

/// Returns the validated stencil action for [value].
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

/// Binds `love.graphics.stencil`.
///
/// This records stencil-writing draw commands by replaying the supplied
/// callback with temporary stencil-write state enabled. CPU readback paths such
/// as `Canvas:newImageData` and `captureScreenshot` then replay the commands
/// against a software stencil buffer.
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
