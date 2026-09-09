#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: benchmark_relic_breach.sh --vm <vm-service-url> [options]

Collects one JSONL timing record for Canvas, GPU, and comparison modes.

Options:
  --vm <url>       VM service URL printed by `flutter run --print-dtd`.
  --isolate <id>   Isolate id; defaults to the first live isolate.
  --samples <n>    Samples required per mode (default: 240; maximum: 240).
  --trials <n>     Independent windows per mode (default: 1; maximum: 20).
  --mode <name>    Measure only canvas, gpu, or comparison (default: all).
  --hold-key <key> Hold a LOVE key during each timing window (for example d).
  --pointer <x,y>  Logical LOVE pointer used for every trial (default: 640,360;
                   use "none" to preserve the current pointer position).
  --reset-key <key>
                   Press this key before every trial and wait for it to render
                   (default: r; use "none" to preserve the current world).
  --expected-workload <name>
                   Require this game-reported workload and an advancing tick.
  --warmup-seconds <n>
                   Settle each renderer before resetting timing (default: 2).
  --min-average-commands <n>
                   Reject a trial whose average rendered command count is
                   below this workload floor (default: disabled).
  --allow-scaled-presentation
                   Permit a presentation rectangle other than exact 1:1.
                   Exact logical pixels are required by default.
  --canvas-rough-curves <true|false>
                   Select native-style or stroked-Path Canvas rough curves in
                   a build compiled with
                   LOVE_CANVAS_RUNTIME_ROUGH_CURVE_TUNING=true.
  --canvas-straight-alpha-textures <true|false>
                   Select premultiplied or straight-alpha Canvas filtering in
                   a build compiled with
                   LOVE_CANVAS_RUNTIME_STRAIGHT_ALPHA_TEXTURE_TUNING=true.
  --typed-generated-strokes <true|false>
                   Select the generated circle/arc stroke path in a build
                   compiled with LOVE2D_GPU_RUNTIME_STROKE_TUNING=true.
  --rough-line-shader <true|false>
                   Select the native rough-line shader in a build compiled
                   with LOVE2D_GPU_RUNTIME_ROUGH_LINE_SHADER_TUNING=true.
  --rough-axis-runs <true|false>
                   Select exact axis-aligned rough-line runs in a build compiled
                   with LOVE2D_GPU_RUNTIME_ROUGH_AXIS_RUN_TUNING=true.
  --direct-sprite-geometry <true|false>
                   Select direct affine or legacy matrix sprite expansion in
                   a build compiled with
                   LOVE2D_GPU_RUNTIME_SPRITE_GEOMETRY_TUNING=true.
  --sync-plain-table-opcodes <true|false>
                   Select synchronous or async plain-table bytecode ops in a
                   build compiled with
                   LUALIKE_RUNTIME_SYNC_PLAIN_TABLE_TUNING=true.
  --output <path>  JSONL output path (default: $TMPDIR/love2d-benchmark/relic-timings.jsonl).
  --cpu-profile-output <path>
                   Write VM CPU samples covering the exact measured window.
                   Requires one explicit --mode and --trials 1.
  --allocation-profile-output <path>
                   Write VM allocation snapshots bracketing the exact measured
                   window. The reset baseline is written to <path>.reset.
                   Requires one explicit --mode and --trials 1.
  --help           Show this help.
EOF
}

