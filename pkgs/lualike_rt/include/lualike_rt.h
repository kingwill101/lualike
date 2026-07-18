// lualike_rt.h — Standalone C runtime for LLVM-compiled lualike IR.
//
// This library provides the runtime support functions needed by Lua code
// that has been compiled through the lualike IR pipeline and lowered to
// LLVM IR. Every compiled Lua function receives a lualike_State* context
// and a register array; operations are performed via calls into this runtime.
//
// Build:
//   cc -c -o lualike_rt.o lualike_rt.c -Iinclude
//   ar rcs liblualike_rt.a lualike_rt.o

#ifndef LUALIKE_RT_H_
#define LUALIKE_RT_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Lua type identifiers
// ---------------------------------------------------------------------------
typedef enum {
  LUA_TNIL = 0,
  LUA_TBOOLEAN = 1,
  LUA_TNUMBER = 2,
  LUA_TSTRING = 3,
  LUA_TTABLE = 4,
  LUA_TFUNCTION = 5,
  LUA_TNATIVEFUNC = 6,
} lua_Type;

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
struct lua_Value;
typedef struct lua_Table lua_Table;
typedef struct lua_String lua_String;
typedef struct lua_Function lua_Function;
typedef struct lua_State lua_State;
typedef struct lua_Upvalue lua_Upvalue;

// A C function callable from Lua.
typedef void (*lua_CFunction)(lua_State* L, struct lua_Value* args, int nargs, struct lua_Value* result);

// ---------------------------------------------------------------------------
// Lua value — tagged union
// ---------------------------------------------------------------------------
typedef union {
    double   n;          // LUA_TNUMBER
    bool     b;          // LUA_TBOOLEAN
    lua_String* s;       // LUA_TSTRING
    lua_Table* t;        // LUA_TTABLE
    lua_Function* fn;    // LUA_TFUNCTION
    lua_CFunction cfn;   // LUA_TNATIVEFUNC
} lua_Payload;

typedef struct lua_Value {
  lua_Type type;
  uint8_t _pad[4];
  lua_Payload payload;
} lua_Value;

// ---------------------------------------------------------------------------
// String (ref-counted, length-prefixed)
// ---------------------------------------------------------------------------
struct lua_String {
  uint32_t refcount;
  uint32_t length;
  char data[];  // not null-terminated; use length
};

// ---------------------------------------------------------------------------
// Table (simple open-addressing hash map with array part)
// ---------------------------------------------------------------------------
typedef struct {
  lua_Value key;
  lua_Value value;
} lua_TableEntry;

struct lua_Table {
  uint32_t refcount;
  uint32_t capacity;      // total allocated slots (hash part)
  uint32_t count;         // occupied hash slots
  uint32_t array_len;     // length of contiguous array part
  lua_Value* array;       // array part: indices 1..array_len
  lua_TableEntry* entries; // hash part
};

// ---------------------------------------------------------------------------
// Upvalue cell
// ---------------------------------------------------------------------------
struct lua_Upvalue {
  uint32_t refcount;
  lua_Value value;
};

// ---------------------------------------------------------------------------
// Function / closure
// ---------------------------------------------------------------------------
// The compiled function pointer type. Each compiled Lua function has this
// signature. The `closure` parameter is the lua_Value for the closure itself
// (providing access to captured upvalues).
typedef void (*lua_CompiledFn)(lua_State* L, lua_Value* r, int nregs,
                               lua_Value* upvals, int nupvals,
                               lua_Value* varargs, int nvarargs);

struct lua_Function {
  uint32_t refcount;
  lua_CompiledFn fn;           // compiled function pointer
  lua_Value* upvals;           // captured upvalue cells
  int nupvals;
  char* name;                  // debug name (may be NULL)
};

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------
// Each compiled chunk gets its own state when called.
struct lua_State {
  // Global environment (shared across all chunks)
  lua_Value globals;

  // Call stack for error handling and tracebacks
  const char** traceback;
  int traceback_len;
  int traceback_cap;

  // Error state (set by lualike_error, checked after each call)
  char error_message[256];
  int error_code;

