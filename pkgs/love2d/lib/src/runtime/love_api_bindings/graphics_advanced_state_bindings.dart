part of '../love_api_bindings.dart';

// love.graphics.setDepthMode([comparemode, write])
//
// Sets the depth comparison mode and whether writing to the depth buffer is
// enabled.  Calling with no arguments (or nil) disables depth testing, which
// is equivalent to setDepthMode('always', false).
//
// The depth state is tracked in LoveGraphicsState so that it is preserved
// by push('all') / pop() and reset() correctly.  The host renderer currently
// does not perform hardware depth testing; the state is recorded for
// completeness and forward-compatibility.
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

// love.graphics.getDepthMode
//
// Returns the current depth comparison mode and whether depth buffer writes
// are enabled.  Returns ('always', false) when depth testing is disabled.
LoveApiImplementation _bindGraphicsGetDepthMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    _compareModeName(runtime.graphics.depthMode),
    runtime.graphics.depthWrite,
  ]);
}

// love.graphics.setStencilTest([comparemode, comparevalue])
//
// Configures the per-pixel stencil test used when drawing.  Calling with no
// arguments (or nil) disables the stencil test, which is equivalent to
// setStencilTest('always', 0).
//
// The stencil state is tracked in LoveGraphicsState.  Hardware stencil
// testing is not yet performed by the host renderer; the state is stored for
// forward-compatibility and so that code that queries getStencilTest receives
// consistent results.
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

// love.graphics.getStencilTest
//
// Returns the current stencil comparison mode and reference value.
// Returns ('always', 0) when stencil testing is disabled.
LoveApiImplementation _bindGraphicsGetStencilTest(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    _compareModeName(runtime.graphics.stencilCompare),
    runtime.graphics.stencilValue,
  ]);
}

// love.graphics.setFrontFaceWinding(winding)
//
// Sets which vertex winding direction is considered front-facing for the
// purpose of face culling with setMeshCullMode.  Accepted values are 'ccw'
// (counter-clockwise, the LOVE default) and 'cw' (clockwise).
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

// love.graphics.getFrontFaceWinding
//
// Returns the current front-face winding direction ('ccw' or 'cw').
LoveApiImplementation _bindGraphicsGetFrontFaceWinding(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => switch (runtime.graphics.frontFaceWinding) {
    LoveGraphicsVertexWinding.ccw => 'ccw',
    LoveGraphicsVertexWinding.cw => 'cw',
  };
}

// love.graphics.setMeshCullMode(mode)
//
// Sets the face-culling mode used when drawing Meshes.  Accepted values are
// 'none' (no culling, the default), 'back' (cull back-facing triangles), and
// 'front' (cull front-facing triangles).
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

// love.graphics.getMeshCullMode
//
// Returns the current mesh face-culling mode ('none', 'back', or 'front').
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
