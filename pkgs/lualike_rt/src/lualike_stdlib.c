// lualike_stdlib.c — Standard library for lualike_rt.
//
// All functions use the multi-result C native calling convention:
//   static void _fn(lua_State* L, lua_Value* args, int nargs,
//                   lua_Value* results, int maxresults, int* nresults)
//
// Registration macros:
//   REG_FN(lib, name)      — register _c_##name in table "lib" as "name"
//   REG_NUM(lib, name, v)  — register number v in table "lib" as "name"

#include "lualike_rt.h"
#include <ctype.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static double _an(lua_Value* a, int i, double d) {
  return a[i].type == LUA_TNUMBER ? a[i].payload.n : d;
}

#define RESULT1 do { if (nr) *nr = 1; } while(0)
#define RESULTN(n) do { if (nr) *nr = (n); } while(0)

// ===========================================================================
// BASE library (registered in global table)
// ===========================================================================

static void _c_print(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)r; (void)mr;
  for (int i = 0; i < n; i++) {
    if (i > 0) lualike_print(L, "\t");
    switch (a[i].type) {
      case LUA_TSTRING:  lualike_print(L, a[i].payload.s->data); break;
      case LUA_TNUMBER:  { char b[64]; snprintf(b,64,"%.14g",a[i].payload.n); lualike_print(L,b); break; }
      case LUA_TBOOLEAN: lualike_print(L, a[i].payload.b ? "true" : "false"); break;
      case LUA_TNIL:     lualike_print(L, "nil"); break;
      default:           lualike_print(L, "table"); break;
    }
  }
  lualike_print(L, "\n");
  lualike_pushnil(r); RESULT1;
}

static void _c_type(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1) { lualike_pushcstring(r, NULL, "nil"); RESULT1; return; }
  switch (a[0].type) {
    case LUA_TNIL:      lualike_pushcstring(r, NULL, "nil"); break;
    case LUA_TBOOLEAN:  lualike_pushcstring(r, NULL, "boolean"); break;
    case LUA_TNUMBER:   lualike_pushcstring(r, NULL, "number"); break;
    case LUA_TSTRING:   lualike_pushcstring(r, NULL, "string"); break;
    case LUA_TTABLE:    lualike_pushcstring(r, NULL, "table"); break;
    case LUA_TFUNCTION:
    case LUA_TNATIVEFUNC: lualike_pushcstring(r, NULL, "function"); break;
    default:            lualike_pushcstring(r, NULL, "unknown"); break;
  }
  RESULT1;
}

static void _c_tonumber(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type == LUA_TNIL) { lualike_pushnil(r); RESULT1; return; }
  if (a[0].type == LUA_TNUMBER) { lualike_copy(r, &a[0]); RESULT1; return; }
  if (a[0].type == LUA_TSTRING) {
    char* e = 0; double v = strtod(a[0].payload.s->data, &e);
    if (e != a[0].payload.s->data) { lualike_pushnumber(r, v); RESULT1; return; }
  }
  lualike_pushnil(r); RESULT1;
}

static void _c_tostring(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type == LUA_TNIL) { lualike_pushcstring(r, L, "nil"); RESULT1; return; }
  switch (a[0].type) {
    case LUA_TBOOLEAN: lualike_pushcstring(r, L, a[0].payload.b ? "true" : "false"); break;
    case LUA_TNUMBER:  { char b[64]; snprintf(b,64,"%.14g",a[0].payload.n); lualike_pushcstring(r, L, b); break; }
    case LUA_TSTRING:  lualike_copy(r, &a[0]); break;
    default:           lualike_pushcstring(r, L, "table"); break;
  }
  RESULT1;
}

