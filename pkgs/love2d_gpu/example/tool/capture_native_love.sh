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
  --settle-seconds <n>
                    Seconds to wait after the window appears (default: 2).
  --help            Show this help.
EOF
}

project_path="${LOVE2D_NATIVE_PROJECT:-assets}"
output_path="${LOVE2D_NATIVE_OUTPUT:-/tmp/love2d-benchmark/native-love.png}"
settle_seconds="${LOVE2D_NATIVE_SETTLE_SECONDS:-2}"

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
    --settle-seconds)
      settle_seconds="$2"
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
if ! [[ "$settle_seconds" =~ ^[0-9]+$ ]]; then
  echo "--settle-seconds must be a non-negative integer" >&2
  exit 2
fi

mkdir -p "$(dirname "$output_path")"

love "$project_path" >/tmp/love2d-native-capture.log 2>&1 &
love_pid=$!

cleanup() {
  kill "$love_pid" >/dev/null 2>&1 || true
  wait "$love_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

geometry=""
for _ in $(seq 1 60); do
  geometry="$(hyprctl clients -j | jq -r --argjson pid "$love_pid" '
    .[] | select(.class == "love" and .pid == $pid)
    | [.at[0], .at[1], .size[0], .size[1]] | @tsv
  ' | head -n 1)"
  if [[ -n "$geometry" ]]; then
    break
  fi
  sleep 0.2
done

if [[ -z "$geometry" ]]; then
  echo "Timed out waiting for LOVE window (pid=$love_pid)" >&2
  cat /tmp/love2d-native-capture.log >&2 || true
  exit 1
fi

if ((settle_seconds > 0)); then
  sleep "$settle_seconds"
fi

IFS=$'\t' read -r x y width height <<<"$geometry"
grim -g "$x,$y ${width}x${height}" "$output_path"
printf 'Captured native LOVE window: %s\n' "$output_path"
