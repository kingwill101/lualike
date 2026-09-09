#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: capture_renderer_parity.sh --vm <url> [options]

Captures one deterministic 1:1 frame through native LOVE, Flutter Canvas, and
Flutter GPU. With --canvas-only, captures the native and non-GPU Canvas control
and verifies that flutter_gpu initialization was disabled. Demo-only controls,
status badges, and virtual cursor overlays are disabled through the LOVE2D
diagnostics extension before capture.

Options:
  --vm <url>              Flutter VM service URL (required).
  --project <path>        Native LOVE project (default: assets).
  --output-prefix <path>  Output prefix (default: $TMPDIR/love2d-benchmark/parity).
  --logical-size <WxH>    LOVE surface size (default: 800x600).
  --chrome-height <n>     Expected title/app-bar height (default: 103).
  --pointer <x,y>         Fixed logical pointer (default: 640,360).
  --reset-key <key>       Deterministic scene key (default: v).
  --native-game-arg <arg> Deterministic argument passed to native love.load.
  --regions <path>         Optional named-region manifest scored after capture.
  --settle-seconds <n>    Capture settle delay (default: 1).
  --canvas-only           Capture only Canvas and require GPU initialization off.
  --skip-native           Capture only the selected Flutter renderer(s).
  --help                  Show this help.
EOF
}

vm_service_url=""
project_path="${LOVE2D_NATIVE_PROJECT:-assets}"
output_prefix="${LOVE2D_PARITY_OUTPUT_PREFIX:-${TMPDIR:-.tmp}/love2d-benchmark/parity}"
logical_size="${LOVE2D_PARITY_LOGICAL_SIZE:-800x600}"
chrome_height="${LOVE2D_PARITY_CHROME_HEIGHT:-103}"
pointer_position="${LOVE2D_POINTER_POSITION:-640,360}"
reset_key="${LOVE2D_RESET_KEY:-v}"
native_game_arg="${LOVE2D_NATIVE_GAME_ARG:-}"
regions_path="${LOVE2D_PARITY_REGIONS:-}"
settle_seconds="${LOVE2D_PARITY_SETTLE_SECONDS:-1}"
capture_native=true
capture_gpu=true
window_class="${LOVE2D_COMPARISON_WINDOW_CLASS:-com.example.love2d_gpu_demo}"

while (($# > 0)); do
  case "$1" in
    --vm) vm_service_url="$2"; shift 2 ;;
    --project) project_path="$2"; shift 2 ;;
    --output-prefix) output_prefix="$2"; shift 2 ;;
    --logical-size) logical_size="$2"; shift 2 ;;
    --chrome-height) chrome_height="$2"; shift 2 ;;
    --pointer) pointer_position="$2"; shift 2 ;;
    --reset-key) reset_key="$2"; shift 2 ;;
    --native-game-arg) native_game_arg="$2"; shift 2 ;;
    --regions) regions_path="$2"; shift 2 ;;
    --settle-seconds) settle_seconds="$2"; shift 2 ;;
    --canvas-only) capture_gpu=false; shift ;;
    --skip-native) capture_native=false; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$vm_service_url" ]]; then
  echo "--vm is required" >&2
  exit 2
fi
if [[ -n "$regions_path" && ! -f "$regions_path" ]]; then
  echo "Region manifest does not exist: $regions_path" >&2
  exit 2
fi
if [[ -n "$regions_path" && "$capture_native" != true ]]; then
  echo "--regions requires a native capture" >&2
  exit 2
fi
for command in curl grim hyprctl jq magick compare; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done
if ! [[ "$logical_size" =~ ^[1-9][0-9]*x[1-9][0-9]*$ &&
        "$pointer_position" =~ ^-?[0-9]+([.][0-9]+)?,-?[0-9]+([.][0-9]+)?$ &&
        "$chrome_height" =~ ^[0-9]+$ && "$settle_seconds" =~ ^[0-9]+$ ]]; then
  echo "Invalid size, pointer, chrome height, or settle delay" >&2
  exit 2
fi

IFS=x read -r logical_width logical_height <<<"$logical_size"
IFS=, read -r pointer_x pointer_y <<<"$pointer_position"
window_height=$((logical_height + chrome_height))
vm_service_url="${vm_service_url%/}"
isolate_id="$(curl --fail --silent --show-error "$vm_service_url/getVM" |
  jq --exit-status --raw-output '.result.isolates[0].id')"

extension() {
  local name="$1"
  shift
  curl --fail --silent --show-error --get \
    "$vm_service_url/ext.flutter.love2d.$name" \
    --data-urlencode "isolateId=$isolate_id" "$@"
}

