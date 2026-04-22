part of '../love_api_bindings.dart';

LoveApiImplementation _bindGraphicsReset(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.reset();
    return null;
  };
}

LoveApiImplementation _bindGraphicsSetLineWidth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final width = _requireNumber(args, 0, 'love.graphics.setLineWidth');
    if (width <= 0) {
      throw LuaError('love.graphics.setLineWidth width must be > 0');
    }
    runtime.graphics.lineWidth = width;
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetLineWidth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.graphics.lineWidth;
}

LoveApiImplementation _bindGraphicsSetPointSize(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final size = _requireNumber(args, 0, 'love.graphics.setPointSize');
    if (size <= 0) {
      throw LuaError('love.graphics.setPointSize size must be > 0');
    }
    runtime.graphics.pointSize = size;
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetPointSize(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.graphics.pointSize;
}

LoveApiImplementation _bindGraphicsSetScissor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty) {
      runtime.graphics.setScissor(null);
      return null;
    }

    runtime.graphics.setScissor(
      _scissorRectFromArgs(args, 'love.graphics.setScissor'),
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsIntersectScissor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.intersectScissor(
      _scissorRectFromArgs(args, 'love.graphics.intersectScissor'),
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetScissor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final scissor = runtime.graphics.scissor;
    if (scissor == null) {
      return null;
    }

    return Value.multi(<Object?>[
      scissor.x,
      scissor.y,
      scissor.width,
      scissor.height,
    ]);
  };
}

LoveApiImplementation _bindGraphicsSetLineStyle(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.lineStyle = _lineStyle(
      _requireString(args, 0, 'love.graphics.setLineStyle'),
      'love.graphics.setLineStyle',
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsSetLineJoin(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.lineJoin = _lineJoin(
      _requireString(args, 0, 'love.graphics.setLineJoin'),
      'love.graphics.setLineJoin',
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsSetBlendMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final mode = _blendMode(
      _requireString(args, 0, 'love.graphics.setBlendMode'),
      'love.graphics.setBlendMode',
    );
    final alphaMode = args.length >= 2
        ? _blendAlphaMode(
            _requireString(args, 1, 'love.graphics.setBlendMode'),
            'love.graphics.setBlendMode',
          )
        : LoveGraphicsBlendAlphaMode.alphaMultiply;
    if (alphaMode != LoveGraphicsBlendAlphaMode.premultiplied) {
      final modeName = switch (mode) {
        LoveGraphicsBlendMode.multiply => 'multiply',
        LoveGraphicsBlendMode.lighten => 'lighten',
        LoveGraphicsBlendMode.darken => 'darken',
        _ => null,
      };
      if (modeName != null) {
        throw LuaError(
          "The '$modeName' blend mode must be used with premultiplied alpha.",
        );
      }
    }

    runtime.graphics.blendMode = mode;
    runtime.graphics.blendAlphaMode = alphaMode;
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetBlendMode(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    switch (runtime.graphics.blendMode) {
      LoveGraphicsBlendMode.alpha => 'alpha',
      LoveGraphicsBlendMode.add => 'add',
      LoveGraphicsBlendMode.subtract => 'subtract',
      LoveGraphicsBlendMode.multiply => 'multiply',
      LoveGraphicsBlendMode.lighten => 'lighten',
      LoveGraphicsBlendMode.darken => 'darken',
      LoveGraphicsBlendMode.screen => 'screen',
      LoveGraphicsBlendMode.replace => 'replace',
      LoveGraphicsBlendMode.none => 'none',
    },
    switch (runtime.graphics.blendAlphaMode) {
      LoveGraphicsBlendAlphaMode.alphaMultiply => 'alphamultiply',
      LoveGraphicsBlendAlphaMode.premultiplied => 'premultiplied',
    },
  ]);
}

LoveApiImplementation _bindGraphicsSetColorMask(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty || _rawValue(args.first) == null) {
      runtime.graphics.colorMask = LoveGraphicsColorMask.all;
      return null;
    }

    runtime.graphics.colorMask = LoveGraphicsColorMask(
      red: _requireBoolean(args, 0, 'love.graphics.setColorMask'),
      green: _requireBoolean(args, 1, 'love.graphics.setColorMask'),
      blue: _requireBoolean(args, 2, 'love.graphics.setColorMask'),
      alpha: _requireBoolean(args, 3, 'love.graphics.setColorMask'),
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetColorMask(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    runtime.graphics.colorMask.red,
    runtime.graphics.colorMask.green,
    runtime.graphics.colorMask.blue,
    runtime.graphics.colorMask.alpha,
  ]);
}

LoveApiImplementation _bindGraphicsSetWireframe(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.wireframe = _requireBoolean(
      args,
      0,
      'love.graphics.setWireframe',
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsIsWireframe(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.graphics.wireframe;
}

LoveApiImplementation _bindGraphicsGetLineStyle(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => switch (runtime.graphics.lineStyle) {
    LoveGraphicsLineStyle.smooth => 'smooth',
    LoveGraphicsLineStyle.rough => 'rough',
  };
}

LoveApiImplementation _bindGraphicsGetLineJoin(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => switch (runtime.graphics.lineJoin) {
    LoveGraphicsLineJoin.none => 'none',
    LoveGraphicsLineJoin.miter => 'miter',
    LoveGraphicsLineJoin.bevel => 'bevel',
  };
}

LoveApiImplementation _bindGraphicsSetColor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.color = _requireColor(args, 0, 'love.graphics.setColor');
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetColor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => _colorResult(runtime.graphics.color);
}

LoveApiImplementation _bindGraphicsSetBackgroundColor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    runtime.graphics.backgroundColor = _requireColor(
      args,
      0,
      'love.graphics.setBackgroundColor',
    );
    return null;
  };
}

LoveApiImplementation _bindGraphicsGetBackgroundColor(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => _colorResult(runtime.graphics.backgroundColor);
}

LoveApiImplementation _bindGraphicsClear(LibraryRegistrationContext context) {
  final runtime = _runtimeContext(context);
  return (args) {
    if (args.isEmpty) {
      runtime.graphics.clear();
      return null;
    }

    final first = _rawValue(args.first);
    if (first is bool) {
      if (first) {
        runtime.graphics.clear();
      }
      return null;
    }

    runtime.graphics.clear(_requireColor(args, 0, 'love.graphics.clear'));
    return null;
  };
}
