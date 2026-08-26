#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: capture_renderer_comparison.sh [options]

Captures the Flutter Canvas/GPU comparison at an integer-aligned LOVE viewport,
crops both synchronized panes, and records their normalized RMSE.

Options:
  --window-class <class>
                    Flutter window class (default: com.example.love2d_gpu_demo).
  --logical-size <WxH>
                    LOVE logical surface size (default: 800x600).
  --chrome-height <n>
                    Window title bar plus Flutter app bar height (default: 103).
  --gap <n>         Comparison gap in logical pixels (default: 16).
  --output-prefix <path>
                    Output prefix (default:
                    /tmp/love2d-benchmark/neon-relay-comparison).
  --vm <url>        Optional VM service URL. When supplied, switch to
                    comparison mode, wait for a rendered LOVE frame, reset the
                    world, and fix the virtual pointer before capture.
  --pointer <x,y>   Logical LOVE pointer used with --vm (default: 640,360).
  --reset-key <key> LOVE reset key used with --vm (default: r; use "none" to
                    preserve the current world).
  --ready-timeout <seconds>
                    Maximum wait for a ready comparison frame (default: 45).
  --settle-seconds <n>
                    Delay after resize before capture (default: 1).
  --help            Show this help.

Without --vm, the app must already be ready in comparison mode.
EOF
}

window_class="${LOVE2D_COMPARISON_WINDOW_CLASS:-com.example.love2d_gpu_demo}"
logical_size="${LOVE2D_COMPARISON_LOGICAL_SIZE:-800x600}"
chrome_height="${LOVE2D_COMPARISON_CHROME_HEIGHT:-103}"
gap="${LOVE2D_COMPARISON_GAP:-16}"
output_prefix="${LOVE2D_COMPARISON_OUTPUT_PREFIX:-/tmp/love2d-benchmark/neon-relay-comparison}"
vm_service_url="${LOVE2D_VM_SERVICE_URL:-}"
pointer_position="${LOVE2D_POINTER_POSITION:-640,360}"
reset_key="${LOVE2D_RESET_KEY:-r}"
ready_timeout="${LOVE2D_READY_TIMEOUT:-45}"
settle_seconds="${LOVE2D_COMPARISON_SETTLE_SECONDS:-1}"

while (($# > 0)); do
  case "$1" in
    --window-class)
      window_class="$2"
      shift 2
      ;;
    --logical-size)
      logical_size="$2"
      shift 2
      ;;
    --chrome-height)
      chrome_height="$2"
      shift 2
      ;;
    --gap)
      gap="$2"
      shift 2
      ;;
    --output-prefix)
      output_prefix="$2"
      shift 2
      ;;
    --vm)
      vm_service_url="$2"
      shift 2
      ;;
    --pointer)
      pointer_position="$2"
      shift 2
      ;;
    --reset-key)
      reset_key="$2"
      shift 2
      ;;
    --ready-timeout)
      ready_timeout="$2"
      shift 2
      ;;
    --settle-seconds)
      settle_seconds="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command in hyprctl grim jq magick compare; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done
if [[ -n "$vm_service_url" ]] && ! command -v curl >/dev/null 2>&1; then
  echo "curl is required with --vm" >&2
  exit 1