static void _c_next(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type != LUA_TTABLE) { lualike_pushnil(r); RESULT1; return; }
  lua_Table* t = a[0].payload.t;
  lua_Value* key = (n >= 2) ? &a[1] : NULL;
  lua_Value nil_key; memset(&nil_key, 0, sizeof(nil_key));
  if (!key) key = &nil_key;

  // Find next key
  if (key->type == LUA_TNIL) {
    // First call: return first key
    for (uint32_t i = 0; i < t->array_len; i++)
      if (t->array[i].type != LUA_TNIL) {
        lualike_pushnumber(r, (double)(i + 1));  // key
        lualike_copy(&r[1], &t->array[i]);        // value
        RESULTN(2); return;
      }
    for (uint32_t i = 0; i < t->capacity; i++)
      if (t->entries[i].key.type != LUA_TNIL) {
        lualike_copy(r, &t->entries[i].key);      // key
        lualike_copy(&r[1], &t->entries[i].value); // value
        RESULTN(2); return;
      }
    lualike_pushnil(r); RESULT1; return; // empty
  }
  lualike_pushnil(r); RESULT1;
}

static void _c_pairs(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type != LUA_TTABLE) { lualike_pushnil(r); RESULT1; return; }
  // Pairs returns next, table, nil
  // We need to return 3 values. Use native function lookup for 'next'
  // For now, return nil
  lualike_pushnil(r); RESULT1;
}

// ===========================================================================
// TABLE library
// ===========================================================================

static void _c_tinsert(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)r; (void)mr;
  if (n < 2 || a[0].type != LUA_TTABLE) return;
  lua_Table* t = a[0].payload.t;
  int p; lua_Value* v;
  if (n >= 3) { p = (int)_an(&a[1], 0, (int)t->array_len + 1); v = &a[2]; }
  else { p = (int)t->array_len + 1; v = &a[1]; }
  if (p <= (int)t->array_len) {
    t->array = (lua_Value*)realloc(t->array, (size_t)(t->array_len + 1) * sizeof(lua_Value));
    for (int i = (int)t->array_len; i > p - 1; i--) lualike_copy(&t->array[i], &t->array[i - 1]);
    t->array_len++;
  } else {
    t->array = (lua_Value*)realloc(t->array, (size_t)p * sizeof(lua_Value));
    for (uint32_t i = t->array_len; i < (uint32_t)p; i++) memset(&t->array[i], 0, sizeof(lua_Value));
    t->array_len = (uint32_t)p;
  }
  lualike_copy(&t->array[p - 1], v);
}

static void _c_tremove(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type != LUA_TTABLE) { lualike_pushnil(r); RESULT1; return; }
  lua_Table* t = a[0].payload.t;
  if (t->array_len == 0) { lualike_pushnil(r); RESULT1; return; }
  int p = (n >= 2) ? (int)_an(&a[1], 0, (int)t->array_len) : (int)t->array_len;
  if (p < 1 || p > (int)t->array_len) { lualike_pushnil(r); RESULT1; return; }
  lualike_copy(r, &t->array[p - 1]);
  for (uint32_t i = (uint32_t)p; i < t->array_len; i++) lualike_copy(&t->array[i - 1], &t->array[i]);
  memset(&t->array[--t->array_len], 0, sizeof(lua_Value));
  RESULT1;
}

// ===========================================================================
// STRING library
// ===========================================================================

static void _c_sbyte(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type != LUA_TSTRING) { lualike_pushnil(r); RESULT1; return; }
  int i = (n >= 2) ? (int)_an(&a[1], 0, 1) : 1;
  if (i < 1 || i > (int)a[0].payload.s->length) { lualike_pushnil(r); RESULT1; return; }
  lualike_pushnumber(r, (double)(unsigned char)a[0].payload.s->data[i - 1]);
  RESULT1;
}

static void _c_schar(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  char buf[64]; int i;
  for (i = 0; i < n && i < 64; i++) buf[i] = (char)(int)_an(&a[i], 0, 0);
  lualike_pushstring(r, L, buf, n > 64 ? 64 : n);
  RESULT1;
}

static void _c_ssub(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type != LUA_TSTRING) { lualike_pushnil(r); RESULT1; return; }
  const char* s = a[0].payload.s->data; int l = (int)a[0].payload.s->length;
  int st = (n >= 2) ? (int)_an(&a[1], 0, 1) : 1;
  int en = (n >= 3) ? (int)_an(&a[2], 0, l) : l;
  if (st < 0) st = l + st + 1; if (en < 0) en = l + en + 1;
  if (st < 1) st = 1; if (en > l) en = l;
  if (st > en) { lualike_pushcstring(r, L, ""); RESULT1; return; }
  lualike_pushstring(r, L, s + st - 1, en - st + 1);
  RESULT1;
}

