#!/usr/bin/env zsh
# Run luascripts/compare/*.lua through the LLVM pipeline and validate with llc.
# Only tests scripts within the COMPILABLE_SUBSET.
#
# Usage:
#   zsh tool/check_llvm_all.sh                    # uses default binary path
#   zsh tool/check_llvm_all.sh /path/to/binary     # custom binary path
#   zsh tool/check_llvm_all.sh /path/to/binary 01  # filtered by prefix

if [[ -f "$1" && -x "$1" && ! "$1" == *.lua ]]; then
  BINARY="$1"
  PREFIX="${2:-}"
else
  BINARY="./build/cli/linux_x64/bundle/bin/main"
  PREFIX="${1:-}"
fi

if [[ ! -f "$BINARY" ]]; then
  echo "FAIL: lualike binary not found at $BINARY"
  echo "Run 'just compile' first."
  exit 1
fi

# Scripts that produce valid whole-function LLVM IR.
COMPILABLE_SUBSET=(
 01_arith
 07_boolean
 16_bitwise
 20_locals_basic
)

passed=0
failed=0
skipped=0

for f in luascripts/compare/*.lua; do
  name="${f:t:r}"
  [[ -z "$PREFIX" || "$name" = "$PREFIX"* ]] || continue

  if ! (($COMPILABLE_SUBSET[(Ie)$name])); then
    (( skipped++ ))
    continue
  fi

  out=$( "$BINARY" --ir --emit-llvm "$f" 2>&1 || true )
  llvm=$( echo "$out" | sed -n '/^; Module generated/,/^}$/p' || true )

  if [[ -z "$llvm" ]]; then
    echo "  $name  FAIL (no LLVM)"
    (( failed++ ))
  elif echo "$llvm" | llc -o /dev/null 2>/dev/null; then
    echo "  $name  ok"
    (( passed++ ))
  else
    echo "  $name  FAIL (llc)"
    (( failed++ ))
  fi
done

echo "$passed passed, $failed failed ($skipped skipped)"
[[ $failed -eq 0 ]]