query_window() {
  hyprctl clients -j | jq -r --arg class "$window_class" '
    .[] | select(.class == $class)
    | [.address, .at[0], .at[1], .size[0], .size[1], .floating] | @tsv
  ' | head -n 1
}

query_window_workspace() {
  hyprctl clients -j | jq -r --arg class "$window_class" '
    .[] | select(.class == $class) | .workspace.id
  ' | head -n 1
}

focus_and_verify_window() {
  local address="$1"
  local active_address=""
  local active_workspace=""
  local target_workspace=""
  for _ in $(seq 1 20); do
    target_workspace="$(query_window_workspace)"
    active_workspace="$(hyprctl activeworkspace -j | jq -r '.id // empty')"
    if [[ "$target_workspace" =~ ^[1-9][0-9]*$ &&
          "$active_workspace" != "$target_workspace" ]]; then
      hyprctl dispatch workspace "$target_workspace" >/dev/null
    fi
    hyprctl eval \
      "hl.dispatch(hl.dsp.focus({ window = \"address:$address\" }))" >/dev/null
    sleep 0.05
    active_address="$(hyprctl activewindow -j | jq -r '.address // empty')"
    active_workspace="$(hyprctl activeworkspace -j | jq -r '.id // empty')"
    if [[ "$active_address" == "$address" &&
          "$active_workspace" == "$target_workspace" ]]; then
      return 0
    fi
  done
  echo "Unable to focus visible Flutter capture window: expected=$address active=${active_address:-none} targetWorkspace=${target_workspace:-none} activeWorkspace=${active_workspace:-none}" >&2
  return 1
}