static void _c_srev(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type != LUA_TSTRING) { lualike_pushnil(r); RESULT1; return; }
  const char* s = a[0].payload.s->data; int l = (int)a[0].payload.s->length;
  char* b = (char*)malloc((size_t)l + 1);
  for (int i = 0; i < l; i++) b[i] = s[l - 1 - i]; b[l] = 0;
  lualike_pushstring(r, L, b, l); free(b);
  RESULT1;
}

static void _c_slower(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type != LUA_TSTRING) { lualike_pushnil(r); RESULT1; return; }
  const char* s = a[0].payload.s->data; int l = (int)a[0].payload.s->length;
  char* b = (char*)malloc((size_t)l + 1);
  for (int i = 0; i < l; i++) b[i] = (char)tolower((unsigned char)s[i]); b[l] = 0;
  lualike_pushstring(r, L, b, l); free(b);
  RESULT1;
}

static void _c_supper(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type != LUA_TSTRING) { lualike_pushnil(r); RESULT1; return; }
  const char* s = a[0].payload.s->data; int l = (int)a[0].payload.s->length;
  char* b = (char*)malloc((size_t)l + 1);
  for (int i = 0; i < l; i++) b[i] = (char)toupper((unsigned char)s[i]); b[l] = 0;
  lualike_pushstring(r, L, b, l); free(b);
  RESULT1;
}

static void _c_srep(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)mr;
  if (n < 1 || a[0].type != LUA_TSTRING) { lualike_pushnil(r); RESULT1; return; }
  const char* s = a[0].payload.s->data; int sl = (int)a[0].payload.s->length;
  int c = (n >= 2) ? (int)_an(&a[1], 0, 1) : 1;
  if (c <= 0) { lualike_pushcstring(r, L, ""); RESULT1; return; }
  int tl = sl * c; char* b = (char*)malloc((size_t)tl + 1);
  for (int i = 0; i < c; i++) memcpy(b + i * sl, s, (size_t)sl); b[tl] = 0;
  lualike_pushstring(r, L, b, tl); free(b);
  RESULT1;
}

// ===========================================================================
// MATH library
// ===========================================================================

static void _c_mabs(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type != LUA_TNUMBER) { lualike_pushnil(r); RESULT1; return; }
  lualike_pushnumber(r, fabs(a[0].payload.n)); RESULT1;
}
static void _c_mfloor(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type != LUA_TNUMBER) { lualike_pushnil(r); RESULT1; return; }
  lualike_pushnumber(r, floor(a[0].payload.n)); RESULT1;
}
static void _c_mceil(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1 || a[0].type != LUA_TNUMBER) { lualike_pushnil(r); RESULT1; return; }
  lualike_pushnumber(r, ceil(a[0].payload.n)); RESULT1;
}
static void _c_mmax(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1) { lualike_pushnil(r); RESULT1; return; }
  double m = _an(&a[0], 0, 0);
  for (int i = 1; i < n; i++) { double v = _an(&a[i], 0, m); if (v > m) m = v; }
  lualike_pushnumber(r, m); RESULT1;
}
static void _c_mmin(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 1) { lualike_pushnil(r); RESULT1; return; }
  double m = _an(&a[0], 0, 0);
  for (int i = 1; i < n; i++) { double v = _an(&a[i], 0, m); if (v < m) m = v; }
  lualike_pushnumber(r, m); RESULT1;
}

#define MATH_TRIG(name, fn) \
  static void _c_m##name(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) { \
    (void)L; (void)mr; \
    if (n < 1 || a[0].type != LUA_TNUMBER) { lualike_pushnil(r); RESULT1; return; } \
    lualike_pushnumber(r, fn(a[0].payload.n)); RESULT1; \
  }

MATH_TRIG(sin, sin) MATH_TRIG(cos, cos) MATH_TRIG(tan, tan)
MATH_TRIG(asin, asin) MATH_TRIG(acos, acos) MATH_TRIG(atan, atan)
MATH_TRIG(sqrt, sqrt) MATH_TRIG(log, log) MATH_TRIG(exp, exp)