vm_service_url="${LOVE2D_VM_SERVICE_URL:-}"
isolate_id="${LOVE2D_ISOLATE_ID:-}"
sample_target="${LOVE2D_SAMPLE_TARGET:-240}"
trial_count="${LOVE2D_TRIAL_COUNT:-1}"
requested_mode="${LOVE2D_RENDER_MODE:-}"
hold_key="${LOVE2D_HOLD_KEY:-}"
pointer_position="${LOVE2D_POINTER_POSITION:-640,360}"
reset_key="${LOVE2D_RESET_KEY:-r}"
expected_workload="${LOVE2D_EXPECTED_WORKLOAD:-}"
warmup_seconds="${LOVE2D_WARMUP_SECONDS:-2}"
min_average_commands="${LOVE2D_MIN_AVERAGE_COMMANDS:-}"
require_exact_presentation=true
canvas_rough_curves=""
canvas_straight_alpha_textures=""
typed_generated_strokes=""
rough_line_shader=""
rough_axis_runs=""
direct_sprite_geometry=""
sync_plain_table_opcodes=""
output_path="${LOVE2D_BENCHMARK_OUTPUT:-${TMPDIR:-.tmp}/love2d-benchmark/relic-timings.jsonl}"
cpu_profile_output="${LOVE2D_CPU_PROFILE_OUTPUT:-}"
allocation_profile_output="${LOVE2D_ALLOCATION_PROFILE_OUTPUT:-}"

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
    --trials)
      trial_count="$2"
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
    --expected-workload)
      expected_workload="$2"
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
    --allow-scaled-presentation)
      require_exact_presentation=false
      shift
      ;;
    --canvas-rough-curves)
      canvas_rough_curves="$2"
      shift 2
      ;;
    --canvas-straight-alpha-textures)
      canvas_straight_alpha_textures="$2"
      shift 2
      ;;
    --typed-generated-strokes)
      typed_generated_strokes="$2"
      shift 2
      ;;
    --rough-line-shader)
      rough_line_shader="$2"
      shift 2
      ;;
    --rough-axis-runs)
      rough_axis_runs="$2"
      shift 2
      ;;
    --direct-sprite-geometry)
      direct_sprite_geometry="$2"
      shift 2
      ;;
    --sync-plain-table-opcodes)
      sync_plain_table_opcodes="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    --cpu-profile-output)
      cpu_profile_output="$2"
      shift 2
      ;;
    --allocation-profile-output)
      allocation_profile_output="$2"
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

