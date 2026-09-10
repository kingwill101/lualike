#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: profile_renderer_lifetime.sh --vm <vm-service-url> [options]

Recreates the LOVE harness across Canvas, GPU, and comparison modes, forces
Dart GC, and fails if discarded runtime contexts remain reachable.

The app must be compiled with:
  --dart-define=LOVE_ENGINE_MODE=luaBytecode
  --dart-define=LOVE2D_DEMO_RECREATE_HARNESS_ON_MODE_SWITCH=true

Options:
  --vm <url>               Flutter VM service URL (required).
  --cycles <n>             Complete Canvas/GPU/comparison cycles (default: 4).
  --output-prefix <path>   Raw/summary output prefix.
  --max-heap-bytes <n>     Optional retained Dart heap ceiling.
  --max-love-images <n>    Optional retained LoveImage ceiling.
  --help                   Show this help.
EOF
}

vm_service_url=""
cycle_count=4
output_prefix="${TMPDIR:-.tmp}/love2d-benchmark/renderer-lifetime"
max_heap_bytes=""
max_love_images=""

while (($# > 0)); do
  case "$1" in
    --vm) vm_service_url="$2"; shift 2 ;;
    --cycles) cycle_count="$2"; shift 2 ;;
    --output-prefix) output_prefix="$2"; shift 2 ;;
    --max-heap-bytes) max_heap_bytes="$2"; shift 2 ;;
    --max-love-images) max_love_images="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$vm_service_url" ]]; then
  echo "--vm is required" >&2
  exit 2
fi
if ! [[ "$cycle_count" =~ ^[1-9][0-9]*$ ]] || ((cycle_count > 50)); then
  echo "--cycles must be between 1 and 50" >&2
  exit 2
fi
for value in "$max_heap_bytes" "$max_love_images"; do
  if [[ -n "$value" && ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "Optional ceilings must be positive integers" >&2
    exit 2
  fi
done
for command in curl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done

vm_service_url="${vm_service_url%/}"
mkdir -p "$(dirname "$output_prefix")"
isolate_id="$(curl --fail --silent --show-error "$vm_service_url/getVM" |
  jq --exit-status --raw-output '.result.isolates[0].id')"

extension() {
  local name="$1"
  shift
  curl --fail --silent --show-error --get \
    "$vm_service_url/ext.flutter.love2d.$name" \
    --data-urlencode "isolateId=$isolate_id" "$@"
}

vm_rpc() {
  local name="$1"
  shift
  curl --fail --silent --show-error --get "$vm_service_url/$name" \
    --data-urlencode "isolateId=$isolate_id" "$@"
}

wait_for_mode() {
  local expected_mode="$1"
  local state
  for _ in $(seq 1 900); do
    state="$(extension getRenderState)"
    if [[ "$(jq -r '.result.ready' <<<"$state")" == true &&
          "$(jq -r '.result.mode' <<<"$state")" == "$expected_mode" &&
          "$(jq -r '.result.commandCount' <<<"$state")" -gt 0 ]]; then
      printf '%s' "$state"
      return 0
    fi
    sleep 0.1
  done
  echo "Timed out waiting for a complete $expected_mode runtime" >&2
  jq '.' <<<"$state" >&2
  return 1
}

state="$(extension getRenderState)"
if ! jq --exit-status \
  '.result.recreateHarnessOnModeSwitch == true and
   .result.engineMode == "luaBytecode" and
   .result.gpuAvailable == true' <<<"$state" >/dev/null; then
  echo "The app must use luaBytecode, diagnostic harness recreation, and Flutter GPU" >&2
  jq '.result | {engineMode, recreateHarnessOnModeSwitch, gpuAvailable}' \
    <<<"$state" >&2
  exit 1
fi
wait_for_mode "$(jq -r '.result.mode' <<<"$state")" >/dev/null

generation_count=1
for cycle in $(seq 1 "$cycle_count"); do
  for mode in canvas gpu comparison; do
    extension setRenderMode --data-urlencode "mode=$mode" >/dev/null
    state="$(wait_for_mode "$mode")"
    generation_count=$((generation_count + 1))
    printf 'generation=%d cycle=%d mode=%s frame=%s commands=%s\n' \
      "$generation_count" "$cycle" "$mode" \
      "$(jq -r '.result.presentedFrame' <<<"$state")" \
      "$(jq -r '.result.commandCount' <<<"$state")"
  done
done

vm_rpc getAllocationProfile --data-urlencode 'gc=true' >/dev/null
sleep 1
allocation_path="${output_prefix}-allocation.json"
memory_path="${output_prefix}-memory.json"
summary_path="${output_prefix}-summary.json"
vm_rpc getAllocationProfile --data-urlencode 'gc=true' >"$allocation_path"
vm_rpc getMemoryUsage >"$memory_path"

jq -n \
  --argjson generations "$generation_count" \
  --slurpfile allocation "$allocation_path" \
  --slurpfile memory "$memory_path" '
  def class($name):
    ([$allocation[0].result.members[] | select(.class.name == $name)][0] //
      {instancesCurrent: 0, bytesCurrent: 0});
  {
    schemaVersion: 1,
    completedRuntimeGenerations: $generations,
    heapUsage: $memory[0].result.heapUsage,
    externalUsage: $memory[0].result.externalUsage,
    retained: {
      luaBytecodeRuntimes: class("LuaBytecodeRuntime").instancesCurrent,
      loveRuntimeContexts: class("LoveRuntimeContext").instancesCurrent,
      loveFlameHosts: class("LoveFlameHost").instancesCurrent,
      loveFlameHarnessGames: class("LoveFlameHarnessGame").instancesCurrent,
      loveImages: class("LoveImage").instancesCurrent,
      loveImageData: class("LoveImageData").instancesCurrent,
      uint8Lists: class("_Uint8List").instancesCurrent,
      uint8ListBytes: class("_Uint8List").bytesCurrent,
      values: class("Value").instancesCurrent
    }
  }
  ' >"$summary_path"

jq '.' "$summary_path"

if ! jq --exit-status '
  .retained.luaBytecodeRuntimes == 1 and
  .retained.loveRuntimeContexts == 1 and
  .retained.loveFlameHosts == 1 and
  .retained.loveFlameHarnessGames == 1
  ' "$summary_path" >/dev/null; then
  echo "Discarded LOVE runtime ownership remains after forced GC" >&2
  exit 1
fi
if [[ -n "$max_heap_bytes" ]] &&
   [[ "$(jq -r '.heapUsage' "$summary_path")" -gt "$max_heap_bytes" ]]; then
  echo "Retained heap exceeds --max-heap-bytes=$max_heap_bytes" >&2
  exit 1
fi
if [[ -n "$max_love_images" ]] &&
   [[ "$(jq -r '.retained.loveImages' "$summary_path")" -gt "$max_love_images" ]]; then
  echo "Retained LoveImage count exceeds --max-love-images=$max_love_images" >&2
  exit 1
fi

echo "Renderer lifetime gate passed; wrote $summary_path"
