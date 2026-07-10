// Solid-color path: the vertex stage has already prepared the tint.
in vec2 v_texcoord;
in vec4 v_color;

out vec4 frag_color;

void main() {
  frag_color = v_color;
}
