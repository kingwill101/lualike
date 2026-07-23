#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fvm flutter pub get >/dev/null

config="$(find .dart_tool/hooks_runner/love2d_gpu -name input.json 2>/dev/null | head -1)"
if [[ -z "${config}" ]]; then
  echo "love2d_gpu: no love2d_gpu hook input.json found after pub get" >&2
  exit 1
fi

fvm dart run hook/build.dart --config="${config}"
