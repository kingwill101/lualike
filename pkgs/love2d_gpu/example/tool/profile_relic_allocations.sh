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
  --samples <n>    Frame samples in the measured window (default: 240;
                   maximum: 240).
  --mode <name>    canvas, gpu, or comparison (default: gpu).
  --hold-key <key> Hold a LOVE key during the timing window (default: d).
  --pointer <x,y>  Logical LOVE pointer used for every trial (default: 640,360;
                   use "none" to preserve the current pointer position).
  --reset-key <key>
                   Reset key passed to the timing helper (default: r).
  --warmup-seconds <n>
                   Settle after reset before measuring (default: 2).
  --min-average-commands <n>
                   Reject the profile window when average rendered commands
                   fall below this workload floor (default: disabled).
  --output-prefix <path>
                   Prefix for -timing.jsonl, -profile.json,
                   -profile.json.reset, and -summary.json outputs (default:
                   /tmp/love2d-benchmark/relic-allocations).
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
pointer_position="${LOVE2D_POINTER_POSITION:-640,360}"
reset_key="${LOVE2D_RESET_KEY:-r}"
warmup_seconds="${LOVE2D_WARMUP_SECONDS:-2}"
min_average_commands="${LOVE2D_MIN_AVERAGE_COMMANDS:-}"
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
    --pointer)
      pointer_position="$2"
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
    --min-average-commands)
      min_average_commands="$2"
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
if ! [[ "$sample_target" =~ ^[1-9][0-9]*$ ]] || ((sample_target > 240)); then
  echo "--samples must be an integer from 1 through 240" >&2
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
if [[ -n "$min_average_commands" ]] &&
    ! [[ "$min_average_commands" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--min-average-commands must be a non-negative number" >&2
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

timing_path="${output_prefix}-timing.jsonl"
profile_path="${output_prefix}-profile.json"
summary_path="${output_prefix}-summary.json"

benchmark_args=(
  --vm "$vm_service_url"
  --isolate "$isolate_id"
  --samples "$sample_target"
  --mode "$requested_mode"
  --pointer "$pointer_position"
  --reset-key "$reset_key"
  --warmup-seconds "$warmup_seconds"
  --output "$timing_path"
  --allocation-profile-output "$profile_path"
)
if [[ -n "$hold_key" && "$hold_key" != "none" ]]; then
  benchmark_args+=(--hold-key "$hold_key")
fi
if [[ -n "$min_average_commands" ]]; then
  benchmark_args+=(--min-average-commands "$min_average_commands")
fi

bash "$script_dir/benchmark_relic_breach.sh" "${benchmark_args[@]}" >/dev/null

jq -n \
  --arg profilePath "$profile_path" \
  --arg timingPath "$timing_path" \
  --slurpfile profile "$profile_path" \
  --slurpfile baseline "$profile_path.reset" \
  --slurpfile timing "$timing_path" '
    def accumulated($snapshot; $name):
      ([
        $snapshot.result.members[]
        | select(.class.name == $name)
        | .instancesAccumulated
      ][0] // 0);
    def count($name):
      accumulated($profile[0]; $name) - accumulated($baseline[0]; $name);
    def baselineMember($member):
      ([
        $baseline[0].result.members[]
        | select(.class.id == $member.class.id)
      ][0] // {});
    (
      $profile[0].result.members
      | map(
          . as $member
          | (baselineMember($member)) as $before
          | {
              class: .class.name,
              instances:
                ((.instancesAccumulated // 0) -
                 ($before.instancesAccumulated // 0)),
              bytes:
                ((.accumulatedSize // 0) -
                 ($before.accumulatedSize // 0)),
              currentInstances: .instancesCurrent,
              currentBytes: .bytesCurrent
            }
        )
    ) as $deltas |
    (
      $deltas
      | map(select(.instances < 0 or .bytes < 0))
    ) as $negativeDeltas |
    (
      $profile[0].result.dateLastAccumulatorReset ==
      $baseline[0].result.dateLastAccumulatorReset
    ) as $resetMatches |
    ($resetMatches and ($negativeDeltas | length == 0)) as $validCounters |
    (count("Environment")) as $environmentCount |
    {
      schemaVersion: 3,
      profilePath: $profilePath,
      timingPath: $timingPath,
      timing: $timing[0],
      allocation: {
        dateLastAccumulatorReset:
          $profile[0].result.dateLastAccumulatorReset,
        counterValidation: {
          valid: $validCounters,
          resetTimestampMatches: $resetMatches,
          negativeClasses: $negativeDeltas,
          message:
            (if $validCounters
             then "VM allocation accumulators were monotonic in this window"
             else "VM allocation accumulators were not monotonic; do not interpret deltas as allocation counts"
             end)
        },
        memoryUsage: $profile[0].result.memoryUsage,
        environmentNormalized:
          (if $validCounters
           then {
             environmentCount: $environmentCount,
             mapsPerEnvironment:
               (if $environmentCount > 0
                then count("_Map") / $environmentCount
                else null
                end),
             fixedListsPerEnvironment:
               (if $environmentCount > 0
                then count("_List") / $environmentCount
                else null
                end),
             growableListsPerEnvironment:
               (if $environmentCount > 0
                then count("_GrowableList") / $environmentCount
                else null
                end)
           }
           else null
           end),
        topClasses:
          (if $validCounters
           then (
             $deltas
             | map(select(.bytes > 0))
             | sort_by(.bytes)
             | reverse
             | .[:30]
           )
           else []
           end)
      }
    }
  ' >"$summary_path"

jq '.' "$summary_path"
if ! jq --exit-status '.allocation.counterValidation.valid == true' \
  "$summary_path" >/dev/null; then
  printf '%s\n' \
    'VM allocation counters were non-monotonic; use exact runtime diagnostics or allocation traces instead.' >&2
  exit 1
fi
printf 'Wrote %s\n' "$summary_path" >&2