if ! [[ "$trial_count" =~ ^[1-9][0-9]*$ ]] || ((trial_count > 20)); then
  echo "--trials must be an integer from 1 through 20" >&2
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
if [[ -n "$min_average_commands" ]] &&
    ! [[ "$min_average_commands" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--min-average-commands must be a non-negative number" >&2
  exit 2
fi
if [[ -n "$cpu_profile_output" ]] &&
    { [[ -z "$requested_mode" ]] || ((trial_count != 1)); }; then
  echo "--cpu-profile-output requires one explicit --mode and --trials 1" >&2
  exit 2
fi
if [[ -n "$allocation_profile_output" ]] &&
    { [[ -z "$requested_mode" ]] || ((trial_count != 1)); }; then
  echo "--allocation-profile-output requires one explicit --mode and --trials 1" >&2
  exit 2
fi
if [[ -n "$typed_generated_strokes" &&
      "$typed_generated_strokes" != true &&
      "$typed_generated_strokes" != false ]]; then
  echo "--typed-generated-strokes must be true or false" >&2
  exit 2
fi
if [[ -n "$canvas_rough_curves" &&
      "$canvas_rough_curves" != true &&
      "$canvas_rough_curves" != false ]]; then
  echo "--canvas-rough-curves must be true or false" >&2
  exit 2
fi
if [[ -n "$canvas_straight_alpha_textures" &&
      "$canvas_straight_alpha_textures" != true &&
      "$canvas_straight_alpha_textures" != false ]]; then
  echo "--canvas-straight-alpha-textures must be true or false" >&2
  exit 2
fi
if [[ -n "$rough_line_shader" &&
      "$rough_line_shader" != true &&
      "$rough_line_shader" != false ]]; then
  echo "--rough-line-shader must be true or false" >&2
  exit 2
fi
if [[ -n "$rough_axis_runs" &&
      "$rough_axis_runs" != true &&
      "$rough_axis_runs" != false ]]; then
  echo "--rough-axis-runs must be true or false" >&2
  exit 2
fi
if [[ -n "$direct_sprite_geometry" &&
      "$direct_sprite_geometry" != true &&
      "$direct_sprite_geometry" != false ]]; then
  echo "--direct-sprite-geometry must be true or false" >&2
  exit 2
fi
if [[ -n "$sync_plain_table_opcodes" &&
      "$sync_plain_table_opcodes" != true &&
      "$sync_plain_table_opcodes" != false ]]; then
  echo "--sync-plain-table-opcodes must be true or false" >&2
  exit 2
fi

pointer_x=""
pointer_y=""
if [[ "$pointer_position" != "none" ]]; then
  if ! [[ "$pointer_position" =~ ^-?[0-9]+([.][0-9]+)?,-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "--pointer must be x,y or none" >&2
    exit 2
  fi
  IFS=',' read -r pointer_x pointer_y <<<"$pointer_position"
fi

vm_service_url="${vm_service_url%/}"
mkdir -p "$(dirname "$output_path")"
if [[ -n "$cpu_profile_output" ]]; then
  mkdir -p "$(dirname "$cpu_profile_output")"
fi
if [[ -n "$allocation_profile_output" ]]; then
  mkdir -p "$(dirname "$allocation_profile_output")"
fi

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

if [[ -n "$canvas_rough_curves" ]]; then
  tuning_state="$(extension setCanvasRoughCurves \
    --data-urlencode "enabled=$canvas_rough_curves")"
  if ! jq --exit-status --argjson expected "$canvas_rough_curves" '
    .result.canvasRuntimeRoughCurveTuning == true and
    .result.canvasRoughCurveTessellation == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested Canvas rough-curve path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

if [[ -n "$canvas_straight_alpha_textures" ]]; then
  tuning_state="$(extension setCanvasStraightAlphaTextures \
    --data-urlencode "enabled=$canvas_straight_alpha_textures")"
  if ! jq --exit-status --argjson expected "$canvas_straight_alpha_textures" '
    .result.canvasRuntimeStraightAlphaTextureTuning == true and
    .result.canvasStraightAlphaTextures == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested Canvas straight-alpha path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

if [[ -n "$typed_generated_strokes" ]]; then
  tuning_state="$(extension setTypedGeneratedStrokes \
    --data-urlencode "enabled=$typed_generated_strokes")"
  if ! jq --exit-status --argjson expected "$typed_generated_strokes" '
    .result.gpuRuntimeStrokeTuning == true and
    .result.gpuTypedGeneratedStrokes == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested generated-stroke path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

if [[ -n "$rough_line_shader" ]]; then
  tuning_state="$(extension setRoughLineShader \
    --data-urlencode "enabled=$rough_line_shader")"
  if ! jq --exit-status --argjson expected "$rough_line_shader" '
    .result.gpuRuntimeRoughLineShaderTuning == true and
    .result.gpuRoughLineShader == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested rough-line shader path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

if [[ -n "$rough_axis_runs" ]]; then
  tuning_state="$(extension setRoughAxisRuns \
    --data-urlencode "enabled=$rough_axis_runs")"
  if ! jq --exit-status --argjson expected "$rough_axis_runs" '
    .result.gpuRuntimeRoughAxisRunTuning == true and
    .result.gpuRoughAxisRuns == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested rough-axis-run path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

if [[ -n "$direct_sprite_geometry" ]]; then
  tuning_state="$(extension setDirectSpriteGeometry \
    --data-urlencode "enabled=$direct_sprite_geometry")"
  if ! jq --exit-status --argjson expected "$direct_sprite_geometry" '
    .result.gpuRuntimeSpriteGeometryTuning == true and
    .result.gpuDirectSpriteGeometry == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested sprite-geometry path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

if [[ -n "$sync_plain_table_opcodes" ]]; then
  tuning_state="$(extension setSyncPlainTableOpcodes \
    --data-urlencode "enabled=$sync_plain_table_opcodes")"
  if ! jq --exit-status --argjson expected "$sync_plain_table_opcodes" '
    .result.lualikeRuntimeSyncPlainTableTuning == true and
    .result.lualikeSyncPlainTableOpcodes == $expected
  ' <<<"$tuning_state" >/dev/null; then
    echo "Unable to select the requested sync plain-table opcode path" >&2
    jq '.' <<<"$tuning_state" >&2
    exit 1
  fi
fi

require_exact_presentation() {
  local state="$1"
  local label="$2"
  if [[ "$require_exact_presentation" == false ]]; then
    return 0
  fi
  if jq --exit-status '
    .result.presentation.destinationLeft == 0 and
    .result.presentation.destinationTop == 0 and
    .result.presentation.destinationWidth == .result.window.width and
    .result.presentation.destinationHeight == .result.window.height
  ' <<<"$state" >/dev/null; then
    return 0
  fi
  echo "Presentation is not exact 1:1 during $label" >&2
  jq '.result | {window, presentation}' <<<"$state" >&2
  return 1
}

vm_rpc() {
  local name="$1"
  shift
  curl --fail --silent --show-error --get \
    "$vm_service_url/$name" \
    --data-urlencode "isolateId=$isolate_id" \
    "$@"
}

cleanup_input() {
  extension resetInputState >/dev/null 2>&1 || true
}
trap cleanup_input EXIT INT TERM

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
  wait_for_ready_mode "$mode" >/dev/null
  reference_presentation=""
  for trial_index in $(seq 1 "$trial_count"); do
    extension resetInputState >/dev/null
    state="$(extension getRenderState)"
    workload_start_tick=""
    if [[ -n "$pointer_x" ]]; then
      state="$(extension setVirtualPointer \
        --data-urlencode "x=$pointer_x" \
        --data-urlencode "y=$pointer_y" \
        --data-urlencode 'lockPhysicalMouseInput=true')"
    fi
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
    state="$(extension getRenderState)"
    if [[ -n "$expected_workload" ]]; then
      if ! jq --exit-status --arg expected "$expected_workload" '
        .result.workload.name == $expected and
        (.result.workload.tick | type == "number") and
        (.result.workload.checksum | type == "number")
      ' <<<"$state" >/dev/null; then
        echo "LOVE workload did not enter $expected_workload" >&2
        jq '.result.workload' <<<"$state" >&2
        exit 1
      fi
      workload_start_tick="$(jq -r '.result.workload.tick' <<<"$state")"
    fi
    require_exact_presentation "$state" "$mode trial $trial_index warmup"
    trial_presentation="$(jq --compact-output \
      '.result.presentation | [.destinationLeft, .destinationTop,
       .destinationWidth, .destinationHeight]' <<<"$state")"
    if [[ -z "$reference_presentation" ]]; then
      reference_presentation="$trial_presentation"
    elif [[ "$trial_presentation" != "$reference_presentation" ]]; then
      echo "Presentation geometry drifted before $mode trial $trial_index" >&2
      exit 1
    fi
    if [[ -n "$cpu_profile_output" ]]; then
      vm_rpc clearCpuSamples >/dev/null
    fi
    if [[ -n "$allocation_profile_output" ]]; then
      vm_rpc getAllocationProfile --data-urlencode 'reset=true' >/dev/null
      vm_rpc getAllocationProfile >"$allocation_profile_output.reset"
    fi
    extension resetFrameTiming >/dev/null
    state="$(wait_for_samples "$mode")"
    require_exact_presentation "$state" "$mode trial $trial_index measurement"
    if [[ -n "$cpu_profile_output" ]]; then
      vm_rpc getCpuSamples >"$cpu_profile_output"
    fi
    if [[ -n "$allocation_profile_output" ]]; then
      vm_rpc getAllocationProfile >"$allocation_profile_output"
    fi
    if [[ -n "$pointer_x" ]]; then
      if ! jq --exit-status \
        --argjson x "$pointer_x" \
        --argjson y "$pointer_y" \
        '.result.input.physicalMouseInputLocked == true and
         .result.input.mouseX == $x and
         .result.input.mouseY == $y' <<<"$state" >/dev/null; then
        echo "LOVE pointer stimulus drifted during $mode trial $trial_index" >&2
        exit 1
      fi
    fi
    if [[ -n "$expected_workload" ]] &&
       ! jq --exit-status \
         --arg expected "$expected_workload" \
         --argjson startTick "$workload_start_tick" '
         .result.workload.name == $expected and
         .result.workload.tick > $startTick and
         (.result.workload.checksum | type == "number")
       ' <<<"$state" >/dev/null; then
      echo "LOVE workload did not advance during $mode trial $trial_index" >&2
      jq '.result.workload' <<<"$state" >&2
      exit 1
    fi
    final_presentation="$(jq --compact-output \
      '.result.presentation | [.destinationLeft, .destinationTop,
       .destinationWidth, .destinationHeight]' <<<"$state")"
    if [[ "$final_presentation" != "$reference_presentation" ]]; then
      echo "Presentation geometry drifted during $mode trial $trial_index" >&2
      exit 1
    fi
    if [[ -n "$min_average_commands" ]] &&
        ! jq --exit-status \
          --argjson minimum "$min_average_commands" \
          '.result.frameTiming.averageRenderedCommands >= $minimum' \
          <<<"$state" >/dev/null; then
      actual_average="$(jq --raw-output \
        '.result.frameTiming.averageRenderedCommands' <<<"$state")"
      echo "Rendered workload fell below the command floor during "\
"$mode trial $trial_index: $actual_average < $min_average_commands" >&2
      exit 1
    fi
    if [[ -n "$hold_key" ]]; then
      extension setVirtualKey \
        --data-urlencode "key=$hold_key" \
        --data-urlencode 'down=false' >/dev/null
    fi
    jq -c \
      --arg trial_mode "$mode" \
      --argjson trial_index "$trial_index" \
      --arg trial_reset_key "$reset_key" \
      --arg expected_workload "$expected_workload" \
      '.result + {trialMode: $trial_mode, trialIndex: $trial_index,
        trialResetKey: $trial_reset_key,
        expectedWorkload: (if $expected_workload == "" then null
          else $expected_workload end)}' \
      <<<"$state" | tee -a "$output_path"
  done
done

echo "Wrote $output_path" >&2