fi
if ! [[ "$logical_size" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
  echo "--logical-size must be WIDTHxHEIGHT" >&2
  exit 2
fi
if ! [[ "$chrome_height" =~ ^[0-9]+$ && "$gap" =~ ^[0-9]+$ &&
        "$settle_seconds" =~ ^[0-9]+$ &&
        "$ready_timeout" =~ ^[1-9][0-9]*$ ]]; then
  echo "--chrome-height, --gap, and --settle-seconds must be non-negative integers; --ready-timeout must be positive" >&2
  exit 2
fi
if ! [[ "$pointer_position" =~ ^-?[0-9]+([.][0-9]+)?,-?[0-9]+([.][0-9]+)?$ ]]; then
  echo "--pointer must be x,y" >&2
  exit 2
fi
IFS=',' read -r pointer_x pointer_y <<<"$pointer_position"

IFS=x read -r logical_width logical_height <<<"$logical_size"
available_width=$((logical_width - gap))
if ((available_width <= 0 || available_width % 2 != 0)); then
  echo "Logical width minus gap must be a positive even number" >&2
  exit 2
fi
pane_width=$((available_width / 2))
scaled_height_product=$((logical_height * pane_width))
if ((scaled_height_product % logical_width != 0)); then
  echo "Comparison pane height is fractional for $logical_size with gap $gap" >&2
  exit 2
fi
pane_height=$((scaled_height_product / logical_width))
if (((logical_height - pane_height) % 2 != 0)); then
  echo "Comparison top offset is fractional for $logical_size with gap $gap" >&2
  exit 2
fi
pane_top=$(((logical_height - pane_height) / 2))
right_pane_x=$((pane_width + gap))
crop_y=$((chrome_height + pane_top))
window_height=$((logical_height + chrome_height))

query_window() {
  hyprctl clients -j | jq -r --arg class "$window_class" '
    .[] | select(.class == $class)
    | [.address, .at[0], .at[1], .size[0], .size[1], .floating] | @tsv
  ' | head -n 1
}

render_state=null
if [[ -n "$vm_service_url" ]]; then
  vm_service_url="${vm_service_url%/}"
  isolate_id="$(
    curl --fail --silent --show-error "$vm_service_url/getVM" |
      jq --exit-status --raw-output '.result.isolates[0].id'
  )"

  extension() {
    local name="$1"
    shift
    curl --fail --silent --show-error --get \
      "$vm_service_url/ext.flutter.love2d.$name" \
      --data-urlencode "isolateId=$isolate_id" \
      "$@"
  }

  wait_for_comparison_frame() {
    local minimum_frame="${1:-0}"
    local state ready mode command_count presented_frame
    for ((attempt = 0; attempt < ready_timeout * 10; attempt++)); do
      state="$(extension getRenderState)"
      ready="$(jq --raw-output '.result.ready' <<<"$state")"
      mode="$(jq --raw-output '.result.mode' <<<"$state")"
      command_count="$(jq --raw-output '.result.commandCount' <<<"$state")"
      presented_frame="$(jq --raw-output '.result.presentedFrame' <<<"$state")"
      if [[ "$ready" == true && "$mode" == comparison &&
            "$command_count" -gt 0 && "$presented_frame" -gt "$minimum_frame" ]]; then
        printf '%s' "$state"
        return 0
      fi
      sleep 0.1
    done
    echo "Timed out waiting for a ready comparison frame" >&2
    jq '.' <<<"$state" >&2
    return 1
  }
fi

geometry="$(query_window)"
if [[ -z "$geometry" ]]; then
  echo "No Flutter window found for class $window_class" >&2
  exit 1
fi
IFS=$'\t' read -r address x y width height floating <<<"$geometry"
if ! [[ "$address" =~ ^0x[0-9a-fA-F]+$ ]]; then
  echo "Invalid Hyprland window address: $address" >&2
  exit 1
fi

hyprctl eval \
  "hl.dispatch(hl.dsp.focus({ window = \"address:$address\" }))" >/dev/null
if [[ "$floating" != "true" ]]; then
  hyprctl eval \
    'hl.dispatch(hl.dsp.window.float({ action = "toggle" }))' >/dev/null
fi
hyprctl eval \
  "hl.dispatch(hl.dsp.window.resize({ x = $logical_width, y = $window_height }))" >/dev/null
hyprctl eval 'hl.dispatch(hl.dsp.window.center())' >/dev/null

if [[ -n "$vm_service_url" ]]; then
  extension setRenderMode --data-urlencode 'mode=comparison' >/dev/null
  render_state="$(wait_for_comparison_frame)"
  extension resetInputState >/dev/null
  render_state="$(extension setVirtualPointer \
    --data-urlencode "x=$pointer_x" \
    --data-urlencode "y=$pointer_y")"
  if [[ "$reset_key" != none ]]; then
    previous_frame="$(jq --raw-output '.result.presentedFrame' <<<"$render_state")"
    extension setVirtualKey \
      --data-urlencode "key=$reset_key" \
      --data-urlencode 'down=true' >/dev/null
    render_state="$(wait_for_comparison_frame "$previous_frame")"
    extension setVirtualKey \
      --data-urlencode "key=$reset_key" \
      --data-urlencode 'down=false' >/dev/null
    previous_frame="$(jq --raw-output '.result.presentedFrame' <<<"$render_state")"
    render_state="$(wait_for_comparison_frame "$previous_frame")"
  fi
fi

if ((settle_seconds > 0)); then
  sleep "$settle_seconds"
fi

geometry="$(query_window)"
IFS=$'\t' read -r address x y width height floating <<<"$geometry"
if [[ "$width" != "$logical_width" || "$height" != "$window_height" ]]; then
  echo "Flutter window resize mismatch: expected=${logical_width}x${window_height} actual=${width}x${height}" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_prefix")"
window_path="${output_prefix}-window.png"
canvas_path="${output_prefix}-canvas.png"
gpu_path="${output_prefix}-gpu.png"
summary_path="${output_prefix}-summary.json"

grim -g "$x,$y ${width}x${height}" "$window_path"
magick "$window_path" \
  -crop "${pane_width}x${pane_height}+0+${crop_y}" +repage "$canvas_path"
magick "$window_path" \
  -crop "${pane_width}x${pane_height}+${right_pane_x}+${crop_y}" +repage "$gpu_path"
rmse="$(compare -metric RMSE "$canvas_path" "$gpu_path" null: 2>&1 || true)"
normalized_rmse="$(sed -n 's/.*(\([^)]*\)).*/\1/p' <<<"$rmse")"
if [[ -z "$normalized_rmse" ]]; then
  echo "Could not parse ImageMagick RMSE: $rmse" >&2
  exit 1
fi

jq -n \
  --arg window "$window_path" \
  --arg canvas "$canvas_path" \
  --arg gpu "$gpu_path" \
  --arg logicalSize "$logical_size" \
  --argjson paneWidth "$pane_width" \
  --argjson paneHeight "$pane_height" \
  --argjson normalizedRmse "$normalized_rmse" \
  --argjson renderState "$render_state" \
  '{
    schemaVersion: 1,
    window: $window,
    canvas: $canvas,
    gpu: $gpu,
    logicalSize: $logicalSize,
    paneWidth: $paneWidth,
    paneHeight: $paneHeight,
    normalizedRmse: $normalizedRmse,
    renderState: ($renderState.result // null)
  }' >"$summary_path"

printf 'Captured synchronized comparison: %s\n' "$window_path"
printf 'Canvas pane: %s\n' "$canvas_path"
printf 'GPU pane: %s\n' "$gpu_path"
printf 'Normalized RMSE: %s\n' "$normalized_rmse"
printf 'Summary: %s\n' "$summary_path"
