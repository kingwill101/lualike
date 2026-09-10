#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: benchmark_generated_strokes_ab.sh --vm <vm-service-url> [options]

Alternates the legacy point-record and typed-coordinate generated-stroke paths
inside one profile-mode process. The app must be compiled with:

  --dart-define=LOVE2D_GPU_RUNTIME_STROKE_TUNING=true

Options:
  --vm <url>       VM service URL printed by flutter run (required).
  --pairs <n>      Alternating pairs to collect (default: 7; maximum: 20).
  --samples <n>    Samples per window (default: 240; maximum: 240).
  --output-prefix <path>
                   Output directory/prefix (default:
                   $TMPDIR/love2d-benchmark/generated-strokes).
  --help           Show this help.
EOF
}

vm_service_url=""
pair_count=7
sample_count=240
output_prefix="${TMPDIR:-/tmp}/love2d-benchmark/generated-strokes"

while (($# > 0)); do
  case "$1" in
    --vm) vm_service_url="$2"; shift 2 ;;
    --pairs) pair_count="$2"; shift 2 ;;
    --samples) sample_count="$2"; shift 2 ;;
    --output-prefix) output_prefix="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$vm_service_url" ]]; then
  echo "--vm is required" >&2
  exit 2
fi
if ! [[ "$pair_count" =~ ^[1-9][0-9]*$ ]] || ((pair_count > 20)); then
  echo "--pairs must be an integer from 1 through 20" >&2
  exit 2
fi
if ! [[ "$sample_count" =~ ^[1-9][0-9]*$ ]] || ((sample_count > 240)); then
  echo "--samples must be an integer from 1 through 240" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$output_prefix"

for pair in $(seq 1 "$pair_count"); do
  if ((pair % 2 == 1)); then
    order=(false true)
  else
    order=(true false)
  fi
  for enabled in "${order[@]}"; do
    if [[ "$enabled" == true ]]; then
      label=typed
    else
      label=records
    fi
    output_path="$output_prefix/$(printf '%02d' "$pair")-$label.jsonl"
    "$script_dir/benchmark_relic_breach.sh" \
      --vm "$vm_service_url" \
      --mode gpu \
      --samples "$sample_count" \
      --trials 1 \
      --hold-key d \
      --pointer 640,360 \
      --reset-key b \
      --warmup-seconds 2 \
      --min-average-commands 100 \
      --typed-generated-strokes "$enabled" \
      --output "$output_path" >/dev/null
  done
done

pair_rows="$output_prefix/pairs.jsonl"
: >"$pair_rows"
for pair in $(seq 1 "$pair_count"); do
  padded_pair="$(printf '%02d' "$pair")"
  jq -s --argjson pair "$pair" '
    {
      pair: $pair,
      records: {
        p95: .[0].frameTiming.p95CpuFrameMicros,
        p99: .[0].frameTiming.p99CpuFrameMicros,
        over120: .[0].frameTiming.cpuFramesOver120HzBudget,
        commands: .[0].frameTiming.averageRenderedCommands
      },
      typed: {
        p95: .[1].frameTiming.p95CpuFrameMicros,
        p99: .[1].frameTiming.p99CpuFrameMicros,
        over120: .[1].frameTiming.cpuFramesOver120HzBudget,
        commands: .[1].frameTiming.averageRenderedCommands
      }
    }
  ' "$output_prefix/$padded_pair-records.jsonl" \
    "$output_prefix/$padded_pair-typed.jsonl" >>"$pair_rows"
done

summary_path="$output_prefix/summary.json"
jq -s '
  sort_by(.pair) as $pairs |
  (($pairs | length) / 2 | floor) as $middle |
  {
    schemaVersion: 1,
    pairCount: ($pairs | length),
    recordsMedianP95:
      ($pairs | map(.records.p95) | sort | .[$middle]),
    typedMedianP95:
      ($pairs | map(.typed.p95) | sort | .[$middle]),
    recordsMedianP99:
      ($pairs | map(.records.p99) | sort | .[$middle]),
    typedMedianP99:
      ($pairs | map(.typed.p99) | sort | .[$middle]),
    medianPairedP95Delta:
      ($pairs | map(.typed.p95 - .records.p95) | sort | .[$middle]),
    medianPairedP99Delta:
      ($pairs | map(.typed.p99 - .records.p99) | sort | .[$middle]),
    recordsFramesOver120Hz:
      ($pairs | map(.records.over120) | add),
    typedFramesOver120Hz:
      ($pairs | map(.typed.over120) | add),
    pairs: $pairs
  }
' "$pair_rows" >"$summary_path"

jq '.' "$summary_path"
printf 'Wrote %s\n' "$summary_path" >&2
