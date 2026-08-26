#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: benchmark_relic_breach.sh --vm <vm-service-url> [options]

Collects one JSONL timing record for Canvas, GPU, and comparison modes.

Options:
  --vm <url>       VM service URL printed by `flutter run --print-dtd`.
  --isolate <id>   Isolate id; defaults to the first live isolate.
  --samples <n>    Samples required per mode (default: 240).
  --mode <name>    Measure only canvas, gpu, or comparison (default: all).
  --hold-key <key> Hold a LOVE key during each timing window (for example d).
  --reset-key <key>
                   Press this key before every trial and wait for it to render
                   (default: r; use "none" to preserve the current world).
  --warmup-seconds <n>
                   Settle each renderer before resetting timing (default: 2).
  --output <path>  JSONL output path (default: /tmp/love2d-benchmark/relic-timings.jsonl).
  --help           Show this help.
EOF
}

vm_service_url="${LOVE2D_VM_SERVICE_URL:-}"
isolate_id="${LOVE2D_ISOLATE_ID:-}"
sample_target="${LOVE2D_SAMPLE_TARGET:-240}"
requested_mode="${LOVE2D_RENDER_MODE:-}"
hold_key="${LOVE2D_HOLD_KEY:-}"
reset_key="${LOVE2D_RESET_KEY:-r}"
warmup_seconds="${LOVE2D_WARMUP_SECONDS:-2}"
output_path="${LOVE2D_BENCHMARK_OUTPUT:-/tmp/love2d-benchmark/relic-timings.jsonl}"

while (($# > 0)); do
  case "$1" in
    --vm)
      vm_service_url="$2"
      shift 2
      ;;
    --isolate)
      isolate_id="$2"
      shift 2
      ;;
    --samples)
      sample_target="$2"
      shift 2
      ;;
    --mode)
      requested_mode="$2"
      shift 2
      ;;
    --hold-key)
      hold_key="$2"
      shift 2
      ;;
    --reset-key)
      reset_key="$2"
      shift 2
      ;;
    --warmup-seconds)
      warmup_seconds="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
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

if [[ -z "$vm_service_url" ]]; then
  echo "--vm or LOVE2D_VM_SERVICE_URL is required" >&2
  usage >&2
  exit 2
fi

if ! [[ "$sample_target" =~ ^[1-9][0-9]*$ ]]; then
  echo "--samples must be a positive integer" >&2
  exit 2
fi

if [[ -n "$requested_mode" &&
      "$requested_mode" != "canvas" &&
      "$requested_mode" != "gpu" &&
      "$requested_mode" != "comparison" ]]; then
  echo "--mode must be one of: canvas, gpu, comparison" >&2
  exit 2
fi

if ! [[ "$warmup_seconds" =~ ^[0-9]+$ ]]; then
  echo "--warmup-seconds must be a non-negative integer" >&2
  exit 2
fi

vm_service_url="${vm_service_url%/}"
mkdir -p "$(dirname "$output_path")"

if [[ -z "$isolate_id" ]]; then
  isolate_id="$(curl --fail --silent --show-error "$vm_service_url/getVM" | jq --exit-status --raw-output '.result.isolates[0].id')"
fi

extension() {
  local name="$1"
  shift
  curl --fail --silent --show-error --get \
    "$vm_service_url/ext.flutter.love2d.$name" \
    --data-urlencode "isolateId=$isolate_id" \
    "$@"
}

wait_for_ready_mode() {
  local expected_mode="$1"
  local state ready mode
  for _ in $(seq 1 30); do
    state="$(extension getRenderState)"
    ready="$(jq --raw-output '.result.ready' <<<"$state")"
    mode="$(jq --raw-output '.result.mode' <<<"$state")"
    if [[ "$ready" == true && "$mode" == "$expected_mode" ]]; then
      printf '%s' "$state"
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for mode=$expected_mode to become ready" >&2
  jq '.' <<<"$state" >&2
  return 1
}

wait_for_samples() {
  local expected_mode="$1"
  local state count ready mode
  for _ in $(seq 1 90); do
    state="$(extension getRenderState)"
    ready="$(jq --raw-output '.result.ready' <<<"$state")"
    mode="$(jq --raw-output '.result.mode' <<<"$state")"
    count="$(jq --raw-output '.result.frameTiming.sampleCount' <<<"$state")"
    if [[ "$ready" == true && "$mode" == "$expected_mode" && "$count" -ge "$sample_target" ]]; then
      printf '%s' "$state"
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for $sample_target samples in mode=$expected_mode" >&2
  jq '.' <<<"$state" >&2
  return 1
}

wait_for_presented_frame_after() {
  local expected_mode="$1"
  local previous_frame="$2"
  local state ready mode presented_frame
  for _ in $(seq 1 60); do
    state="$(extension getRenderState)"
    ready="$(jq --raw-output '.result.ready' <<<"$state")"
    mode="$(jq --raw-output '.result.mode' <<<"$state")"
    presented_frame="$(jq --raw-output '.result.presentedFrame' <<<"$state")"
    if [[ "$ready" == true &&
          "$mode" == "$expected_mode" &&
          "$presented_frame" -gt "$previous_frame" ]]; then
      printf '%s' "$state"
      return 0
    fi
    sleep 0.1
  done
  echo "Timed out waiting for mode=$expected_mode after frame=$previous_frame" >&2
  jq '.' <<<"$state" >&2
  return 1
}

: >"$output_path"
modes=(canvas gpu comparison)
if [[ -n "$requested_mode" ]]; then
  modes=("$requested_mode")
fi
for mode in "${modes[@]}"; do
  extension setRenderMode --data-urlencode "mode=$mode" >/dev/null
  state="$(wait_for_ready_mode "$mode")"
  extension resetInputState >/dev/null
  if [[ "$reset_key" != "none" ]]; then
    presented_frame="$(jq --raw-output '.result.presentedFrame' <<<"$state")"
    extension setVirtualKey \
      --data-urlencode "key=$reset_key" \
      --data-urlencode 'down=true' >/dev/null
    state="$(wait_for_presented_frame_after "$mode" "$presented_frame")"
    extension setVirtualKey \
      --data-urlencode "key=$reset_key" \
      --data-urlencode 'down=false' >/dev/null
    presented_frame="$(jq --raw-output '.result.presentedFrame' <<<"$state")"
    wait_for_presented_frame_after "$mode" "$presented_frame" >/dev/null
  fi
  if [[ -n "$hold_key" ]]; then
    extension setVirtualKey \
      --data-urlencode "key=$hold_key" \
      --data-urlencode 'down=true' >/dev/null
  fi
  if ((warmup_seconds > 0)); then
    sleep "$warmup_seconds"
  fi
  extension resetFrameTiming >/dev/null
  state="$(wait_for_samples "$mode")"
  if [[ -n "$hold_key" ]]; then
    extension setVirtualKey \
      --data-urlencode "key=$hold_key" \
      --data-urlencode 'down=false' >/dev/null
  fi
  jq -c --arg trial_mode "$mode" '.result + {trialMode: $trial_mode}' <<<"$state" | tee -a "$output_path"
done

echo "Wrote $output_path" >&2
