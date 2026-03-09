#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner_src="$script_dir/tool/test.dart"
runner_bin="$script_dir/test_runnerbc"
lualike_bin="$script_dir/lualikebc"
cache_dir="$script_dir/.build_cache/bytecode"
dart_bin="${DART:-dart}"

needs_runner_rebuild=false
if [[ ! -x "$runner_bin" ]]; then
  needs_runner_rebuild=true
elif find "$script_dir/tool" -name '*.dart' -newer "$runner_bin" -print -quit | grep -q .; then
  needs_runner_rebuild=true
fi

if [[ "$needs_runner_rebuild" == true ]]; then
  "$dart_bin" compile exe \
    "-DDART_EXECUTABLE_PATH=$dart_bin" \
    --output "$runner_bin" \
    "$runner_src"
fi

exec "$runner_bin" \
  --lualike-bin "$lualike_bin" \
  --lualike-cache-dir "$cache_dir" \
  "$@"
