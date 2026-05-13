part of '../love_api_bindings.dart';

/// Binds `love.graphics.applyTransform`.
LoveApiImplementation _bindGraphicsApplyTransform(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.applyTransform(
      _requireTransform(args, 0, 'love.graphics.applyTransform'),
    );
    return null;
  };
}

/// Binds `love.graphics.replaceTransform`.
LoveApiImplementation _bindGraphicsReplaceTransform(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.replaceTransform(
      _requireTransform(args, 0, 'love.graphics.replaceTransform'),
    );
    return null;
  };
}

/// Binds `love.graphics.getStackDepth`.
LoveApiImplementation _bindGraphicsGetStackDepth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.graphics.stackDepth;
}

/// Binds `love.graphics.origin`.
LoveApiImplementation _bindGraphicsOrigin(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.origin();
    return null;
  };
}

/// Binds `love.graphics.push`.
///
/// LOVE optionally accepts a stack type and an immediate transform to apply
/// after the push, so this binding supports both call shapes.
LoveApiImplementation _bindGraphicsPush(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final stackType = args.isEmpty
        ? LoveGraphicsStackType.transform
        : _graphicsStackType(_valueAt(args, 0), 'love.graphics.push');
    runtime.graphics.push(stackType);
    if (_transformIfPresent(_valueAt(args, 1))
        case final LoveTransform transform) {
      runtime.graphics.applyTransform(transform);
    }
    return null;
  };
}

/// Binds `love.graphics.pop`.
LoveApiImplementation _bindGraphicsPop(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.pop();
    return null;
  };
}

/// Binds `love.graphics.translate`.
LoveApiImplementation _bindGraphicsTranslate(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.translate(
      _requireNumber(args, 0, 'love.graphics.translate'),
      _requireNumber(args, 1, 'love.graphics.translate'),
    );
    return null;
  };
}

/// Binds `love.graphics.rotate`.
LoveApiImplementation _bindGraphicsRotate(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.rotate(_requireNumber(args, 0, 'love.graphics.rotate'));
    return null;
  };
}

/// Binds `love.graphics.scale`.
///
/// When Lua omits the second scale component, LOVE reuses the x scale for y.
LoveApiImplementation _bindGraphicsScale(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final x = args.isEmpty
        ? 1.0
        : _requireNumber(args, 0, 'love.graphics.scale');
    final y = args.length >= 2
        ? _requireNumber(args, 1, 'love.graphics.scale')
        : x;
    runtime.graphics.scale(x, y);
    return null;
  };
}

/// Binds `love.graphics.shear`.
LoveApiImplementation _bindGraphicsShear(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.shear(
      _requireNumber(args, 0, 'love.graphics.shear'),
      _requireNumber(args, 1, 'love.graphics.shear'),
    );
    return null;
  };
}

/// Binds `love.graphics.transformPoint`.
///
/// The returned values match LOVE's transformed `(x, y)` tuple.
LoveApiImplementation _bindGraphicsTransformPoint(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final point = runtime.graphics.transformPoint(
      _requireNumber(args, 0, 'love.graphics.transformPoint'),
      _requireNumber(args, 1, 'love.graphics.transformPoint'),
    );
    return Value.multi(<Object?>[point.x, point.y]);
  };
}

/// Binds `love.graphics.inverseTransformPoint`.
///
/// The returned values match LOVE's inverse-transformed `(x, y)` tuple.
LoveApiImplementation _bindGraphicsInverseTransformPoint(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final point = runtime.graphics.inverseTransformPoint(
      _requireNumber(args, 0, 'love.graphics.inverseTransformPoint'),
      _requireNumber(args, 1, 'love.graphics.inverseTransformPoint'),
    );
    return Value.multi(<Object?>[point.x, point.y]);
  };
}
