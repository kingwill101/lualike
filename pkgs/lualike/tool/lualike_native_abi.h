// Interface between lualike's native-compiled functions and the Dart VM.
//
// Every compiled function receives a register frame and returns an exit code:
//   0  = success, continue execution
//   >0 = PC to resume interpretation at (fallback)
//   <0 = fatal error
//
// Registers are passed as a flat array of TValue structures.  The native code
// reads/writes them directly.  When it hits an operation it can't handle
// (tables, closures, calls), it returns the current PC and the VM takes over.
//
// This header is the single source of truth for the ABI.  Both the LLVM IR
// emitter (dart) and the C runtime stub include it.

#ifndef LUALIKE_NATIVE_ABI_H
#define LUALIKE_NATIVE_ABI_H

#include <stdint.h>

// Lua value representation for native code.
// Mirrors the layout used by lualike's Value class for direct field access.
// Tagged pointer: the low 3 bits encode the type, the rest is data/pointer.
typedef uint64_t TValue;

// Type tags (must match lualike's Value type tags).
#define TAG_NIL     0
#define TAG_BOOL    1
#define TAG_NUMBER  2
#define TAG_STRING  3
#define TAG_TABLE   4
#define TAG_FUNCTION 5
#define TAG_USERDATA 6
#define TAG_THREAD  7

// Native function signature.
// Takes a register frame pointer and the return register index.
// Returns 0 on success, or the PC to resume the interpreter at on fallback.
typedef int (*LuaNativeFn)(TValue* registers, int returnReg);

// Helper: create a number value.
static inline TValue lua_number(double d) {
  // Bitcast double to uint64, tag with TAG_NUMBER.
  // The type tag occupies the low 3 bits of a NaN-boxed double.
  // In a NaN-boxing scheme: quiet NaN + tag + 48-bit pointer/data.
  // For now, simple offset tagging: tag in low bits, data shifted.
  union { double d; uint64_t u; } u;
  u.d = d;
  // Low 3 bits = TAG_NUMBER, rest = mantissa bits.
  // This requires the value to be a valid non-NaN double, which is fine
  // for the compilable subset (pure arithmetic).
  return (u.u & ~7ULL) | TAG_NUMBER;
}

// Helper: extract double from a number value.
static inline double lua_to_number(TValue v) {
  union { double d; uint64_t u; } u;
  u.u = (v & ~7ULL) | 0x0; // Clear tag bits, restore lower mantissa.
  return u.d;
}

// Helper: check the type tag.
static inline int lua_tag(TValue v) {
  return (int)(v & 7);
}

#endif // LUALIKE_NATIVE_ABI_H
