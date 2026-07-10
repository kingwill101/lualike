// Shared camera matrix for instanced sprite batches.
uniform ViewInfo {
  mat4 view_projection;
} view_info;

in vec2 position;
in vec2 texcoord;

in vec4 instance_transform_row0;
in vec4 instance_transform_row1;
in vec4 instance_transform_row2;
in vec4 instance_transform_row3;
in vec4 instance_uv_transform;
in vec4 instance_color;

out vec2 v_texcoord;
out vec4 v_color;

void main() {
  mat4 instance_transform = mat4(
    instance_transform_row0,
    instance_transform_row1,
    instance_transform_row2,
    instance_transform_row3
  );
  vec4 world_pos = instance_transform * vec4(position, 0.0, 1.0);
  gl_Position = view_info.view_projection * world_pos;
  v_texcoord = texcoord * instance_uv_transform.xy + instance_uv_transform.zw;
  v_color = instance_color;
}
