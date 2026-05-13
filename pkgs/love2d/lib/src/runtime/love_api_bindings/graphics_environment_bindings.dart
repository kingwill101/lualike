part of '../love_api_bindings.dart';

/// The LOVE graphics feature flags reported by `love.graphics.getSupported`.
const Map<String, bool> _loveGraphicsSupportedFeatures = <String, bool>{
  // Mirrors the documented GraphicsFeature constants surfaced by
  // LOVE's wrap_Graphics.cpp w_getSupported helper.
  'clampzero': true,
  'fullnpot': true,
  'glsl3': true,
  'instancing': true,
  'lighten': true,
  'multicanvasformats': true,
  'pixelshaderhighp': true,
  'shaderderivatives': true,
};

/// The LOVE graphics system limits reported by `love.graphics.getSystemLimits`.
const Map<String, num> _loveGraphicsSystemLimits = <String, num>{
  // Mirrors the documented GraphicsLimit constants returned by
  // LOVE's wrap_Graphics.cpp w_getSystemLimits helper.
  'anisotropy': 16,
  'canvasmsaa': 8,
  'cubetexturesize': 4096,
  'multicanvas': 4,
  'pointsize': 64,
  'texturelayers': 256,
  'texturesize': 4096,
  'volumetexturesize': 256,
};

/// Binds `love.graphics.getDPIScale`.
LoveApiImplementation _bindGraphicsGetDpiScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.dpiScale;
}

/// Binds `love.graphics.getPixelWidth`.
LoveApiImplementation _bindGraphicsGetPixelWidth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      (runtime.windowMetrics.width * runtime.windowMetrics.dpiScale).round();
}

/// Binds `love.graphics.getPixelHeight`.
LoveApiImplementation _bindGraphicsGetPixelHeight(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      (runtime.windowMetrics.height * runtime.windowMetrics.dpiScale).round();
}

/// Binds `love.graphics.getPixelDimensions`.
///
/// The returned values match LOVE's `(pixelWidth, pixelHeight)` tuple.
LoveApiImplementation _bindGraphicsGetPixelDimensions(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final pixelWidth =
        (runtime.windowMetrics.width * runtime.windowMetrics.dpiScale).round();
    final pixelHeight =
        (runtime.windowMetrics.height * runtime.windowMetrics.dpiScale).round();
    return Value.multi(<Object?>[pixelWidth, pixelHeight]);
  };
}

/// Binds `love.graphics.getRendererInfo`.
///
/// The returned values match LOVE's `(name, version, vendor, device)` tuple.
LoveApiImplementation _bindGraphicsGetRendererInfo(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => Value.multi(<Object?>[
    runtime.host.rendererName,
    runtime.host.rendererVersion,
    runtime.host.rendererVendor,
    runtime.host.rendererDevice,
  ]);
}

/// Binds `love.graphics.getImageFormats`.
///
/// LOVE optionally accepts a destination table to populate, so this binding
/// preserves that in-place fill behavior.
LoveApiImplementation _bindGraphicsGetImageFormats(
  LibraryRegistrationContext context,
) {
  return (args) {
    final target = _optionalTableTarget(_valueAt(args, 0));
    final table = target?.$2 ?? <dynamic, dynamic>{};
    for (final format in _canvasFormatNames) {
      table[format] = !_isDepthStencilFormat(format) && format != 'unknown';
    }
    return target?.$1 ?? Value(table);
  };
}

/// Binds `love.graphics.getSupported`.
///
/// LOVE optionally accepts a destination table to populate, so this binding
/// preserves that in-place fill behavior.
LoveApiImplementation _bindGraphicsGetSupported(
  LibraryRegistrationContext context,
) {
  return (args) {
    final target = _optionalTableTarget(_valueAt(args, 0));
    final table = _fillGraphicsInfoTable(
      target: target?.$2,
      source: _loveGraphicsSupportedFeatures,
    );
    return target?.$1 ?? Value(table);
  };
}

/// Binds `love.graphics.getSystemLimits`.
///
/// LOVE optionally accepts a destination table to populate, so this binding
/// preserves that in-place fill behavior.
LoveApiImplementation _bindGraphicsGetSystemLimits(
  LibraryRegistrationContext context,
) {
  return (args) {
    final target = _optionalTableTarget(_valueAt(args, 0));
    final table = _fillGraphicsInfoTable(
      target: target?.$2,
      source: _loveGraphicsSystemLimits,
    );
    return target?.$1 ?? Value(table);
  };
}

/// Binds `love.graphics.getStats`.
///
/// LOVE optionally accepts a destination table to populate, so this binding
/// forwards that table to the runtime stats collector when present.
LoveApiImplementation _bindGraphicsGetStats(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) {
    final target = _optionalTableTarget(_valueAt(args, 0));
    final table = runtime.graphicsStats(target: target?.$2);
    return target?.$1 ?? Value(table);
  };
}

/// Copies key-value pairs from [source] into a LOVE info table.
///
/// When [target] is provided, this mutates it in place to match LOVE's optional
/// destination-table convention.
Map<dynamic, dynamic> _fillGraphicsInfoTable<T extends Object>({
  required Map<String, T> source,
  Map<dynamic, dynamic>? target,
}) {
  final table = target ?? <dynamic, dynamic>{};
  for (final entry in source.entries) {
    table[entry.key] = entry.value;
  }
  return table;
}
