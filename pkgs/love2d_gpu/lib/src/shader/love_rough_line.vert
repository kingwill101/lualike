// Screen and clip positions are uploaded together. Avoiding a per-command
// matrix uniform keeps this exact line path as cheap to record as an ordinary
// unlit quad.
in vec2 position;
in vec2 clip_position;

out vec2 v_screen_position;

void main() {
  gl_Position = vec4(clip_position, 0.0, 1.0);
  v_screen_position = position;
}
