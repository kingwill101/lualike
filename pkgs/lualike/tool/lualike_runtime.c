// Minimal runtime for lualike-compiled native code.
// Link with: clang -o output output.o lualike_runtime.c -lm

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Called when compiled code hits an unsupported Lua runtime feature.
void lualike_abort(const char *message) {
  fprintf(stderr, "lualike runtime error: %s\n", message);
  abort();
}

// Math library functions that compiled code may call.
// These are declared in the LLVM IR; we provide them here.
// (pow, fmod, floor are already in libm)