set_capture_window_prop() {
  local address="$1"
  local prop="$2"
  local value="$3"
  local response
  response="$(hyprctl eval \
    "hl.dispatch(hl.dsp.window.set_prop({ prop = \"$prop\", value = \"$value\", window = \"address:$address\" }))")"
  if [[ "$response" != ok ]]; then
    echo "Unable to set Flutter capture property $prop=$value: $response" >&2
    return 1
  fi
}

capture_verified_window_region() {
  local address="$1"
  local output_path="$2"
  local active_before=""
  local active_after=""
  local current_address=""
  local current_geometry=""
  local geometry_after=""
  local x=""
  local y=""
  local width=""
  local height=""
  local floating=""
  local effective_chrome_height=""
  local chrome_delta=""
  for _ in $(seq 1 12); do
    focus_and_verify_window "$address" || continue
    sleep 0.1
    current_geometry="$(query_window)"
    IFS=$'\t' read -r current_address x y width height floating <<<"$current_geometry"
    effective_chrome_height=$((height - logical_height))
    chrome_delta=$((effective_chrome_height - chrome_height))
    if [[ "$current_address" != "$address" || "$width" != "$logical_width" ||
          "$chrome_delta" -lt -1 || "$chrome_delta" -gt 1 ]]; then
      continue
    fi
    active_before="$(hyprctl activewindow -j | jq -r '.address // empty')"
    [[ "$active_before" == "$address" ]] || continue
    grim -g "$x,$y ${width}x${height}" "$output_path"
    active_after="$(hyprctl activewindow -j | jq -r '.address // empty')"
    geometry_after="$(query_window)"
    if [[ "$active_after" == "$address" &&
          "$geometry_after" == "$current_geometry" ]]; then
      return 0
    fi
  done
  echo "Flutter window focus or geometry changed during capture: expected=$address before=${active_before:-none} after=${active_after:-none}" >&2
  return 1
}

wait_for_mode() {
  local expected_mode="$1"
  local minimum_frame="${2:-0}"
  local state
  for _ in $(seq 1 450); do
    state="$(extension getRenderState)"
    if [[ "$(jq -r '.result.ready' <<<"$state")" == true &&
          "$(jq -r '.result.mode' <<<"$state")" == "$expected_mode" &&
          "$(jq -r '.result.commandCount' <<<"$state")" -gt 0 &&
          "$(jq -r '.result.presentedFrame' <<<"$state")" -gt "$minimum_frame" ]]; then
      printf '%s' "$state"
      return 0
    fi
    sleep 0.1
  done
  echo "Timed out waiting for a ready $expected_mode frame" >&2
  return 1
}

normalize_exact_presentation() {
  local expected_mode="$1"
  local state geometry address x y width height floating
  local extra_width extra_height target_width target_height
  for _ in $(seq 1 12); do
    state="$(extension getRenderState)"
    if [[ "$(jq -r --arg mode "$expected_mode" --argjson width "$logical_width" \
      --argjson height "$logical_height" '
        .result.ready == true and .result.mode == $mode and
        .result.presentation.destinationLeft == 0 and
        .result.presentation.destinationTop == 0 and
        .result.presentation.destinationWidth == $width and
        .result.presentation.destinationHeight == $height
      ' <<<"$state")" == true ]]; then
      printf '%s' "$state"
      return 0
    fi

    geometry="$(query_window)"
    if [[ -z "$geometry" ]]; then
      break
    fi
    IFS=$'\t' read -r address x y width height floating <<<"$geometry"
    extra_width="$(jq -r '(.result.presentation.destinationLeft * 2) | round' <<<"$state")"
    extra_height="$(jq -r '(.result.presentation.destinationTop * 2) | round' <<<"$state")"
    if ! [[ "$extra_width" =~ ^[0-9]+$ && "$extra_height" =~ ^[0-9]+$ ]] ||
      ((extra_width == 0 && extra_height == 0)); then
      break
    fi
    target_width=$((width - extra_width))
    target_height=$((height - extra_height))
    if ((target_width < logical_width || target_height < logical_height)); then
      break
    fi
    hyprctl eval \
      "hl.dispatch(hl.dsp.window.resize({ x = $target_width, y = $target_height, window = \"address:$address\" }))" >/dev/null
    sleep 0.25
  done

  echo "Unable to establish an exact 1:1 Flutter presentation rectangle" >&2
  if [[ -n "${state:-}" ]]; then
    jq '.result | {mode, window, presentation}' <<<"$state" >&2 || true
  fi
  return 1
}

mkdir -p "$(dirname "$output_prefix")"
native_path="${output_prefix}-native.png"
if [[ "$capture_native" == true ]]; then
  native_capture_args=(
    --project "$project_path"
    --key "$reset_key"
    --window-size "$logical_size"
    --settle-seconds "$settle_seconds"
    --output "$native_path"
  )
  if [[ -n "$native_game_arg" ]]; then
    native_capture_args+=(--game-arg "$native_game_arg")
  fi
  bash "$(dirname "$0")/capture_native_love.sh" "${native_capture_args[@]}"
fi

initial_state="$(extension getRenderState)"
if [[ "$capture_gpu" == true ]]; then
  if [[ "$(jq -r '.result.gpuAvailable' <<<"$initial_state")" != true ]]; then
    echo "The three-renderer lane requires an available Flutter GPU backend" >&2
    jq '.result | {gpuInitializationDisabled, gpuAvailable, mode}' \
      <<<"$initial_state" >&2
    exit 1
  fi
else
  if ! jq --exit-status '
    .result.gpuInitializationDisabled == true and
    .result.gpuAvailable == false and
    .result.mode == "canvas"
    ' <<<"$initial_state" >/dev/null; then
    echo "--canvas-only requires LOVE2D_DEMO_FORCE_CANVAS=true" >&2
    jq '.result | {gpuInitializationDisabled, gpuAvailable, mode}' \
      <<<"$initial_state" >&2
    exit 1
  fi
fi
initial_capture="$(jq -r '.result.capturePresentation // false' <<<"$initial_state")"
restore_capture() {
  extension setCapturePresentation \
    --data-urlencode "enabled=$initial_capture" >/dev/null 2>&1 || true
}
trap restore_capture EXIT INT TERM

geometry="$(query_window)"
if [[ -z "$geometry" ]]; then
  echo "No Flutter window found for class $window_class" >&2
  exit 1
fi
IFS=$'\t' read -r address x y width height floating <<<"$geometry"
focus_and_verify_window "$address"
set_capture_window_prop "$address" border_size 0
set_capture_window_prop "$address" rounding 0
set_capture_window_prop "$address" no_shadow 1
if [[ "$floating" != true ]]; then
  hyprctl eval 'hl.dispatch(hl.dsp.window.float({ action = "toggle" }))' >/dev/null
fi
hyprctl eval \
  "hl.dispatch(hl.dsp.window.resize({ x = $logical_width, y = $window_height, window = \"address:$address\" }))" >/dev/null
hyprctl eval 'hl.dispatch(hl.dsp.window.center())' >/dev/null
extension setCapturePresentation --data-urlencode enabled=true >/dev/null

modes=(canvas)
if [[ "$capture_gpu" == true ]]; then
  modes=(gpu canvas)
fi
for mode in "${modes[@]}"; do
  extension setRenderMode --data-urlencode "mode=$mode" >/dev/null
  state="$(wait_for_mode "$mode")"
  extension resetInputState >/dev/null
  extension setVirtualPointer \
    --data-urlencode "x=$pointer_x" --data-urlencode "y=$pointer_y" \
    --data-urlencode lockPhysicalMouseInput=true >/dev/null
  previous_frame="$(jq -r '.result.presentedFrame' <<<"$state")"
  extension setVirtualKey --data-urlencode "key=$reset_key" \
    --data-urlencode down=true >/dev/null
  state="$(wait_for_mode "$mode" "$previous_frame")"
  extension setVirtualKey --data-urlencode "key=$reset_key" \
    --data-urlencode down=false >/dev/null
  previous_frame="$(jq -r '.result.presentedFrame' <<<"$state")"
  state="$(wait_for_mode "$mode" "$previous_frame")"
  if ((settle_seconds > 0)); then sleep "$settle_seconds"; fi
  state="$(normalize_exact_presentation "$mode")"

  geometry="$(query_window)"
  IFS=$'\t' read -r address x y width height floating <<<"$geometry"
  focus_and_verify_window "$address"
  geometry="$(query_window)"
  IFS=$'\t' read -r address x y width height floating <<<"$geometry"
  effective_chrome_height=$((height - logical_height))
  chrome_delta=$((effective_chrome_height - chrome_height))
  if [[ "$width" != "$logical_width" || "$chrome_delta" -lt -1 ||
        "$chrome_delta" -gt 1 ]]; then
    echo "Flutter window size mismatch: expected=${logical_width}x${window_height} actual=${width}x${height}" >&2
    exit 1
  fi
  window_path="${output_prefix}-${mode}-window.png"
  image_path="${output_prefix}-${mode}.png"
  capture_verified_window_region "$address" "$window_path"
  magick "$window_path" \
    -crop "${logical_width}x${logical_height}+0+${effective_chrome_height}" \
    +repage "$image_path"
  jq '.result' <<<"$state" >"${output_prefix}-${mode}-state.json"
done

canvas_gpu_normalized=null
native_canvas_normalized=null
native_gpu_normalized=null
if [[ "$capture_gpu" == true ]]; then
  canvas_gpu_rmse="$(compare -metric RMSE "${output_prefix}-canvas.png" \
    "${output_prefix}-gpu.png" null: 2>&1 || true)"
  canvas_gpu_normalized="$(sed -n 's/.*(\([^)]*\)).*/\1/p' \
    <<<"$canvas_gpu_rmse")"
fi
if [[ "$capture_native" == true ]]; then
  metric="$(compare -metric RMSE "$native_path" \
    "${output_prefix}-canvas.png" null: 2>&1 || true)"
  native_canvas_normalized="$(sed -n 's/.*(\([^)]*\)).*/\1/p' <<<"$metric")"
  if [[ "$capture_gpu" == true ]]; then
    metric="$(compare -metric RMSE "$native_path" \
      "${output_prefix}-gpu.png" null: 2>&1 || true)"
    native_gpu_normalized="$(sed -n 's/.*(\([^)]*\)).*/\1/p' <<<"$metric")"
  fi
fi

if [[ "$capture_gpu" == true ]]; then
  jq -n \
    --arg logicalSize "$logical_size" \
    --arg captureLane native-canvas-gpu \
    --argjson canvasGpuRmse "$canvas_gpu_normalized" \
    --argjson nativeCanvasRmse "$native_canvas_normalized" \
    --argjson nativeGpuRmse "$native_gpu_normalized" \
    --slurpfile canvas "${output_prefix}-canvas-state.json" \
    --slurpfile gpu "${output_prefix}-gpu-state.json" \
    '{schemaVersion: 1, logicalSize: $logicalSize, captureLane: $captureLane,
      normalizedRmse: {canvasGpu: $canvasGpuRmse,
        nativeCanvas: $nativeCanvasRmse, nativeGpu: $nativeGpuRmse},
      renderState: {canvas: $canvas[0], gpu: $gpu[0]}}' \
    >"${output_prefix}-summary.json"
else
  jq -n \
    --arg logicalSize "$logical_size" \
    --arg captureLane native-canvas \
    --argjson nativeCanvasRmse "$native_canvas_normalized" \
    --slurpfile canvas "${output_prefix}-canvas-state.json" \
    '{schemaVersion: 1, logicalSize: $logicalSize, captureLane: $captureLane,
      normalizedRmse: {canvasGpu: null,
        nativeCanvas: $nativeCanvasRmse, nativeGpu: null},
      renderState: {canvas: $canvas[0], gpu: null}}' \
    >"${output_prefix}-summary.json"
fi

jq '{logicalSize, normalizedRmse}' "${output_prefix}-summary.json"

if [[ -n "$regions_path" ]]; then
  region_args=(
    --native "$native_path" \
    --canvas "${output_prefix}-canvas.png" \
    --regions "$regions_path" \
    --output "${output_prefix}-regions.json"
  )
  if [[ "$capture_gpu" == true ]]; then
    region_args+=(--gpu "${output_prefix}-gpu.png")
  fi
  "$(dirname "$0")/score_renderer_regions.sh" "${region_args[@]}"
fi
