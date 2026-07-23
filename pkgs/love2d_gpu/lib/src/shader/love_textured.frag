// Texture path bound by image / mesh / sprite-batch handlers.
uniform sampler2D texture_sampler;

in vec2 v_texcoord;
in vec4 v_color;

out vec4 frag_color;

void main() {
  frag_color = v_color * texture(texture_sampler, v_texcoord);
}
