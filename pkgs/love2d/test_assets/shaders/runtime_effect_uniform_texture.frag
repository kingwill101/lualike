#version 460 core

precision mediump float;

uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  fragColor = texture(uTexture, vec2(0.5, 0.5));
}
