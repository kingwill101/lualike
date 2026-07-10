// Shared transform + tint for mesh and image draws.
// The CPU side binds this as a VertInfo uniform block.
uniform VertInfo {
  mat4 mvp;
  vec4 color;
} vert_info;

in vec2 position;
in vec2 texcoord;
in vec4 color;

out vec2 v_texcoord;
out vec4 v_color;

void main() {
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
  v_texcoord = texcoord;
  v_color = vert_info.color * color;
}
