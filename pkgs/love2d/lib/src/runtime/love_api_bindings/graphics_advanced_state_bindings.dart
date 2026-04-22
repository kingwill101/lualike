part of '../love_api_bindings.dart';

/// Binds `love.graphics.setDepthMode`.
///
/// Calling this with no arguments, or with `nil`, disables depth testing,
/// which is equivalent to `setDepthMode('always', false)`. The depth state is
/// tracked so it survives `push('all')`, `pop()`, and `reset()` even though
/// the host renderer does not currently perform hardware depth testing.
LoveApiImplementation _bindGraphicsSetDepthMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty || _rawValue(args.first) == null) {
      runtime.graphics.depthMode = LoveGraphicsCompareMode.always;
      runtime.graphics.depthWrite = false;
      return null;
    }

    runtime.graphics.depthMode = _compareMode(
      _requireString(args, 0, 'love.graphics.setDepthMode'),
      'love.graphics.setDepthMode',
    );
    runtime.graphics.depthWrite = _requireBoolean(
      args,
      1,
      'love.graphics.setDepthMode',
    );
    return null;
  };
}

/// Binds `love.graphics.getDepthMode`.
///
/// The returned values match LOVE's `(compareMode, write)` tuple and fall back
/// to `('always', false)` when depth testing is disabled.
LoveApiImplementation _bindGraphicsGetDepthMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    _compareModeName(runtime.graphics.depthMode),
    runtime.graphics.depthWrite,
  ]);
}

/// Binds `love.graphics.setStencilTest`.
///
/// Calling this with no arguments, or with `nil`, disables the stencil test,
/// which is equivalent to `setStencilTest('always', 0)`. The stencil state is
/// stored for compatibility even though the host renderer does not yet perform
/// hardware stencil testing.
LoveApiImplementation _bindGraphicsSetStencilTest(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty || _rawValue(args.first) == null) {
      runtime.graphics.stencilCompare = LoveGraphicsCompareMode.always;
      runtime.graphics.stencilValue = 0;
      return null;
    }

    runtime.graphics.stencilCompare = _compareMode(
      _requireString(args, 0, 'love.graphics.setStencilTest'),
      'love.graphics.setStencilTest',
    );
    runtime.graphics.stencilValue = _requireRoundedInt(
      args,
      1,
      'love.graphics.setStencilTest',
    );
    return null;
  };
}

/// Binds `love.graphics.getStencilTest`.
///
/// The returned values match LOVE's `(compareMode, referenceValue)` tuple and
/// fall back to `('always', 0)` when stencil testing is disabled.
LoveApiImplementation _bindGraphicsGetStencilTest(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    _compareModeName(runtime.graphics.stencilCompare),
    runtime.graphics.stencilValue,
  ]);
}

/// Binds `love.graphics.setFrontFaceWinding`.
///
/// This sets which vertex winding is considered front-facing for mesh culling.
/// Accepted values are `ccw` and `cw`.
LoveApiImplementation _bindGraphicsSetFrontFaceWinding(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.graphics.setFrontFaceWinding';
    final winding = _requireString(args, 0, symbol);
    runtime.graphics.frontFaceWinding = switch (winding) {
      'ccw' => LoveGraphicsVertexWinding.ccw,
      'cw' => LoveGraphicsVertexWinding.cw,
      _ => throw LuaError('$symbol invalid vertex winding "$winding"'),
    };
    return null;
  };
}

/// Binds `love.graphics.getFrontFaceWinding`.
LoveApiImplementation _bindGraphicsGetFrontFaceWinding(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => switch (runtime.graphics.frontFaceWinding) {
    LoveGraphicsVertexWinding.ccw => 'ccw',
    LoveGraphicsVertexWinding.cw => 'cw',
  };
}

/// Binds `love.graphics.setMeshCullMode`.
///
/// Accepted values are `none`, `back`, and `front`.
LoveApiImplementation _bindGraphicsSetMeshCullMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    const symbol = 'love.graphics.setMeshCullMode';
    final mode = _requireString(args, 0, symbol);
    runtime.graphics.meshCullMode = switch (mode) {
      'none' => LoveGraphicsCullMode.none,
      'back' => LoveGraphicsCullMode.back,
      'front' => LoveGraphicsCullMode.front,
      _ => throw LuaError('$symbol invalid cull mode "$mode"'),
    };
    return null;
  };
}

/// Binds `love.graphics.getMeshCullMode`.
LoveApiImplementation _bindGraphicsGetMeshCullMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => switch (runtime.graphics.meshCullMode) {
    LoveGraphicsCullMode.none => 'none',
    LoveGraphicsCullMode.back => 'back',
    LoveGraphicsCullMode.front => 'front',
  };
}
