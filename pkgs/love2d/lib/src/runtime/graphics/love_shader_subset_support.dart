part of '../love_runtime.dart';

double? loveShaderNumberUniform(LoveShader shader, String name) {
  final value = shader.uniform(name);
  return switch (value) {
    final num number => number.toDouble(),
    final List<Object?> values when values.length == 1 && values.first is num =>
      (values.first as num).toDouble(),
    _ => null,
  };
}

List<double>? loveShaderVectorUniform(
  LoveShader shader,
  String name,
  int length,
) {
  final value = shader.uniform(name);
  if (value is! List<Object?> || value.length < length) {
    return null;
  }

  final result = <double>[];
  for (var index = 0; index < length; index++) {
    final entry = value[index];
    if (entry is! num) {
      return null;
    }
    result.add(entry.toDouble());
  }
  return result;
}

LoveColor? loveShaderColorUniform(LoveShader shader, String name) {
  final value = shader.uniform(name);
  if (value is LoveColor) {
    return value;
  }

  if (value is! List<Object?> || value.length < 3) {
    return null;
  }

  final components = <double>[];
  for (final entry in value.take(4)) {
    if (entry is! num) {
      return null;
    }
    components.add(entry.toDouble());
  }
  while (components.length < 4) {
    components.add(1.0);
  }

  return LoveColor(components[0], components[1], components[2], components[3]);
}

LoveColor? loveShaderDesaturationTintColor(LoveShader shader, LoveColor color) {
  final tint = loveShaderColorUniform(shader, 'tint');
  final strength = loveShaderNumberUniform(shader, 'strength');
  if (tint == null || strength == null) {
    return null;
  }

  const lumaR = 0.299;
  const lumaG = 0.587;
  const lumaB = 0.114;
  final base = 1.0 - strength;
  final luma = color.r * lumaR + color.g * lumaG + color.b * lumaB;

  return LoveColor(
    color.r * base + (tint.r * luma * strength),
    color.g * base + (tint.g * luma * strength),
    color.b * base + (tint.b * luma * strength),
    color.a * base + (tint.a * luma * strength),
  ).clamped();
}

LoveColor? loveShaderRadialGradientColorAt(
  LoveShader shader, {
  required LoveColor fallbackColor,
  required double x,
  required double y,
}) {
  final center = loveShaderVectorUniform(shader, 'center', 2);
  final innerRadius = loveShaderNumberUniform(shader, 'innerRadius') ?? 0;
  final outerRadius = loveShaderNumberUniform(shader, 'outerRadius') ?? 0;
  final colorInner =
      loveShaderColorUniform(shader, 'colorInner') ?? fallbackColor;
  final colorOuter =
      loveShaderColorUniform(shader, 'colorOuter') ?? fallbackColor;

  if (center == null || outerRadius <= 0) {
    return null;
  }

  final dx = x - center[0];
  final dy = y - center[1];
  final distance = math.sqrt(dx * dx + dy * dy);
  final normalizedDistance = (distance / outerRadius).clamp(0.0, 1.0);
  final innerStop = (innerRadius / outerRadius).clamp(0.0, 1.0);

  if (normalizedDistance >= 1.0) {
    return colorOuter.clamped();
  }
  if (normalizedDistance <= innerStop) {
    return colorInner.clamped();
  }

  final t = innerStop >= 1.0
      ? 1.0
      : ((normalizedDistance - innerStop) / (1.0 - innerStop)).clamp(0.0, 1.0);
  return _loveLerpColor(colorInner, colorOuter, t);
}

LoveColor _loveLerpColor(LoveColor a, LoveColor b, double t) {
  return LoveColor(
    a.r + ((b.r - a.r) * t),
    a.g + ((b.g - a.g) * t),
    a.b + ((b.b - a.b) * t),
    a.a + ((b.a - a.a) * t),
  ).clamped();
}