  // Print callback (defaults to lualike_rt_print)
  void (*print_fn)(lua_State* L, const char* s);
};

// ---------------------------------------------------------------------------
// Value constructors
// ---------------------------------------------------------------------------
void lualike_pushnil(lua_Value* v);
void lualike_pushboolean(lua_Value* v, bool b);
void lualike_pushnumber(lua_Value* v, double n);
void lualike_pushinteger(lua_Value* v, int64_t i);
void lualike_pushstring(lua_Value* v, lua_State* L, const char* s, int len);
void lualike_pushcstring(lua_Value* v, lua_State* L, const char* s);
void lualike_pushfunction(lua_Value* v, lua_Function* fn);

// ---------------------------------------------------------------------------
// Value queries
// ---------------------------------------------------------------------------
lua_Type lualike_type(const lua_Value* v);
bool     lualike_isnil(const lua_Value* v);
bool     lualike_isnumber(const lua_Value* v);
bool     lualike_isstring(const lua_Value* v);
bool     lualike_istable(const lua_Value* v);
bool     lualike_isfunction(const lua_Value* v);
double   lualike_tonumber(const lua_Value* v);
bool     lualike_toboolean(const lua_Value* v);
const char* lualike_tostring(const lua_Value* v);
int      lualike_strlen(const lua_Value* v);
bool     lualike_istruthy(const lua_Value* v);

// ---------------------------------------------------------------------------
// Value lifecycle
// ---------------------------------------------------------------------------
void lualike_retain(const lua_Value* v);
void lualike_release(lua_Value* v);
void lualike_copy(lua_Value* dst, const lua_Value* src);

