part of '../love_runtime.dart';

/// Returns the scalar uniform named [name] from [shader].
///
/// This accepts either a numeric uniform value or a single-element numeric
/// list and normalizes the result to `double`.
double? loveShaderNumberUniform(LoveShader shader, String name) {
  final value = shader.uniform(name);
  return switch (value) {
    final num number => number.toDouble(),
    final List<Object?> values when values.length == 1 && values.first is num =>
      (values.first as num).toDouble(),
    _ => null,
  };
}

/// Returns the first [length] numeric components of the uniform named [name].
///
/// This returns `null` when the uniform is missing, is not a list, or does not
/// contain at least [length] numeric entries.
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

/// Returns the color uniform named [name] from [shader].
///
/// This accepts either a stored [LoveColor] or a numeric list containing at
/// least red, green, and blue components. Missing alpha defaults to `1.0`.
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

/// Applies the desaturation tint subset effect to [color].
///
/// This reads `tint` and `strength` uniforms from [shader] and returns the
/// tinted result, or `null` when either uniform is unavailable.
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

/// Samples the radial-gradient subset effect at the point `[x, y]`.
///
/// This reads `center`, `innerRadius`, `outerRadius`, `colorInner`, and
/// `colorOuter` uniforms from [shader]. Missing colors fall back to
/// [fallbackColor]. The function returns `null` when the gradient center or
/// outer radius cannot be resolved.
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

/// Linearly interpolates from [a] to [b] using [t].
LoveColor _loveLerpColor(LoveColor a, LoveColor b, double t) {
  return LoveColor(
    a.r + ((b.r - a.r) * t),
    a.g + ((b.g - a.g) * t),
    a.b + ((b.b - a.b) * t),
    a.a + ((b.a - a.a) * t),
  ).clamped();
}
