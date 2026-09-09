#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: score_renderer_regions.sh --native <png> --canvas <png> [--gpu <png>]
                                 --regions <json> --output <json>

Scores native LOVE and Flutter Canvas captures, plus an optional Flutter GPU
capture, over named validated regions. All supplied images must match the
logical size in the region file.

Options:
  --native <path>  Native LOVE capture.
  --canvas <path>  Flutter Canvas capture.
  --gpu <path>     Optional Flutter GPU capture.
  --regions <path> Region manifest JSON.
  --output <path>  Output JSON report.
  --help           Show this help.
EOF
}

native_path=""
canvas_path=""
gpu_path=""
regions_path=""
output_path=""

while (($# > 0)); do
  case "$1" in
    --native) native_path="$2"; shift 2 ;;
    --canvas) canvas_path="$2"; shift 2 ;;
    --gpu) gpu_path="$2"; shift 2 ;;
    --regions) regions_path="$2"; shift 2 ;;
    --output) output_path="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for command in compare jq magick mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done
for required in native_path canvas_path regions_path output_path; do
  if [[ -z "${!required}" ]]; then
    echo "All capture, region, and output paths are required" >&2
    usage >&2
    exit 2
  fi
done
inputs=("$native_path" "$canvas_path" "$regions_path")
if [[ -n "$gpu_path" ]]; then
  inputs+=("$gpu_path")
fi
for input in "${inputs[@]}"; do
  if [[ ! -f "$input" ]]; then
    echo "Input does not exist: $input" >&2
    exit 1
  fi
done

logical_width="$(jq -er '.logicalSize.width' "$regions_path")"
logical_height="$(jq -er '.logicalSize.height' "$regions_path")"
if ! [[ "$logical_width" =~ ^[1-9][0-9]*$ &&
        "$logical_height" =~ ^[1-9][0-9]*$ ]]; then
  echo "Region logical size must contain positive integer width and height" >&2
  exit 2
fi
if ! jq -e --argjson width "$logical_width" --argjson height "$logical_height" '
  .schemaVersion == 1 and
  (.regions | type == "array" and length > 0) and
  all(.regions[];
    (.name | type == "string" and length > 0) and
    ([.x, .y, .width, .height] | all(type == "number" and floor == .)) and
    .x >= 0 and .y >= 0 and .width > 0 and .height > 0 and
    (.x + .width) <= $width and (.y + .height) <= $height) and
  ([.regions[].name] | length == (unique | length))
' "$regions_path" >/dev/null; then
  echo "Region manifest is invalid, out of bounds, or has duplicate names" >&2
  exit 2
fi

image_paths=("$native_path" "$canvas_path")
if [[ -n "$gpu_path" ]]; then
  image_paths+=("$gpu_path")
fi
for image_path in "${image_paths[@]}"; do
  dimensions="$(magick identify -format '%w %h' "$image_path")"
  if [[ "$dimensions" != "$logical_width $logical_height" ]]; then
    echo "Capture size mismatch: $image_path is $dimensions, expected $logical_width $logical_height" >&2
    exit 1
  fi
done

scratch_root="${TMPDIR:-.tmp}"
mkdir -p "$scratch_root"
scratch_dir="$(mktemp -d "$scratch_root/love2d-region-score.XXXXXX")"
cleanup() {
  rm -rf -- "$scratch_dir"
}
trap cleanup EXIT INT TERM

normalized_rmse() {
  local left="$1"
  local right="$2"
  local metric
  metric="$(compare -metric RMSE "$left" "$right" null: 2>&1 || true)"
  sed -n 's/.*(\([^)]*\)).*/\1/p' <<<"$metric"
}

rows_path="$scratch_dir/rows.jsonl"
: >"$rows_path"
while IFS= read -r region; do
  name="$(jq -r '.name' <<<"$region")"
  x="$(jq -r '.x' <<<"$region")"
  y="$(jq -r '.y' <<<"$region")"
  width="$(jq -r '.width' <<<"$region")"
  height="$(jq -r '.height' <<<"$region")"
  geometry="${width}x${height}+${x}+${y}"

  native_crop="$scratch_dir/$name-native.png"
  canvas_crop="$scratch_dir/$name-canvas.png"
  magick "$native_path" -crop "$geometry" +repage "$native_crop"
  magick "$canvas_path" -crop "$geometry" +repage "$canvas_crop"

  native_canvas="$(normalized_rmse "$native_crop" "$canvas_crop")"
  native_gpu=null
  canvas_gpu=null
  if [[ -n "$gpu_path" ]]; then
    gpu_crop="$scratch_dir/$name-gpu.png"
    magick "$gpu_path" -crop "$geometry" +repage "$gpu_crop"
    native_gpu="$(normalized_rmse "$native_crop" "$gpu_crop")"
    canvas_gpu="$(normalized_rmse "$canvas_crop" "$gpu_crop")"
  fi
  jq -cn \
    --arg name "$name" \
    --argjson x "$x" --argjson y "$y" \
    --argjson width "$width" --argjson height "$height" \
    --argjson nativeGpu "$native_gpu" \
    --argjson nativeCanvas "$native_canvas" \
    --argjson canvasGpu "$canvas_gpu" \
    '{name: $name, rect: {x: $x, y: $y, width: $width, height: $height},
      normalizedRmse: {nativeGpu: $nativeGpu,
        nativeCanvas: $nativeCanvas, canvasGpu: $canvasGpu}}' >>"$rows_path"
done < <(jq -c '.regions[]' "$regions_path")

mkdir -p "$(dirname "$output_path")"
jq -s \
  --arg native "$native_path" --arg canvas "$canvas_path" --arg gpu "$gpu_path" \
  --arg regions "$regions_path" \
  --argjson width "$logical_width" --argjson height "$logical_height" \
  '{schemaVersion: 1, logicalSize: {width: $width, height: $height},
    inputs: {native: $native, canvas: $canvas,
      gpu: (if $gpu == "" then null else $gpu end), regions: $regions},
    regions: .}' "$rows_path" >"$output_path"

jq '.' "$output_path"