// ---------------------------------------------------------------------------
// Arithmetic (with metamethod dispatch)
// ---------------------------------------------------------------------------
void lualike_add(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_sub(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_mul(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_div(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_mod(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_pow(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_idiv(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_unm(lua_State* L, lua_Value* dst, const lua_Value* a);

// ---------------------------------------------------------------------------
// Bitwise (no metamethods in standard Lua — always numeric)
// ---------------------------------------------------------------------------
void lualike_band(lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_bor(lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_bxor(lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_bnot(lua_Value* dst, const lua_Value* a);
void lualike_shl(lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_shr(lua_Value* dst, const lua_Value* a, const lua_Value* b);

// ---------------------------------------------------------------------------
// Comparison (returns boolean Value)
// ---------------------------------------------------------------------------
void lualike_eq(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_lt(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_le(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);

// ---------------------------------------------------------------------------
// Logical
// ---------------------------------------------------------------------------
void lualike_not(lua_Value* dst, const lua_Value* a);

// ---------------------------------------------------------------------------
// Length
// ---------------------------------------------------------------------------
void lualike_len(lua_State* L, lua_Value* dst, const lua_Value* a);

// ---------------------------------------------------------------------------
// Concatenation
// ---------------------------------------------------------------------------
void lualike_concat(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b);

// ---------------------------------------------------------------------------
// Table operations
// ---------------------------------------------------------------------------
void lualike_newtable(lua_Value* dst);
void lualike_gettable(lua_State* L, lua_Value* dst, const lua_Value* tbl, const lua_Value* key);
void lualike_settable(lua_State* L, lua_Value* tbl, const lua_Value* key, const lua_Value* val);
void lualike_getfield(lua_State* L, lua_Value* dst, const lua_Value* tbl, const char* field);
void lualike_setfield(lua_State* L, lua_Value* tbl, const char* field, const lua_Value* val);
void lualike_geti(lua_State* L, lua_Value* dst, const lua_Value* tbl, int64_t idx);
void lualike_seti(lua_State* L, lua_Value* tbl, int64_t idx, const lua_Value* val);
void lualike_setlist(lua_State* L, lua_Value* tbl, int base, int count, int idx0);
int  lualike_table_len(const lua_Value* tbl);

// ---------------------------------------------------------------------------
// Closure / upvalue operations
// ---------------------------------------------------------------------------
void lualike_newclosure(lua_Value* dst, lua_CompiledFn fn,
                        lua_Value* upvals, int nupvals, const char* name);
void lualike_getupval(lua_Value* dst, lua_Value* upvals, int index);
void lualike_setupval(lua_Value* upvals, int index, const lua_Value* src);
lua_Upvalue* lualike_newupvalue(const lua_Value* v);

// ---------------------------------------------------------------------------
// Function call dispatch
// ---------------------------------------------------------------------------
void lualike_call(lua_State* L, lua_Value* dst, const lua_Value* fn_val,
                  lua_Value* args, int nargs);
void lualike_tailcall(lua_State* L, lua_Value* dst, const lua_Value* fn_val,
                      lua_Value* args, int nargs);

// ---------------------------------------------------------------------------
// For loop helpers (return 1 to continue loop, 0 to exit)
// ---------------------------------------------------------------------------
int32_t lualike_forprep(lua_Value* r, int a);
int32_t lualike_forloop(lua_Value* r, int a);

// ---------------------------------------------------------------------------
// Generic for loop helpers
// ---------------------------------------------------------------------------
int32_t lualike_tforloop(lua_Value* r, int a);

// ---------------------------------------------------------------------------
// Metamethod dispatch (internal, used by arithmetic)
// ---------------------------------------------------------------------------
bool lualike_trymetamethod(lua_State* L, lua_Value* dst,
                           const lua_Value* a, const lua_Value* b,
                           const char* metamethod);

// ---------------------------------------------------------------------------
// Native C function registration
// ---------------------------------------------------------------------------
void lualike_pushcfunction(lua_Value* v, lua_CFunction fn, const char* name);

// ---------------------------------------------------------------------------
// Raw table access (no metamethods)
// ---------------------------------------------------------------------------
void lualike_rawget(lua_Value* dst, const lua_Value* tbl, const lua_Value* key);
void lualike_rawset(lua_Value* tbl, const lua_Value* key, const lua_Value* val);
void lualike_rawequal(lua_Value* dst, const lua_Value* a, const lua_Value* b);
void lualike_rawlen(lua_Value* dst, const lua_Value* v);

// ---------------------------------------------------------------------------
// Table iteration (next)
// ---------------------------------------------------------------------------
void lualike_next(lua_State* L, lua_Value* dst, const lua_Value* tbl, const lua_Value* key);

// ---------------------------------------------------------------------------
// Metatable access
// ---------------------------------------------------------------------------
void lualike_getmetatable(lua_Value* dst, const lua_Value* v);
void lualike_setmetatable(lua_Value* v, const lua_Value* mt);

// ---------------------------------------------------------------------------
// Type as string
// ---------------------------------------------------------------------------
void lualike_type_str(lua_Value* dst, const lua_Value* v);

// ---------------------------------------------------------------------------
// Select
// ---------------------------------------------------------------------------
void lualike_select(lua_Value* dst, lua_Value* args, int nargs);

// ---------------------------------------------------------------------------
// Standard library init
// ---------------------------------------------------------------------------
// Registers all stdlib functions into the global environment.
void lualike_openlibs(lua_State* L);

// ---------------------------------------------------------------------------
// I/O and standard library
// ---------------------------------------------------------------------------
void lualike_print(lua_State* L, const char* s);
void lualike_error(lua_State* L, const char* msg);

// ---------------------------------------------------------------------------
// Globals (integrated with constant table for LLVM pipeline)
// ---------------------------------------------------------------------------
void lualike_getglobal(lua_State* L, lua_Value* dst, const char* name);
void lualike_setglobal(lua_State* L, const char* name, const lua_Value* val);
void lualike_gettabup(lua_Value* dst, lua_Value* upvals, lua_Value* constants, int c);
void lualike_settabup(lua_Value* upvals, lua_Value* constants, lua_Value* val, int c);

// ---------------------------------------------------------------------------
// State lifecycle
// ---------------------------------------------------------------------------
lua_State* lualike_newstate(void);
void       lualike_freestate(lua_State* L);

#ifdef __cplusplus
}
#endif

#endif  // LUALIKE_RT_H_
