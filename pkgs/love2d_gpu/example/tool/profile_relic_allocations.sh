#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: profile_relic_allocations.sh --vm <vm-service-url> [options]

Captures a Dart VM allocation profile around one deterministic Relic Breach
timing window and reports allocation counts normalized per Environment.

Options:
  --vm <url>       VM service URL printed by `flutter run --print-dtd`.
  --isolate <id>   Isolate id; defaults to the first live isolate.
  --samples <n>    Frame samples in the measured window (default: 240).
  --mode <name>    canvas, gpu, or comparison (default: gpu).
  --hold-key <key> Hold a LOVE key during the timing window (default: d).
  --reset-key <key>
                   Reset key passed to the timing helper (default: r).
  --warmup-seconds <n>
                   Settle after reset before measuring (default: 2).
  --output-prefix <path>
                   Prefix for -reset.json, -timing.jsonl, -profile.json, and
                   -summary.json outputs (default: /tmp/love2d-benchmark/relic-allocations).
  --help           Show this help.

Run this against a fresh profile-mode app. The helper deliberately does not
request a service GC because that pause can change simulation catch-up work.
EOF
}

vm_service_url="${LOVE2D_VM_SERVICE_URL:-}"
isolate_id="${LOVE2D_ISOLATE_ID:-}"
sample_target="${LOVE2D_SAMPLE_TARGET:-240}"
requested_mode="${LOVE2D_RENDER_MODE:-gpu}"
hold_key="${LOVE2D_HOLD_KEY:-d}"
reset_key="${LOVE2D_RESET_KEY:-r}"
warmup_seconds="${LOVE2D_WARMUP_SECONDS:-2}"
output_prefix="${LOVE2D_ALLOCATION_OUTPUT_PREFIX:-/tmp/love2d-benchmark/relic-allocations}"

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
    --output-prefix)
      output_prefix="$2"
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
if [[ "$requested_mode" != "canvas" &&
      "$requested_mode" != "gpu" &&
      "$requested_mode" != "comparison" ]]; then
  echo "--mode must be one of: canvas, gpu, comparison" >&2
  exit 2
fi
if ! [[ "$warmup_seconds" =~ ^[0-9]+$ ]]; then
  echo "--warmup-seconds must be a non-negative integer" >&2
  exit 2
fi
if [[ -z "$output_prefix" ]]; then
  echo "--output-prefix must not be empty" >&2
  exit 2
fi

vm_service_url="${vm_service_url%/}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$(dirname "$output_prefix")"

if [[ -z "$isolate_id" ]]; then
  isolate_id="$(curl --fail --silent --show-error "$vm_service_url/getVM" |
    jq --exit-status --raw-output '.result.isolates[0].id')"
fi

allocation_profile() {
  curl --fail --silent --show-error --get \
    "$vm_service_url/getAllocationProfile" \
    --data-urlencode "isolateId=$isolate_id" \
    "$@"
}

reset_path="${output_prefix}-reset.json"
timing_path="${output_prefix}-timing.jsonl"
profile_path="${output_prefix}-profile.json"
summary_path="${output_prefix}-summary.json"

allocation_profile --data-urlencode 'reset=true' >"$reset_path"

benchmark_args=(
  --vm "$vm_service_url"
  --isolate "$isolate_id"
  --samples "$sample_target"
  --mode "$requested_mode"
  --reset-key "$reset_key"
  --warmup-seconds "$warmup_seconds"
  --output "$timing_path"
)
if [[ -n "$hold_key" && "$hold_key" != "none" ]]; then
  benchmark_args+=(--hold-key "$hold_key")
fi

bash "$script_dir/benchmark_relic_breach.sh" "${benchmark_args[@]}" >/dev/null
allocation_profile >"$profile_path"

jq -n \
  --arg profilePath "$profile_path" \
  --arg timingPath "$timing_path" \
  --slurpfile profile "$profile_path" \
  --slurpfile timing "$timing_path" '
    def count($name):
      ([
        $profile[0].result.members[]
        | select(.class.name == $name)
        | .instancesAccumulated
      ][0] // 0);
    (count("Environment")) as $environmentCount |
    {
      schemaVersion: 1,
      profilePath: $profilePath,
      timingPath: $timingPath,
      timing: $timing[0],
      allocation: {
        dateLastAccumulatorReset:
          $profile[0].result.dateLastAccumulatorReset,
        memoryUsage: $profile[0].result.memoryUsage,
        environmentNormalized: {
          environmentCount: $environmentCount,
          mapsPerEnvironment:
            (if $environmentCount > 0
             then count("_Map") / $environmentCount
             else null
             end),
          growableListsPerEnvironment:
            (if $environmentCount > 0
             then count("_GrowableList") / $environmentCount
             else null
             end)
        },
        topClasses: (
          $profile[0].result.members
          | map(select((.accumulatedSize // 0) > 0))
          | sort_by(.accumulatedSize)
          | reverse
          | .[:30]
          | map({
              class: .class.name,
              instances: .instancesAccumulated,
              bytes: .accumulatedSize
            })
        )
      }
    }
  ' >"$summary_path"

jq '.' "$summary_path"
printf 'Wrote %s\n' "$summary_path" >&2
