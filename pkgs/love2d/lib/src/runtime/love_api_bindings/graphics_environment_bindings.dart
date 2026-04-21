part of '../love_api_bindings.dart';

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

LoveApiImplementation _bindGraphicsGetDpiScale(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) => runtime.windowMetrics.dpiScale;
}

LoveApiImplementation _bindGraphicsGetPixelWidth(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      (runtime.windowMetrics.width * runtime.windowMetrics.dpiScale).round();
}

LoveApiImplementation _bindGraphicsGetPixelHeight(
  LibraryRegistrationContext context,
) {
  final runtime = _runtimeContext(context);
  return (args) =>
      (runtime.windowMetrics.height * runtime.windowMetrics.dpiScale).round();
}

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
