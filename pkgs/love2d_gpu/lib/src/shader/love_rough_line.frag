// One conservative quad covers the segment. This shader reproduces the
// perpendicular sleeve that LOVE 11.5 submits as a single-sample triangle
// strip, independently of flutter_gpu's triangle-edge conventions.
uniform RoughLineInfo {
  vec4 endpoints;
  vec4 params;
  vec4 color;
} rough_line_info;

in vec2 v_screen_position;

out vec4 frag_color;

void main() {
  vec2 pixel_center = floor(v_screen_position) + vec2(0.5);
  vec2 start = rough_line_info.endpoints.xy;
  vec2 end = rough_line_info.endpoints.zw;
  float half_width = rough_line_info.params.x;
  vec2 segment = end - start;
  float segment_length = length(segment);
  vec2 tangent = segment / segment_length;
  vec2 relative = pixel_center - start;
  float along = dot(relative, tangent);
  if (along < 0.0 || along >= segment_length) {
    discard;
  }

  float perpendicular = abs(segment.x * relative.y - segment.y * relative.x)
      / segment_length;
  if (perpendicular > half_width) {
    discard;
  }
  frag_color = rough_line_info.color;
}
