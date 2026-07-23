#!/usr/bin/env zsh
# Compile a Lua script to a native binary via LLVM and run it.
# 
# Usage:
#   zsh tool/compile_to_native.sh script.lua [output]
#   zsh tool/compile_to_native.sh /path/to/lualike_bin script.lua [output]
set -eo pipefail

DIR="${0:A:h}"

# Determine binary path and script path
if [[ -f "$1" && -x "$1" && ! "$1" == *.lua ]]; then
  BINARY="$1"
  shift
else
  BINARY="./build/cli/linux_x64/bundle/bin/main"
fi

SCRIPT="$1"
OUTPUT="${2:-a.out}"

if [[ -z "$SCRIPT" ]]; then
  echo "Usage: $0 [binary] <script.lua> [output]"
  echo "  binary defaults to ./build/cli/linux_x64/bundle/bin/main"
  exit 1
fi

if [[ ! -f "$BINARY" ]]; then
  echo "FAIL: lualike binary not found at $BINARY"
  echo "Run 'just compile' first."
  exit 1
fi

echo "  emit LLVM IR..."
LLVM=$("$BINARY" --ir --emit-llvm "$SCRIPT" 2>/dev/null)
LLVM_BODY=$(echo "$LLVM" | sed -n '/^; Module generated/,/^}$/p')
if [[ -z "$LLVM_BODY" ]]; then
  echo "FAIL: no LLVM output from lualike"
  exit 1
fi

echo "$LLVM_BODY" > /tmp/compile_native.ll

# Append main() wrapper that calls _lua_fn_0 and prints the result.
if echo "$LLVM_BODY" | grep -q "define double @_lua_fn_0"; then
  cat >> /tmp/compile_native.ll << 'LLVM'
@.str = private unnamed_addr constant [4 x i8] c"%g\0a\00"
declare i32 @printf(i8*, ...)

define i32 @main() {
  %r = call double @_lua_fn_0()
  %fmt = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
  call i32 (i8*, ...) @printf(i8* %fmt, double %r)
  ret i32 0
}
LLVM
else
  cat >> /tmp/compile_native.ll << 'LLVM'
define i32 @main() {
  call void @_lua_fn_0()
  ret i32 0
}
LLVM
fi

echo "  llc..."
llc -filetype=obj /tmp/compile_native.ll -o /tmp/compile_native.o || {
  echo "FAIL: llc"
  exit 1
}

echo "  link..."
cc -no-pie -o "$OUTPUT" /tmp/compile_native.o "$DIR/lualike_runtime.c" -lm 2>/dev/null || \
cc -o "$OUTPUT" /tmp/compile_native.o "$DIR/lualike_runtime.c" -lm || {
  echo "FAIL: link"
  exit 1
}

echo "  run..."
if "$OUTPUT"; then
  echo "  ok"
else
  rc=$?
  echo "  exit $rc"
fi
