#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: benchmark_bytecode_sync_tables_ab.sh --vm <vm-service-url> [options]

Alternates async fallback and synchronous plain-table bytecode operations
inside one profile-mode luaBytecode process. The app must be compiled with:

  --dart-define=LOVE_ENGINE_MODE=luaBytecode
  --dart-define=LUALIKE_RUNTIME_SYNC_PLAIN_TABLE_TUNING=true

Options:
  --vm <url>       VM service URL printed by flutter run (required).
  --pairs <n>      Alternating pairs to collect (default: 7; maximum: 20).
  --samples <n>    Samples per window (default: 240; maximum: 240).
  --mode <name>    canvas or gpu (default: canvas).
  --output-prefix <path>
                   Output directory (default:
                   $TMPDIR/love2d-benchmark/bytecode-sync-tables).
  --help           Show this help.
EOF
}

vm_service_url=""
pair_count=7
sample_count=240
render_mode=canvas
output_prefix="${TMPDIR:-/tmp}/love2d-benchmark/bytecode-sync-tables"

while (($# > 0)); do
  case "$1" in
    --vm) vm_service_url="$2"; shift 2 ;;
    --pairs) pair_count="$2"; shift 2 ;;
    --samples) sample_count="$2"; shift 2 ;;
    --mode) render_mode="$2"; shift 2 ;;
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
if [[ "$render_mode" != canvas && "$render_mode" != gpu ]]; then
  echo "--mode must be canvas or gpu" >&2
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
      label=sync
    else
      label=async
    fi
    output_path="$output_prefix/$(printf '%02d' "$pair")-$label.jsonl"
    "$script_dir/benchmark_relic_breach.sh" \
      --vm "$vm_service_url" \
      --mode "$render_mode" \
      --samples "$sample_count" \
      --trials 1 \
      --hold-key d \
      --pointer 640,360 \
      --reset-key b \
      --warmup-seconds 2 \
      --min-average-commands 100 \
      --sync-plain-table-opcodes "$enabled" \
      --output "$output_path" >/dev/null
    if ! jq --exit-status '
      .engineMode == "luaBytecode" and
      .frameTiming.averageRenderedCommands >= 100
    ' "$output_path" >/dev/null; then
      echo "Invalid luaBytecode workload in $output_path" >&2
      exit 1
    fi
  done
done

pair_rows="$output_prefix/pairs.jsonl"
: >"$pair_rows"
for pair in $(seq 1 "$pair_count"); do
  padded_pair="$(printf '%02d' "$pair")"
  jq -s --argjson pair "$pair" '
    {
      pair: $pair,
      async: {
        updateP95: .[0].frameTiming.p95UpdateMicros,
        updateP99: .[0].frameTiming.p99UpdateMicros,
        cpuP95: .[0].frameTiming.p95CpuFrameMicros,
        cpuP99: .[0].frameTiming.p99CpuFrameMicros,
        renderP95: .[0].frameTiming.p95RenderMicros,
        commands: .[0].frameTiming.averageRenderedCommands
      },
      sync: {
        updateP95: .[1].frameTiming.p95UpdateMicros,
        updateP99: .[1].frameTiming.p99UpdateMicros,
        cpuP95: .[1].frameTiming.p95CpuFrameMicros,
        cpuP99: .[1].frameTiming.p99CpuFrameMicros,
        renderP95: .[1].frameTiming.p95RenderMicros,
        commands: .[1].frameTiming.averageRenderedCommands
      }
    }
  ' "$output_prefix/$padded_pair-async.jsonl" \
    "$output_prefix/$padded_pair-sync.jsonl" >>"$pair_rows"
done

summary_path="$output_prefix/summary.json"
jq -s '
  sort_by(.pair) as $pairs |
  (($pairs | length) / 2 | floor) as $middle |
  def median($path): [$pairs[] | getpath($path)] | sort | .[$middle];
  def pairedMedian($field):
    [$pairs[] | (.sync[$field] - .async[$field])] | sort | .[$middle];
  {
    schemaVersion: 1,
    pairCount: ($pairs | length),
    asyncMedianUpdateP95: median(["async", "updateP95"]),
    syncMedianUpdateP95: median(["sync", "updateP95"]),
    asyncMedianUpdateP99: median(["async", "updateP99"]),
    syncMedianUpdateP99: median(["sync", "updateP99"]),
    asyncMedianCpuP95: median(["async", "cpuP95"]),
    syncMedianCpuP95: median(["sync", "cpuP95"]),
    medianPairedUpdateP95Delta: pairedMedian("updateP95"),
    medianPairedUpdateP99Delta: pairedMedian("updateP99"),
    medianPairedCpuP95Delta: pairedMedian("cpuP95"),
    medianPairedRenderP95Delta: pairedMedian("renderP95"),
    pairs: $pairs
  }
' "$pair_rows" >"$summary_path"

jq '.' "$summary_path"
printf 'Wrote %s\n' "$summary_path" >&2
