#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: capture_native_love.sh [options]

Launches the installed LOVE CLI and captures its Hyprland window after it has
settled. This is intended for source-for-source visual comparisons with the
Flutter demo on Linux/Wayland hosts.

Options:
  --project <path>  LOVE project directory (default: assets).
  --output <path>   PNG output path (default: /tmp/love2d-benchmark/native-love.png).
  --window-size <WxH>
                    Float and resize the LOVE window before capture
                    (default: 1280x720; use "current" to keep tiling).
  --key <key>       Press and release one LOVE key after focusing the window
                    (for example b for the sentinel phase).
  --game-arg <arg>  Pass one deterministic argument to love.load.
  --settle-seconds <n>
                    Seconds to wait after the window appears (default: 2).
  --help            Show this help.
EOF
}

project_path="${LOVE2D_NATIVE_PROJECT:-assets}"
output_path="${LOVE2D_NATIVE_OUTPUT:-/tmp/love2d-benchmark/native-love.png}"
window_size="${LOVE2D_NATIVE_WINDOW_SIZE:-1280x720}"
settle_seconds="${LOVE2D_NATIVE_SETTLE_SECONDS:-2}"
capture_key="${LOVE2D_NATIVE_CAPTURE_KEY:-}"
game_arg="${LOVE2D_NATIVE_GAME_ARG:-}"

while (($# > 0)); do
  case "$1" in
    --project)
      project_path="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    --window-size)
      window_size="$2"
      shift 2
      ;;
    --settle-seconds)
      settle_seconds="$2"
      shift 2
      ;;
    --key)
      capture_key="$2"
      shift 2
      ;;
    --game-arg)
      game_arg="$2"
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

if ! command -v love >/dev/null 2>&1; then
  echo "love CLI is required" >&2
  exit 1
fi
if ! command -v hyprctl >/dev/null 2>&1 || ! command -v grim >/dev/null 2>&1; then
  echo "hyprctl and grim are required on this Wayland capture host" >&2
  exit 1
fi
if [[ -n "$capture_key" ]] && ! command -v wtype >/dev/null 2>&1; then
  echo "wtype is required with --key" >&2
  exit 1
fi
if ! [[ "$settle_seconds" =~ ^[0-9]+$ ]]; then
  echo "--settle-seconds must be a non-negative integer" >&2
  exit 2
fi
if [[ "$window_size" != "current" &&
      ! "$window_size" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
  echo "--window-size must be WIDTHxHEIGHT or current" >&2
  exit 2
fi

mkdir -p "$(dirname "$output_path")"
runtime_log="${TMPDIR:-/tmp}/love2d-native-capture.log"
mkdir -p "$(dirname "$runtime_log")"

love_args=("$project_path")
if [[ -n "$game_arg" ]]; then
  love_args+=("$game_arg")
fi
love "${love_args[@]}" >"$runtime_log" 2>&1 &
love_pid=$!

cleanup() {
  kill "$love_pid" >/dev/null 2>&1 || true
  wait "$love_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

query_love_geometry() {
  hyprctl clients -j | jq -r --argjson pid "$love_pid" '
    .[] | select(.class == "love" and .pid == $pid)
    | [.address, .at[0], .at[1], .size[0], .size[1], .floating] | @tsv
  ' | head -n 1
}

focus_and_verify_love_window() {
  local address="$1"
  local active_address=""
  for _ in $(seq 1 20); do
    hyprctl eval \
      "hl.dispatch(hl.dsp.focus({ window = \"address:$address\" }))" >/dev/null
    sleep 0.05
    active_address="$(hyprctl activewindow -j | jq -r '.address // empty')"
    if [[ "$active_address" == "$address" ]]; then
      return 0
    fi
  done
  echo "Unable to focus native LOVE window: expected=$address active=${active_address:-none}" >&2
  return 1
}

set_capture_window_prop() {
  local address="$1"
  local prop="$2"
  local value="$3"
  local response
  response="$(hyprctl eval \
    "hl.dispatch(hl.dsp.window.set_prop({ prop = \"$prop\", value = \"$value\", window = \"address:$address\" }))")"
  if [[ "$response" != ok ]]; then
    echo "Unable to set native capture property $prop=$value: $response" >&2
    return 1
  fi
}

capture_verified_love_region() {
  local address="$1"
  local geometry="$2"
  local output_path="$3"
  local active_before=""
  local active_after=""
  for _ in $(seq 1 12); do
    focus_and_verify_love_window "$address" || continue
    active_before="$(hyprctl activewindow -j | jq -r '.address // empty')"
    [[ "$active_before" == "$address" ]] || continue
    grim -g "$geometry" "$output_path"
    active_after="$(hyprctl activewindow -j | jq -r '.address // empty')"
    if [[ "$active_after" == "$address" ]]; then
      return 0
    fi
  done
  echo "Native LOVE window lost focus during capture: expected=$address before=${active_before:-none} after=${active_after:-none}" >&2
  return 1
}

geometry=""
for _ in $(seq 1 60); do
  geometry="$(query_love_geometry)"
  if [[ -n "$geometry" ]]; then
    break
  fi
  sleep 0.2
done

if [[ -z "$geometry" ]]; then
  echo "Timed out waiting for LOVE window (pid=$love_pid)" >&2
  cat "$runtime_log" >&2 || true
  exit 1
fi

IFS=$'\t' read -r address x y width height floating <<<"$geometry"
set_capture_window_prop "$address" border_size 0
set_capture_window_prop "$address" rounding 0
set_capture_window_prop "$address" no_shadow 1
if [[ "$window_size" != "current" ]]; then
  if ! [[ "$address" =~ ^0x[0-9a-fA-F]+$ ]]; then
    echo "Invalid Hyprland window address: $address" >&2
    exit 1
  fi
  IFS=x read -r requested_width requested_height <<<"$window_size"
  focus_and_verify_love_window "$address"
  if [[ "$floating" != "true" ]]; then
    hyprctl eval \
      'hl.dispatch(hl.dsp.window.float({ action = "toggle" }))' >/dev/null
  fi
  hyprctl eval \
    "hl.dispatch(hl.dsp.window.resize({ x = $requested_width, y = $requested_height }))" >/dev/null
  hyprctl eval 'hl.dispatch(hl.dsp.window.center())' >/dev/null
  sleep 0.5
  geometry="$(query_love_geometry)"
  if [[ -z "$geometry" ]]; then
    echo "LOVE window disappeared while resizing" >&2
    exit 1
  fi
  IFS=$'\t' read -r address x y width height floating <<<"$geometry"
  if [[ "$width" != "$requested_width" || "$height" != "$requested_height" ]]; then
    echo "LOVE window resize mismatch: expected=$window_size actual=${width}x${height}" >&2
    exit 1
  fi
fi

if [[ -n "$capture_key" ]]; then
  focus_and_verify_love_window "$address"
  wtype -k "$capture_key"
fi

if ((settle_seconds > 0)); then
  sleep "$settle_seconds"
fi

focus_and_verify_love_window "$address"
geometry="$(query_love_geometry)"
IFS=$'\t' read -r address x y width height floating <<<"$geometry"
capture_verified_love_region \
  "$address" "$x,$y ${width}x${height}" "$output_path"
printf 'Captured native LOVE window: %s (%sx%s)\n' \
  "$output_path" "$width" "$height"
