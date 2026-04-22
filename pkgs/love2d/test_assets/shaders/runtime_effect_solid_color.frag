#version 460 core

precision mediump float;

uniform vec4 uColor;

out vec4 fragColor;

void main() {
  fragColor = uColor;
}
