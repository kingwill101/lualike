#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: benchmark_signal_lattice.sh [options]

Runs the exact fixed-capacity Neon Relay signal simulation through native LOVE
and Lualike's AST, IR, and lua-bytecode engines. Every trial must produce the
same tick and checksum before timing results are accepted.

Options:
  --frames <n>             Simulated game frames per trial (default: 240).
  --trials <n>             Trials per engine (default: 5).
  --lualike-bin <path>     Precompiled Lualike CLI executable.
  --output-prefix <path>   JSONL and summary output prefix.
  --help                   Show this help.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
example_dir="$(cd "$script_dir/.." && pwd)"
repo_root="$(cd "$example_dir/../../.." && pwd)"
assets_dir="$example_dir/assets"
frame_count=240
trial_count=5
lualike_bin="${LUALIKE_BIN:-}"
output_prefix="${TMPDIR:-.tmp}/love2d-benchmark/signal-lattice"

while (($# > 0)); do
  case "$1" in
    --frames) frame_count="$2"; shift 2 ;;
    --trials) trial_count="$2"; shift 2 ;;
    --lualike-bin) lualike_bin="$2"; shift 2 ;;
    --output-prefix) output_prefix="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! [[ "$frame_count" =~ ^[1-9][0-9]*$ ]] || ((frame_count > 100000)); then
  echo "--frames must be between 1 and 100000" >&2
  exit 2
fi
if ! [[ "$trial_count" =~ ^[1-9][0-9]*$ ]] || ((trial_count > 30)); then
  echo "--trials must be between 1 and 30" >&2
  exit 2
fi
for command in jq love rg timeout; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required" >&2
    exit 1
  fi
done

if [[ -z "$lualike_bin" ]]; then
  lualike_bin="$(
    rg --files "$repo_root/pkgs/lualike/.build_cache" 2>/dev/null |
      rg '/native_build/bundle/bin/main$' | head -n 1 || true
  )"
fi
if [[ -z "$lualike_bin" || ! -x "$lualike_bin" ]]; then
  echo "A precompiled Lualike CLI is required; pass --lualike-bin" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_prefix")"
records_path="${output_prefix}.jsonl"
summary_path="${output_prefix}-summary.json"
: >"$records_path"
expected_tick=""
expected_checksum=""

run_engine() {
  local engine="$1"
  case "$engine" in
    native-love)
      timeout 120s love "$assets_dir" \
        "--signal-kernel-frames=$frame_count"
      ;;
    ast)
      (cd "$assets_dir" && timeout 120s "$lualike_bin" --no-ansi \
        signal_lattice_benchmark.lua "$frame_count")
      ;;
    ir)
      (cd "$assets_dir" && timeout 120s "$lualike_bin" --no-ansi --ir \
        signal_lattice_benchmark.lua "$frame_count")
      ;;
    lua-bytecode)
      (cd "$assets_dir" && timeout 120s "$lualike_bin" --no-ansi \
        --lua-bytecode signal_lattice_benchmark.lua "$frame_count")
      ;;
  esac
}

record_result() {
  local engine="$1"
  local trial_index="$2"
  local output result_line marker frames_field nodes_field substeps_field
  local tick_field checksum_field elapsed_field actual_frames nodes substeps
  local tick checksum elapsed_micros

  output="$(run_engine "$engine")"
  result_line="$(rg 'NEON_SIGNAL_RESULT' <<<"$output" | tail -n 1)"
  read -r marker frames_field nodes_field substeps_field tick_field \
    checksum_field elapsed_field <<<"$result_line"
  actual_frames="${frames_field#frames=}"
  nodes="${nodes_field#nodes=}"
  substeps="${substeps_field#substeps=}"
  tick="${tick_field#tick=}"
  checksum="${checksum_field#checksum=}"
  elapsed_micros="${elapsed_field#elapsedMicros=}"

  if [[ "$marker" != NEON_SIGNAL_RESULT || "$actual_frames" != "$frame_count" ]] ||
     ! [[ "$nodes" =~ ^[1-9][0-9]*$ && "$substeps" =~ ^[1-9][0-9]*$ &&
          "$tick" =~ ^[1-9][0-9]*$ && "$checksum" =~ ^[0-9]+$ &&
          "$elapsed_micros" =~ ^[0-9]+$ ]]; then
    echo "Invalid signal-lattice result from $engine" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  if [[ -z "$expected_tick" ]]; then
    expected_tick="$tick"
    expected_checksum="$checksum"
  elif [[ "$tick" != "$expected_tick" || "$checksum" != "$expected_checksum" ]]; then
    echo "Signal-lattice parity failure for $engine trial $trial_index" >&2
    echo "expected tick=$expected_tick checksum=$expected_checksum" >&2
    echo "actual   tick=$tick checksum=$checksum" >&2
    exit 1
  fi

  jq -cn \
    --arg engine "$engine" \
    --argjson trialIndex "$trial_index" \
    --argjson frames "$actual_frames" \
    --argjson nodes "$nodes" \
    --argjson substeps "$substeps" \
    --argjson tick "$tick" \
    --argjson checksum "$checksum" \
    --argjson elapsedMicros "$elapsed_micros" \
    '{schemaVersion: 1, engine: $engine, trialIndex: $trialIndex,
      frames: $frames, nodes: $nodes, substepsPerFrame: $substeps,
      tick: $tick, checksum: $checksum, elapsedMicros: $elapsedMicros,
      microsPerFrame: ($elapsedMicros / $frames)}' |
    tee -a "$records_path"
}

forward=(native-love ast ir lua-bytecode)
reverse=(lua-bytecode ir ast native-love)
for trial_index in $(seq 1 "$trial_count"); do
  if ((trial_index % 2 == 1)); then
    engines=("${forward[@]}")
  else
    engines=("${reverse[@]}")
  fi
  for engine in "${engines[@]}"; do
    record_result "$engine" "$trial_index"
  done
done

jq -s '
  def median:
    sort as $values |
    ($values | length) as $length |
    if ($length % 2) == 1 then $values[$length / 2 | floor]
    else (($values[$length / 2 - 1] + $values[$length / 2]) / 2)
    end;
  {
    schemaVersion: 1,
    parity: {
      frames: .[0].frames,
      nodes: .[0].nodes,
      substepsPerFrame: .[0].substepsPerFrame,
      tick: .[0].tick,
      checksum: .[0].checksum
    },
    engines: [group_by(.engine)[] | {
      engine: .[0].engine,
      trials: length,
      medianElapsedMicros: ([.[].elapsedMicros] | median),
      medianMicrosPerFrame: ([.[].microsPerFrame] | median),
      minMicrosPerFrame: ([.[].microsPerFrame] | min),
      maxMicrosPerFrame: ([.[].microsPerFrame] | max)
    }]
  }
' "$records_path" >"$summary_path"

jq '.' "$summary_path"
echo "Signal-lattice parity and timing gate passed; wrote $summary_path"
