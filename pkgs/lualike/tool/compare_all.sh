#!/bin/sh
# Run compare_disasm over every script in luascripts/compare/
# Output goes to stdout; pipe to a file for review.
#
# Usage:  ./tool/compare_all.sh
#         ./tool/compare_all.sh | less

cd "$(dirname "$0")/.."  # pkgs/lualike

COMPARE_DIR=luascripts/compare
TOOL=tool/compare_disasm.dart

if [ ! -d "$COMPARE_DIR" ]; then
  echo "No $COMPARE_DIR directory — nothing to compare."
  exit 1
fi

for f in "$COMPARE_DIR"/*.lua; do
  dart run "$TOOL" "$f"
  echo ""
done
