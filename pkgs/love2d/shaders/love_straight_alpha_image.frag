#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uImageSize;
uniform vec2 uSourceOrigin;
uniform vec2 uSourceSize;
uniform vec2 uDestinationOrigin;
uniform vec2 uDestinationSize;
uniform vec4 uTint;
uniform sampler2D uOpaqueRgb;
uniform sampler2D uNativeAlpha;

out vec4 fragColor;

void main() {
  vec2 local = (FlutterFragCoord().xy - uDestinationOrigin) / uDestinationSize;
  vec2 uv = (uSourceOrigin + local * uSourceSize) / uImageSize;
  vec3 rgb = texture(uOpaqueRgb, uv).rgb * uTint.rgb;
  float alpha = texture(uNativeAlpha, uv).a * uTint.a;
  fragColor = vec4(rgb * alpha, alpha);
}
