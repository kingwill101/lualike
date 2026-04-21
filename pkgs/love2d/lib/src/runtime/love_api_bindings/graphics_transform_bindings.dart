part of '../love_api_bindings.dart';

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

LoveApiImplementation _bindGraphicsGetStackDepth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.graphics.stackDepth;
}

LoveApiImplementation _bindGraphicsOrigin(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.origin();
    return null;
  };
}

LoveApiImplementation _bindGraphicsPush(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    final stackType = args.isEmpty
        ? LoveGraphicsStackType.transform
        : _graphicsStackType(_valueAt(args, 0), 'love.graphics.push');
    runtime.graphics.push(stackType);
    if (args.length >= 2) {
      runtime.graphics.applyTransform(
        _requireTransform(args, 1, 'love.graphics.push'),
      );
    }
    return null;
  };
}

LoveApiImplementation _bindGraphicsPop(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.pop();
    return null;
  };
}

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

LoveApiImplementation _bindGraphicsRotate(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.rotate(_requireNumber(args, 0, 'love.graphics.rotate'));
    return null;
  };
}

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
