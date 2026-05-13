#version 460 core

precision lowp float;

uniform vec4 uColor;

out vec4 fragColor;

void main() {
  fragColor = uColor;
}

