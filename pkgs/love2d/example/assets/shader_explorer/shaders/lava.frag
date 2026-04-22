#version 150
#include <flutter/runtime_effect.glsl>

// KodeLife start example
 
uniform vec2 resolution;
uniform float time;

out vec4 fragColor;

void main()
{
    vec2 uv = -1. + 2. * FlutterFragCoord().xy / resolution.xy;
    fragColor = vec4(
        abs(sin(cos(time+3.*uv.y)*2.*uv.x+time)),
        abs(cos(sin(time+2.*uv.x)*3.*uv.y+time)),
        0.,
        1.0);
}