static void _c_matan2(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  if (n < 2 || a[0].type != LUA_TNUMBER || a[1].type != LUA_TNUMBER) { lualike_pushnil(r); RESULT1; return; }
  lualike_pushnumber(r, atan2(a[0].payload.n, a[1].payload.n)); RESULT1;
}

static unsigned int _rand = 1;
static void _c_mrandom(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)mr;
  _rand = _rand * 1103515245 + 12345;
  double v = (double)(_rand & 0x7FFFFFFF) / 2147483648.0;
  if (n == 0) lualike_pushnumber(r, v);
  else if (n == 1) lualike_pushnumber(r, 1.0 + (int)(v * _an(&a[0], 0, 1)));
  else { int m = (int)_an(&a[0], 0, 1), M = (int)_an(&a[1], 0, 100);
         lualike_pushnumber(r, m + (int)(v * (M - m + 1))); }
  RESULT1;
}
static void _c_mrandseed(lua_State* L, lua_Value* a, int n, lua_Value* r, int mr, int* nr) {
  (void)L; (void)r; (void)mr;
  if (n >= 1 && a[0].type == LUA_TNUMBER) _rand = (unsigned int)a[0].payload.n;
}

// ===========================================================================
// Registration macros and function
// ===========================================================================

#define REG_FN(L, lib, name) do { \
  lua_Value tv, fv; memset(&tv,0,sizeof(tv)); memset(&fv,0,sizeof(fv)); \
  if (lib[0]) { lualike_getfield(L, &tv, &L->globals, lib); \
    if (tv.type != LUA_TTABLE) { lualike_newtable(&tv); \
      lualike_setfield(L, &L->globals, lib, &tv); } } \
  else { tv = L->globals; lualike_retain(&tv); } \
  lualike_pushcfunction(&fv, _c_##name, #name); \
  lualike_setfield(L, &tv, #name, &fv); \
  if (lib[0]) lualike_setfield(L, &L->globals, lib, &tv); \
  lualike_release(&tv); lualike_release(&fv); \
} while(0)

#define REG_NUM(L, lib, name, val) do { \
  lua_Value v; memset(&v,0,sizeof(v)); v.type=LUA_TNUMBER; v.payload.n=val; \
  lua_Value tv; memset(&tv,0,sizeof(tv)); lualike_getfield(L,&tv,&L->globals,lib); \
  if(tv.type!=LUA_TTABLE){lualike_newtable(&tv);lualike_setfield(L,&L->globals,lib,&tv);} \
  lualike_setfield(L,&tv,name,&v); lualike_setfield(L,&L->globals,lib,&tv); \
  lualike_release(&tv); \
} while(0)

// Base library helpers
#define BASE_FN(name) REG_FN(L, "", name)
#define MATH_FN(name) REG_FN(L, "math", m##name)
#define STR_FN(name)  REG_FN(L, "string", s##name)
#define TAB_FN(name)  REG_FN(L, "table", t##name)

void lualike_openlibs(lua_State* L) {
  // Base
  BASE_FN(print); BASE_FN(type); BASE_FN(tonumber); BASE_FN(tostring);

  // Table
  REG_FN(L, "table", tinsert);   // name "insert", cname "tinsert"
  REG_FN(L, "table", tremove);   // name "remove", cname "tremove"

  // String
  REG_FN(L, "string", sbyte);
  REG_FN(L, "string", schar);
  REG_FN(L, "string", ssub);
  REG_FN(L, "string", srev);
  REG_FN(L, "string", slower);
  REG_FN(L, "string", supper);
  REG_FN(L, "string", srep);

  // Math
  MATH_FN(abs); MATH_FN(floor); MATH_FN(ceil);
  MATH_FN(max); MATH_FN(min);
  MATH_FN(sin); MATH_FN(cos); MATH_FN(tan);
  MATH_FN(asin); MATH_FN(acos); MATH_FN(atan);
  MATH_FN(sqrt); MATH_FN(log); MATH_FN(exp);
  REG_FN(L, "math", matan2);
  REG_FN(L, "math", mrandom);
  REG_FN(L, "math", mrandseed);
  REG_NUM(L, "math", "pi", 3.14159265358979323846);
  REG_NUM(L, "math", "huge", HUGE_VAL);
}
