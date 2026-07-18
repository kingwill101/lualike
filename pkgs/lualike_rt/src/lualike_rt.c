// lualike_rt.c — Standalone C runtime for LLVM-compiled lualike IR.
#include "lualike_rt.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

// ===========================================================================
// Internal helpers
// ===========================================================================

static void* xmalloc(size_t sz) {
  void* p = malloc(sz);
  if (!p) { fprintf(stderr, "lualike_rt: out of memory\n"); exit(1); }
  return p;
}

static void* xcalloc(size_t n, size_t sz) {
  void* p = calloc(n, sz);
  if (!p) { fprintf(stderr, "lualike_rt: out of memory\n"); exit(1); }
  return p;
}

static char* xstrdup(const char* s) {
  size_t len = strlen(s);
  char* d = (char*)xmalloc(len + 1);
  memcpy(d, s, len + 1);
  return d;
}

static lua_String* lualike_newstring_raw(lua_State* L, const char* s, int len) {
  (void)L;
  lua_String* ls = (lua_String*)xmalloc(sizeof(lua_String) + (size_t)len + 1);
  ls->refcount = 1;
  ls->length = (uint32_t)len;
  if (s && len > 0) memcpy(ls->data, s, (size_t)len);
  if (s) ls->data[len] = '\0';  // null-terminate for C interop
  return ls;
}

// Lua 5.4: coerce string <-> number for arithmetic
static bool lualike_tonumber_raw(lua_Value* v) {
  if (v->type == LUA_TNUMBER) return true;
  if (v->type != LUA_TSTRING) return false;
  char* end = NULL;
  double n = strtod(v->payload.s->data, &end);
  if (end == v->payload.s->data) return false;  // no digits consumed
  // Release string, set number
  lualike_release(v);
  v->type = LUA_TNUMBER;
  v->payload.n = n;
  return true;
}

// ===========================================================================
// Value lifecycle
// ===========================================================================

void lualike_retain(const lua_Value* v) {
  switch (v->type) {
    case LUA_TSTRING: if (v->payload.s) v->payload.s->refcount++; break;
    case LUA_TTABLE:  if (v->payload.t) v->payload.t->refcount++; break;
    case LUA_TFUNCTION: if (v->payload.fn) v->payload.fn->refcount++; break;
    default: break;
  }
}

void lualike_release(lua_Value* v) {
  switch (v->type) {
    case LUA_TSTRING: {
      if (v->payload.s && --v->payload.s->refcount == 0) free(v->payload.s);
      break;
    }
    case LUA_TTABLE: {
      if (v->payload.t && --v->payload.t->refcount == 0) {
        free(v->payload.t->array);
        for (uint32_t i = 0; i < v->payload.t->capacity; i++) {
          if (v->payload.t->entries[i].key.type != LUA_TNIL) {
            lualike_release(&v->payload.t->entries[i].key);
            lualike_release(&v->payload.t->entries[i].value);
          }
        }
        free(v->payload.t->entries);
        free(v->payload.t);
      }
      break;
    }
    case LUA_TFUNCTION: {
      if (v->payload.fn && --v->payload.fn->refcount == 0) {
        for (int i = 0; i < v->payload.fn->nupvals; i++) {
          lualike_release(&v->payload.fn->upvals[i]);
        }
        free(v->payload.fn->upvals);
        free(v->payload.fn->name);
        free(v->payload.fn);
      }
      break;
    }
    default: break;
  }
}

void lualike_copy(lua_Value* dst, const lua_Value* src) {
  if (dst == src) return;
  lualike_release(dst);
  memcpy(dst, src, sizeof(lua_Value));
  lualike_retain(dst);
}

// ===========================================================================
// Value constructors
// ===========================================================================

void lualike_pushnil(lua_Value* v) {
  lualike_release(v);
  memset(v, 0, sizeof(*v));
  v->type = LUA_TNIL;
}

void lualike_pushboolean(lua_Value* v, bool b) {
  lualike_release(v);
  memset(v, 0, sizeof(*v));
  v->type = LUA_TBOOLEAN;
  v->payload.b = b;
}

void lualike_pushnumber(lua_Value* v, double n) {
  lualike_release(v);
  memset(v, 0, sizeof(*v));
  v->type = LUA_TNUMBER;
  v->payload.n = n;
}

void lualike_pushinteger(lua_Value* v, int64_t i) {
  lualike_pushnumber(v, (double)i);
}

void lualike_pushstring(lua_Value* v, lua_State* L, const char* s, int len) {
  lualike_release(v);
  memset(v, 0, sizeof(*v));
  v->type = LUA_TSTRING;
  v->payload.s = lualike_newstring_raw(L, s, len);
}

void lualike_pushcstring(lua_Value* v, lua_State* L, const char* s) {
  lualike_pushstring(v, L, s, (int)strlen(s));
}

void lualike_pushfunction(lua_Value* v, lua_Function* fn) {
  lualike_release(v);
  memset(v, 0, sizeof(*v));
  v->type = LUA_TFUNCTION;
  v->payload.fn = fn;
  fn->refcount++;
}

// ===========================================================================
// Value queries
// ===========================================================================

lua_Type lualike_type(const lua_Value* v) { return v->type; }
bool lualike_isnil(const lua_Value* v) { return v->type == LUA_TNIL; }
bool lualike_isnumber(const lua_Value* v) { return v->type == LUA_TNUMBER; }
bool lualike_isstring(const lua_Value* v) { return v->type == LUA_TSTRING; }
bool lualike_istable(const lua_Value* v) { return v->type == LUA_TTABLE; }
bool lualike_isfunction(const lua_Value* v) { return v->type == LUA_TFUNCTION; }

double lualike_tonumber(const lua_Value* v) {
  if (v->type == LUA_TNUMBER) return v->payload.n;
  return 0.0;
}

bool lualike_toboolean(const lua_Value* v) {
  return v->type == LUA_TBOOLEAN ? v->payload.b : true;  // everything except nil/false is truthy
}

const char* lualike_tostring(const lua_Value* v) {
  if (v->type == LUA_TSTRING) return v->payload.s->data;
  return NULL;
}

int lualike_strlen(const lua_Value* v) {
  if (v->type == LUA_TSTRING) return (int)v->payload.s->length;
  return 0;
}

bool lualike_istruthy(const lua_Value* v) {
  if (v->type == LUA_TNIL) return false;
  if (v->type == LUA_TBOOLEAN) return v->payload.b;
  return true;
}

// ===========================================================================
// Metamethod dispatch
// ===========================================================================

bool lualike_trymetamethod(lua_State* L, lua_Value* dst,
                           const lua_Value* a, const lua_Value* b,
                           const char* metamethod) {
  // Check metatables on a and b
  // For now: simple fallback — just returns false (no metamethod)
  (void)L; (void)dst; (void)a; (void)b; (void)metamethod;
  return false;
}

// ===========================================================================
// Arithmetic
// ===========================================================================

static void arith_binary(lua_State* L, lua_Value* dst,
                         const lua_Value* a, const lua_Value* b,
                         double (*op)(double, double), const char* mm) {
  lua_Value av = *a, bv = *b;
  lualike_retain(&av); lualike_retain(&bv);

  // Try numeric coercion
  if (av.type == LUA_TSTRING) lualike_tonumber_raw(&av);
  if (bv.type == LUA_TSTRING) lualike_tonumber_raw(&bv);

  if (av.type == LUA_TNUMBER && bv.type == LUA_TNUMBER) {
    lualike_pushnumber(dst, op(av.payload.n, bv.payload.n));
    lualike_release(&av);
    lualike_release(&bv);
    return;
  }

  // Try metamethod
  if (lualike_trymetamethod(L, dst, &av, &bv, mm)) {
    lualike_release(&av);
    lualike_release(&bv);
    return;
  }

  lualike_release(&av);
  lualike_release(&bv);
  lualike_error(L, "attempt to perform arithmetic on a non-number value");
  lualike_pushnil(dst);
}

static double add_op(double a, double b) { return a + b; }
static double sub_op(double a, double b) { return a - b; }
static double mul_op(double a, double b) { return a * b; }
static double div_op(double a, double b) { return a / b; }
static double pow_op(double a, double b) { return pow(a, b); }
static double idiv_op(double a, double b) { return floor(a / b); }

void lualike_add(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  arith_binary(L, dst, a, b, add_op, "__add");
}
void lualike_sub(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  arith_binary(L, dst, a, b, sub_op, "__sub");
}
void lualike_mul(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  arith_binary(L, dst, a, b, mul_op, "__mul");
}
void lualike_div(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  arith_binary(L, dst, a, b, div_op, "__div");
}
void lualike_pow(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  arith_binary(L, dst, a, b, pow_op, "__pow");
}
void lualike_idiv(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  arith_binary(L, dst, a, b, idiv_op, "__idiv");
}

void lualike_mod(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lua_Value av = *a, bv = *b;
  lualike_retain(&av); lualike_retain(&bv);
  if (av.type == LUA_TSTRING) lualike_tonumber_raw(&av);
  if (bv.type == LUA_TSTRING) lualike_tonumber_raw(&bv);
  if (av.type == LUA_TNUMBER && bv.type == LUA_TNUMBER) {
    lualike_pushnumber(dst, fmod(av.payload.n, bv.payload.n));
    lualike_release(&av); lualike_release(&bv);
    return;
  }
  if (lualike_trymetamethod(L, dst, &av, &bv, "__mod")) {
    lualike_release(&av); lualike_release(&bv);
    return;
  }
  lualike_release(&av); lualike_release(&bv);
  lualike_error(L, "attempt to perform arithmetic on a non-number value");
  lualike_pushnil(dst);
}

void lualike_unm(lua_State* L, lua_Value* dst, const lua_Value* a) {
  lua_Value av = *a;
  lualike_retain(&av);
  if (av.type == LUA_TSTRING) lualike_tonumber_raw(&av);
  if (av.type == LUA_TNUMBER) {
    lualike_pushnumber(dst, -av.payload.n);
    lualike_release(&av);
    return;
  }
  if (lualike_trymetamethod(L, dst, &av, &av, "__unm")) {
    lualike_release(&av);
    return;
  }
  lualike_release(&av);
  lualike_error(L, "attempt to perform arithmetic on a non-number value");
  lualike_pushnil(dst);
}

// ===========================================================================
// Bitwise
// ===========================================================================

static int64_t toint64(const lua_Value* v) {
  if (v->type == LUA_TNUMBER) return (int64_t)v->payload.n;
  return 0;
}

void lualike_band(lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lualike_pushnumber(dst, (double)(toint64(a) & toint64(b)));
}
void lualike_bor(lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lualike_pushnumber(dst, (double)(toint64(a) | toint64(b)));
}
void lualike_bxor(lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lualike_pushnumber(dst, (double)(toint64(a) ^ toint64(b)));
}
void lualike_bnot(lua_Value* dst, const lua_Value* a) {
  lualike_pushnumber(dst, (double)(~toint64(a)));
}
void lualike_shl(lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lualike_pushnumber(dst, (double)(toint64(a) << (toint64(b) & 63)));
}
void lualike_shr(lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lualike_pushnumber(dst, (double)((uint64_t)toint64(a) >> (toint64(b) & 63)));
}

// ===========================================================================
// Comparison
// ===========================================================================

void lualike_eq(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  (void)L;
  // Same type comparisons
  if (a->type == b->type) {
    switch (a->type) {
      case LUA_TNIL:     lualike_pushboolean(dst, true); return;
      case LUA_TBOOLEAN: lualike_pushboolean(dst, a->payload.b == b->payload.b); return;
      case LUA_TNUMBER:  lualike_pushboolean(dst, a->payload.n == b->payload.n); return;
      case LUA_TSTRING:  lualike_pushboolean(dst,
                           a->payload.s->length == b->payload.s->length &&
                           memcmp(a->payload.s->data, b->payload.s->data, a->payload.s->length) == 0); return;
      case LUA_TTABLE:
      case LUA_TFUNCTION: lualike_pushboolean(dst, a->payload.t == b->payload.t); return;  // identity
    }
  }
  // number <-> string coercion
  if (a->type == LUA_TSTRING && b->type == LUA_TNUMBER) {
    lua_Value cv = *a; lualike_retain(&cv);
    if (lualike_tonumber_raw(&cv)) {
      lualike_pushboolean(dst, cv.payload.n == b->payload.n);
      lualike_release(&cv);
      return;
    }
    lualike_release(&cv);
  }
  if (a->type == LUA_TNUMBER && b->type == LUA_TSTRING) {
    lua_Value cv = *b; lualike_retain(&cv);
    if (lualike_tonumber_raw(&cv)) {
      lualike_pushboolean(dst, a->payload.n == cv.payload.n);
      lualike_release(&cv);
      return;
    }
    lualike_release(&cv);
  }
  lualike_pushboolean(dst, false);
}

void lualike_lt(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  (void)L;
  if (a->type == LUA_TNUMBER && b->type == LUA_TNUMBER) {
    lualike_pushboolean(dst, a->payload.n < b->payload.n);
    return;
  }
  if (a->type == LUA_TSTRING && b->type == LUA_TSTRING) {
    int cmp = memcmp(a->payload.s->data, b->payload.s->data,
                     a->payload.s->length < b->payload.s->length ? a->payload.s->length : b->payload.s->length);
    if (cmp == 0) cmp = (int)a->payload.s->length - (int)b->payload.s->length;
    lualike_pushboolean(dst, cmp < 0);
    return;
  }
  lualike_error(L, "attempt to compare two values");
  lualike_pushboolean(dst, false);
}

void lualike_le(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  (void)L;
  if (a->type == LUA_TNUMBER && b->type == LUA_TNUMBER) {
    lualike_pushboolean(dst, a->payload.n <= b->payload.n);
    return;
  }
  if (a->type == LUA_TSTRING && b->type == LUA_TSTRING) {
    int cmp = memcmp(a->payload.s->data, b->payload.s->data,
                     a->payload.s->length < b->payload.s->length ? a->payload.s->length : b->payload.s->length);
    if (cmp == 0) cmp = (int)a->payload.s->length - (int)b->payload.s->length;
    lualike_pushboolean(dst, cmp <= 0);
    return;
  }
  lualike_error(L, "attempt to compare two values");
  lualike_pushboolean(dst, false);
}

// ===========================================================================
// Logical not
// ===========================================================================

void lualike_not(lua_Value* dst, const lua_Value* a) {
  lualike_pushboolean(dst, !lualike_istruthy(a));
}

// ===========================================================================
// Length
// ===========================================================================

void lualike_len(lua_State* L, lua_Value* dst, const lua_Value* a) {
  (void)L;
  if (a->type == LUA_TSTRING) {
    lualike_pushnumber(dst, (double)a->payload.s->length);
    return;
  }
  if (a->type == LUA_TTABLE) {
    lualike_pushnumber(dst, (double)lualike_table_len(a));
    return;
  }
  lualike_error(L, "attempt to get length of a non-string, non-table value");
  lualike_pushnil(dst);
}

// ===========================================================================
// Concatenation
// ===========================================================================

void lualike_concat(lua_State* L, lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  lua_Value av = *a, bv = *b;
  lualike_retain(&av); lualike_retain(&bv);

  // Coerce numbers to strings
  if (av.type == LUA_TNUMBER) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%.14g", av.payload.n);
    lualike_release(&av);
    lualike_pushstring(&av, L, buf, (int)strlen(buf));
  }
  if (bv.type == LUA_TNUMBER) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%.14g", bv.payload.n);
    lualike_release(&bv);
    lualike_pushstring(&bv, L, buf, (int)strlen(buf));
  }

  if (av.type != LUA_TSTRING || bv.type != LUA_TSTRING) {
    lualike_release(&av); lualike_release(&bv);
    lualike_error(L, "attempt to concatenate a non-string value");
    lualike_pushnil(dst);
    return;
  }

  int total_len = (int)(av.payload.s->length + bv.payload.s->length);
  char* buf = (char*)xmalloc((size_t)total_len + 1);
  memcpy(buf, av.payload.s->data, av.payload.s->length);
  memcpy(buf + av.payload.s->length, bv.payload.s->data, bv.payload.s->length);
  buf[total_len] = '\0';
  lualike_pushstring(dst, L, buf, total_len);
  free(buf);
  lualike_release(&av); lualike_release(&bv);
}

// ===========================================================================
// Table operations
// ===========================================================================

static uint32_t hash_key(const lua_Value* key, uint32_t cap) {
  uint64_t h;
  switch (key->type) {
    case LUA_TNIL:     h = 0; break;
    case LUA_TBOOLEAN: h = key->payload.b ? 1 : 0; break;
    case LUA_TNUMBER: {
      double n = key->payload.n;
      memcpy(&h, &n, sizeof(h));
      break;
    }
    case LUA_TSTRING: {
      h = 5381;
      for (uint32_t i = 0; i < key->payload.s->length; i++)
        h = ((h << 5) + h) + (unsigned char)key->payload.s->data[i];
      break;
    }
    default: h = (uint64_t)(uintptr_t)key->payload.t; break;
  }
  return (uint32_t)(h & (uint64_t)(cap - 1));
}

void lualike_newtable(lua_Value* dst) {
  lualike_release(dst);
  memset(dst, 0, sizeof(*dst));
  lua_Table* t = (lua_Table*)xcalloc(1, sizeof(lua_Table));
  t->refcount = 1;
  t->capacity = 8;  // initial hash capacity
  t->entries = (lua_TableEntry*)xcalloc(t->capacity, sizeof(lua_TableEntry));
  dst->type = LUA_TTABLE;
  dst->payload.t = t;
}

static void table_grow(lua_Table* t) {
  uint32_t old_cap = t->capacity;
  lua_TableEntry* old_entries = t->entries;
  uint32_t new_cap = old_cap ? old_cap * 2 : 8;
  t->entries = (lua_TableEntry*)xcalloc(new_cap, sizeof(lua_TableEntry));
  t->capacity = new_cap;
  t->count = 0;
  for (uint32_t i = 0; i < old_cap; i++) {
    if (old_entries[i].key.type != LUA_TNIL) {
      uint32_t h = hash_key(&old_entries[i].key, new_cap);
      while (t->entries[h].key.type != LUA_TNIL)
        h = (h + 1) & (new_cap - 1);
      t->entries[h].key = old_entries[i].key;
      t->entries[h].value = old_entries[i].value;
      t->count++;
    }
  }
  free(old_entries);
}

static lua_Value* table_find(lua_Table* t, const lua_Value* key) {
  if (t->capacity == 0) return NULL;
  uint32_t h = hash_key(key, t->capacity);
  uint32_t start = h;
  do {
    lua_TableEntry* e = &t->entries[h];
    if (e->key.type == LUA_TNIL) return NULL;  // empty slot
    // Check equality
    if (e->key.type == key->type) {
      bool match = false;
      switch (key->type) {
        case LUA_TNIL:     match = true; break;
        case LUA_TBOOLEAN: match = e->key.payload.b == key->payload.b; break;
        case LUA_TNUMBER:  match = e->key.payload.n == key->payload.n; break;
        case LUA_TSTRING:  match = e->key.payload.s->length == key->payload.s->length &&
                                   memcmp(e->key.payload.s->data, key->payload.s->data, key->payload.s->length) == 0; break;
        default: match = e->key.payload.t == key->payload.t; break;
      }
      if (match) return &e->value;
    }
    h = (h + 1) & (t->capacity - 1);
  } while (h != start);
  return NULL;
}

static void table_set(lua_Table* t, const lua_Value* key, const lua_Value* val) {
  // Check array part for integer keys
  if (key->type == LUA_TNUMBER && key->payload.n == (double)(int64_t)key->payload.n && key->payload.n >= 1) {
    int64_t idx = (int64_t)key->payload.n;
    if (idx <= (int64_t)t->array_len) {
      if (idx > (int64_t)t->array_len) {
        // Grow array
        uint32_t new_len = (uint32_t)idx;
        t->array = (lua_Value*)realloc(t->array, new_len * sizeof(lua_Value));
        for (uint32_t i = t->array_len; i < new_len; i++)
          memset(&t->array[i], 0, sizeof(lua_Value));
        t->array_len = new_len;
      }
      if (t->array[idx - 1].type != LUA_TNIL) lualike_release(&t->array[idx - 1]);
      t->array[idx - 1] = *val;
      lualike_retain(val);
      return;
    }
  }

  // Hash part
  if (t->count * 2 >= t->capacity) table_grow(t);
  uint32_t h = hash_key(key, t->capacity);
  while (t->entries[h].key.type != LUA_TNIL) {
    // Check if key already exists
    if (hash_key(&t->entries[h].key, t->capacity) == h) {
      // Simplified: just check basic identity
      if (t->entries[h].key.type == key->type) {
        // Replace
        lualike_release(&t->entries[h].value);
        t->entries[h].value = *val;
        lualike_retain(val);
        return;
      }
    }
    h = (h + 1) & (t->capacity - 1);
  }
  // New entry
  memset(&t->entries[h].key, 0, sizeof(lua_Value));
  t->entries[h].key = *key;
  lualike_retain(key);
  t->entries[h].value = *val;
  lualike_retain(val);
  t->count++;
}

void lualike_gettable(lua_State* L, lua_Value* dst, const lua_Value* tbl, const lua_Value* key) {
  (void)L;
  if (tbl->type != LUA_TTABLE) {
    lualike_error(L, "attempt to index a non-table value");
    lualike_pushnil(dst);
    return;
  }
  lua_Table* t = tbl->payload.t;
  lua_Value* found = table_find(t, key);
  if (found) {
    lualike_copy(dst, found);
    return;
  }
  lualike_pushnil(dst);
}

void lualike_settable(lua_State* L, lua_Value* tbl, const lua_Value* key, const lua_Value* val) {
  (void)L;
  if (tbl->type != LUA_TTABLE) {
    lualike_error(L, "attempt to index a non-table value");
    return;
  }
  table_set(tbl->payload.t, key, val);
}

void lualike_getfield(lua_State* L, lua_Value* dst, const lua_Value* tbl, const char* field) {
  lua_Value key;
  memset(&key, 0, sizeof(key));
  key.type = LUA_TSTRING;
  key.payload.s = lualike_newstring_raw(L, field, (int)strlen(field));
  lualike_gettable(L, dst, tbl, &key);
  lualike_release(&key);
}

void lualike_setfield(lua_State* L, lua_Value* tbl, const char* field, const lua_Value* val) {
  lua_Value key;
  memset(&key, 0, sizeof(key));
  key.type = LUA_TSTRING;
  key.payload.s = lualike_newstring_raw(L, field, (int)strlen(field));
  lualike_settable(L, tbl, &key, val);
  lualike_release(&key);
}

void lualike_geti(lua_State* L, lua_Value* dst, const lua_Value* tbl, int64_t idx) {
  lua_Value key;
  memset(&key, 0, sizeof(key));
  key.type = LUA_TNUMBER;
  key.payload.n = (double)idx;
  lualike_gettable(L, dst, tbl, &key);
}

void lualike_seti(lua_State* L, lua_Value* tbl, int64_t idx, const lua_Value* val) {
  lua_Value key;
  memset(&key, 0, sizeof(key));
  key.type = LUA_TNUMBER;
  key.payload.n = (double)idx;
  lualike_settable(L, tbl, &key, val);
}

void lualike_setlist(lua_State* L, lua_Value* tbl, int base, int count, int idx0) {
  (void)base;
  (void)L;
  (void)L;
  if (tbl->type != LUA_TTABLE) return;
  for (int j = 0; j < count; j++) {
    lua_Value key;
    memset(&key, 0, sizeof(key));
    key.type = LUA_TNUMBER;
    key.payload.n = (double)(idx0 + j);
    // The source values are in registers base+1+j (convention)
    // We just set nil as placeholder — actual values are set by the compiled code
    lua_Value nil_val;
    memset(&nil_val, 0, sizeof(nil_val));
    nil_val.type = LUA_TNIL;
    table_set(tbl->payload.t, &key, &nil_val);
  }
}

int lualike_table_len(const lua_Value* tbl) {
  if (tbl->type != LUA_TTABLE) return 0;
  lua_Table* t = tbl->payload.t;
  // Simple: return array_len
  return (int)t->array_len;
}

// ===========================================================================
// For loop helpers
// ===========================================================================

int32_t lualike_forprep(lua_Value* r, int a) {
  // FORPREP: r[a+3] = r[a]; r[a] -= r[a+2]; always enter loop
  double initial = r[a].payload.n;
  double step = r[a + 2].payload.n;
  r[a + 3] = r[a];  // save initial value (struct copy, no ref increment needed for numbers)
  r[a].payload.n = initial - step;
  return 1;  // always enter loop body
}

int32_t lualike_forloop(lua_Value* r, int a) {
  // FORLOOP: r[a] += r[a+2]; check r[a] against r[a+1]
  double step = r[a + 2].payload.n;
  double limit = r[a + 1].payload.n;
  r[a].payload.n += step;
  double next = r[a].payload.n;
  int cont = (step > 0) ? (next <= limit) : (next >= limit);
  if (cont) {
    r[a + 3].payload.n = next;  // expose internal variable
  }
  return cont;
}

int32_t lualike_tforloop(lua_Value* r, int a) {
  // TFORLOOP: check if r[a+3] is not nil
  if (r[a + 3].type == LUA_TNIL) return 0;
  return 1;
}

// ===========================================================================
// Closure / upvalue
// ===========================================================================

lua_Upvalue* lualike_newupvalue(const lua_Value* v) {
  lua_Upvalue* uv = (lua_Upvalue*)xmalloc(sizeof(lua_Upvalue));
  uv->refcount = 1;
  memset(&uv->value, 0, sizeof(uv->value));
  uv->value = *v;
  lualike_retain((lua_Value*)v);
  return uv;
}

void lualike_newclosure(lua_Value* dst, lua_CompiledFn fn,
                        lua_Value* upvals, int nupvals, const char* name) {
  lua_Function* f = (lua_Function*)xcalloc(1, sizeof(lua_Function));
  f->refcount = 1;
  f->fn = fn;
  f->nupvals = nupvals;
  f->upvals = (lua_Value*)xcalloc((size_t)nupvals, sizeof(lua_Value));
  for (int i = 0; i < nupvals; i++) {
    lualike_copy(&f->upvals[i], &upvals[i]);
  }
  if (name) f->name = xstrdup(name);
  lualike_pushfunction(dst, f);
}

void lualike_getupval(lua_Value* dst, lua_Value* upvals, int index) {
  lualike_copy(dst, &upvals[index]);
}

void lualike_setupval(lua_Value* upvals, int index, const lua_Value* src) {
  lualike_copy(&upvals[index], src);
}

// ===========================================================================
// Function call dispatch
// ===========================================================================

void lualike_pushcfunction(lua_Value* v, lua_CFunction fn, const char* name) {
  (void)name;
  lualike_release(v);
  memset(v, 0, sizeof(*v));
  v->type = LUA_TNATIVEFUNC;
  v->payload.cfn = fn;
}

void lualike_call(lua_State* L, lua_Value* dst, const lua_Value* fn_val,
                  lua_Value* args, int nargs) {
  if (fn_val->type == LUA_TNATIVEFUNC) {
    lua_CFunction cfn = fn_val->payload.cfn;
    if (cfn) {
      lua_Value result;
      memset(&result, 0, sizeof(result));
      cfn(L, args, nargs, &result);
      if (dst) lualike_copy(dst, &result);
      lualike_release(&result);
      return;
    }
  }
  if (fn_val->type != LUA_TFUNCTION) {
    lualike_error(L, "attempt to call a non-function value");
    lualike_pushnil(dst);
    return;
  }
  lua_Function* f = fn_val->payload.fn;
  if (f->fn) {
    // Compiled Lua function
    int nregs = 16;  // TODO: determine from function metadata
    lua_Value* regs = (lua_Value*)xcalloc((size_t)nregs, sizeof(lua_Value));
    for (int i = 0; i < nargs && i < nregs; i++) {
      lualike_copy(&regs[i], &args[i]);
    }
    // Transfer upvalues
    lua_Value* upvals = f->upvals;
    int nupvals = f->nupvals;

    // Call with empty varargs
    lua_Value empty_varargs[1];
    memset(empty_varargs, 0, sizeof(empty_varargs));

    f->fn(L, regs, nregs, upvals, nupvals, empty_varargs, 0);

    // Return value is in regs[0]
    if (dst) lualike_copy(dst, &regs[0]);

    // Clean up registers
    for (int i = 0; i < nregs; i++) lualike_release(&regs[i]);
    free(regs);
  } else {
    lualike_error(L, "attempt to call a native function (not yet supported)");
    lualike_pushnil(dst);
  }
}

void lualike_tailcall(lua_State* L, lua_Value* dst, const lua_Value* fn_val,
                      lua_Value* args, int nargs) {
  // For now, tailcall behaves like call
  lualike_call(L, dst, fn_val, args, nargs);
}

// ===========================================================================
// I/O
// ===========================================================================

void lualike_print(lua_State* L, const char* s) {
  if (L && L->print_fn) {
    L->print_fn(L, s);
  } else {
    printf("%s", s);
  }
}

void lualike_error(lua_State* L, const char* msg) {
  if (L) {
    strncpy(L->error_message, msg, sizeof(L->error_message) - 1);
    L->error_message[sizeof(L->error_message) - 1] = '\0';
    L->error_code = 1;
  }
}

// ===========================================================================
// Globals
// ===========================================================================

void lualike_getglobal(lua_State* L, lua_Value* dst, const char* name) {
  lualike_getfield(L, dst, &L->globals, name);
}

void lualike_setglobal(lua_State* L, const char* name, const lua_Value* val) {
  lualike_setfield(L, &L->globals, name, val);
}

// GetTabUp helper for LLVM pipeline: looks up const[c] in upvals[0]
void lualike_gettabup(lua_Value* dst, lua_Value* upvals, lua_Value* constants, int c) {
  lua_Value* env = &upvals[0];
  if (env->type != LUA_TTABLE) { lualike_pushnil(dst); return; }
  lua_Value* key = &constants[c];
  if (key->type == LUA_TSTRING) {
    lua_Value* found = table_find(env->payload.t, key);
    if (found) { lualike_copy(dst, found); return; }
  }
  lualike_pushnil(dst);
}

// SetTabUp helper for LLVM pipeline: sets constants[c] in upvals[0] = val
void lualike_settabup(lua_Value* upvals, lua_Value* constants, lua_Value* val, int c) {
  lua_Value* env = &upvals[0];
  if (env->type != LUA_TTABLE) return;
  lua_Value* key = &constants[c];
  table_set(env->payload.t, key, val);
}

// ===========================================================================
// Raw table access
// ===========================================================================
void lualike_rawget(lua_Value* dst, const lua_Value* tbl, const lua_Value* key) {
  if (tbl->type != LUA_TTABLE) { lualike_pushnil(dst); return; }
  lua_Value* found = table_find(tbl->payload.t, key);
  if (found) { lualike_copy(dst, found); return; }
  lualike_pushnil(dst);
}
void lualike_rawset(lua_Value* tbl, const lua_Value* key, const lua_Value* val) {
  if (tbl->type == LUA_TTABLE) table_set(tbl->payload.t, key, val);
}
void lualike_rawequal(lua_Value* dst, const lua_Value* a, const lua_Value* b) {
  if (a->type != b->type) { lualike_pushboolean(dst, 0); return; }
  lualike_pushboolean(dst, a->type == b->type);
}
void lualike_rawlen(lua_Value* dst, const lua_Value* v) {
  if (v->type == LUA_TSTRING) { lualike_pushnumber(dst,(double)v->payload.s->length); return; }
  if (v->type == LUA_TTABLE) { lualike_pushnumber(dst,(double)lualike_table_len(v)); return; }
  lualike_pushnumber(dst,0);
}
void lualike_next(lua_State* L, lua_Value* dst, const lua_Value* tbl, const lua_Value* key) {
  (void)L;
  if (tbl->type != LUA_TTABLE) { lualike_pushnil(dst); return; }
  lua_Table* t = tbl->payload.t;
  if (key->type == LUA_TNIL) {
    for (uint32_t i = 0; i < t->array_len; i++)
      if (t->array[i].type != LUA_TNIL) { lualike_pushnumber(dst,(double)(i+1)); return; }
    for (uint32_t i = 0; i < t->capacity; i++)
      if (t->entries[i].key.type != LUA_TNIL) { lualike_copy(dst,&t->entries[i].key); return; }
    lualike_pushnil(dst); return;
  }
  lualike_pushnil(dst);
}
void lualike_getmetatable(lua_Value* dst, const lua_Value* v) {
  (void)v; lualike_pushnil(dst);
}
void lualike_setmetatable(lua_Value* v, const lua_Value* mt) {
  (void)v; (void)mt;
}
void lualike_type_str(lua_Value* dst, const lua_Value* v) {
  const char* s;
  switch (v->type) {
    case LUA_TNIL: s = "nil"; break;
    case LUA_TBOOLEAN: s = "boolean"; break;
    case LUA_TNUMBER: s = "number"; break;
    case LUA_TSTRING: s = "string"; break;
    case LUA_TTABLE: s = "table"; break;
    case LUA_TFUNCTION: case LUA_TNATIVEFUNC: s = "function"; break;
    default: s = "unknown";
  }
  lualike_pushcstring(dst, NULL, s);
}
void lualike_select(lua_Value* dst, lua_Value* args, int nargs) {
  if (nargs < 1) { lualike_pushnil(dst); return; }
  if (args[0].type == LUA_TNUMBER) {
    int idx = (int)args[0].payload.n;
    if (idx < 0) idx = nargs + idx;
    if (idx >= 1 && idx < nargs) lualike_copy(dst, &args[idx]);
  } else if (args[0].type == LUA_TSTRING && args[0].payload.s->data[0] == '#') {
    lualike_pushnumber(dst, (double)(nargs - 1));
  }
}

// ===========================================================================
// Standard library — Native C functions
// ===========================================================================
static double _an(lua_Value* a, int i, double d) { return a[i].type==LUA_TNUMBER?a[i].payload.n:d; }

static void _c_print(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)r;
  for (int i = 0; i < n; i++) {
    if (i > 0) lualike_print(L,"\t");
    if (a[i].type == LUA_TSTRING) lualike_print(L,a[i].payload.s->data);
    else if (a[i].type == LUA_TNUMBER) { char b[64]; snprintf(b,64,"%.14g",a[i].payload.n); lualike_print(L,b); }
    else if (a[i].type == LUA_TBOOLEAN) lualike_print(L,a[i].payload.b?"true":"false");
    else if (a[i].type == LUA_TNIL) lualike_print(L,"nil");
    else lualike_print(L,"table");
  }
  lualike_print(L,"\n");
  lualike_pushnil(r);
}
static void _c_type(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if (n<1) { lualike_pushcstring(r,NULL,"nil"); return; }
  lualike_type_str(r, &a[0]);
}
static void _c_tonumber(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if (n<1||a[0].type==LUA_TNIL) { lualike_pushnil(r); return; }
  if (a[0].type==LUA_TNUMBER) { lualike_copy(r,&a[0]); return; }
  if (a[0].type==LUA_TSTRING) { char* e=0; double v=strtod(a[0].payload.s->data,&e); if(e!=a[0].payload.s->data){lualike_pushnumber(r,v);return;}}
  lualike_pushnil(r);
}
static void _c_tostring(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  if (n<1||a[0].type==LUA_TNIL){lualike_pushcstring(r,L,"nil");return;}
  switch(a[0].type) {
    case LUA_TBOOLEAN: lualike_pushcstring(r,L,a[0].payload.b?"true":"false"); break;
    case LUA_TNUMBER: {char b[64];snprintf(b,64,"%.14g",a[0].payload.n);lualike_pushcstring(r,L,b);break;}
    case LUA_TSTRING: lualike_copy(r,&a[0]); break;
    default: lualike_pushcstring(r,L,"table"); break;
  }
}

static void _c_tinsert(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L;(void)r; if(n<2||a[0].type!=LUA_TTABLE)return;
  lua_Table* t=a[0].payload.t; int p; lua_Value* v;
  if(n>=3){p=(int)_an(&a[1],0,(int)t->array_len+1);v=&a[2];}
  else{p=(int)t->array_len+1;v=&a[1];}
  if(p<=(int)t->array_len){
    t->array=(lua_Value*)realloc(t->array,(size_t)(t->array_len+1)*sizeof(lua_Value)); t->array_len++;
    for(int i=(int)t->array_len-1;i>p-1;i--)lualike_copy(&t->array[i],&t->array[i-1]);
  }else{t->array=(lua_Value*)realloc(t->array,(size_t)p*sizeof(lua_Value));for(uint32_t i=t->array_len;i<(uint32_t)p;i++)memset(&t->array[i],0,sizeof(lua_Value));t->array_len=(uint32_t)p;}
  lualike_copy(&t->array[p-1],v);
}
static void _c_tremove(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1||a[0].type!=LUA_TTABLE){lualike_pushnil(r);return;}
  lua_Table* t=a[0].payload.t; if(t->array_len==0){lualike_pushnil(r);return;}
  int p=(n>=2)?(int)_an(&a[1],0,(int)t->array_len):(int)t->array_len;
  if(p<1||p>(int)t->array_len){lualike_pushnil(r);return;}
  lualike_copy(r,&t->array[p-1]);
  for(uint32_t i=(uint32_t)p;i<t->array_len;i++)lualike_copy(&t->array[i-1],&t->array[i]);
  memset(&t->array[--t->array_len],0,sizeof(lua_Value));
}

static void _c_sbyte(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1||a[0].type!=LUA_TSTRING){lualike_pushnil(r);return;}
  int i=(n>=2)?(int)_an(&a[1],0,1):1;
  if(i<1||i>(int)a[0].payload.s->length){lualike_pushnil(r);return;}
  lualike_pushnumber(r,(double)(unsigned char)a[0].payload.s->data[i-1]);
}
static void _c_schar(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  char b[64]; int i; for(i=0;i<n&&i<64;i++)b[i]=(char)(int)_an(&a[i],0,0);
  lualike_pushstring(r,L,b,n>64?64:n);
}
static void _c_ssub(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  if(n<1||a[0].type!=LUA_TSTRING){lualike_pushnil(r);return;}
  const char* s=a[0].payload.s->data; int l=(int)a[0].payload.s->length;
  int st=(n>=2)?(int)_an(&a[1],0,1):1; int en=(n>=3)?(int)_an(&a[2],0,l):l;
  if(st<0)st=l+st+1; if(en<0)en=l+en+1; if(st<1)st=1; if(en>l)en=l;
  if(st>en){lualike_pushcstring(r,L,"");return;}
  lualike_pushstring(r,L,s+st-1,en-st+1);
}
static void _c_srev(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  if(n<1||a[0].type!=LUA_TSTRING){lualike_pushnil(r);return;}
  const char* s=a[0].payload.s->data; int l=(int)a[0].payload.s->length;
  char* b=(char*)malloc((size_t)l+1); for(int i=0;i<l;i++)b[i]=s[l-1-i]; b[l]=0;
  lualike_pushstring(r,L,b,l); free(b);
}
static void _c_slower(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  if(n<1||a[0].type!=LUA_TSTRING){lualike_pushnil(r);return;}
  const char* s=a[0].payload.s->data; int l=(int)a[0].payload.s->length;
  char* b=(char*)malloc((size_t)l+1); for(int i=0;i<l;i++)b[i]=(char)tolower((unsigned char)s[i]); b[l]=0;
  lualike_pushstring(r,L,b,l); free(b);
}
static void _c_supper(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  if(n<1||a[0].type!=LUA_TSTRING){lualike_pushnil(r);return;}
  const char* s=a[0].payload.s->data; int l=(int)a[0].payload.s->length;
  char* b=(char*)malloc((size_t)l+1); for(int i=0;i<l;i++)b[i]=(char)toupper((unsigned char)s[i]); b[l]=0;
  lualike_pushstring(r,L,b,l); free(b);
}
static void _c_srep(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  if(n<1||a[0].type!=LUA_TSTRING){lualike_pushnil(r);return;}
  const char* s=a[0].payload.s->data; int sl=(int)a[0].payload.s->length; int c=(n>=2)?(int)_an(&a[1],0,1):1;
  if(c<=0){lualike_pushcstring(r,L,"");return;}
  int tl=sl*c; char* b=(char*)malloc((size_t)tl+1);
  for(int i=0;i<c;i++)memcpy(b+i*sl,s,(size_t)sl); b[tl]=0;
  lualike_pushstring(r,L,b,tl); free(b);
}

static void _c_mabs(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1||a[0].type!=LUA_TNUMBER){lualike_pushnil(r);return;} lualike_pushnumber(r,fabs(a[0].payload.n));
}
static void _c_mfloor(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1||a[0].type!=LUA_TNUMBER){lualike_pushnil(r);return;} lualike_pushnumber(r,floor(a[0].payload.n));
}
static void _c_mceil(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1||a[0].type!=LUA_TNUMBER){lualike_pushnil(r);return;} lualike_pushnumber(r,ceil(a[0].payload.n));
}
static void _c_mmax(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1){lualike_pushnil(r);return;} double m=_an(&a[0],0,0);
  for(int i=1;i<n;i++){double v=_an(&a[i],0,m);if(v>m)m=v;} lualike_pushnumber(r,m);
}
static void _c_mmin(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<1){lualike_pushnil(r);return;} double m=_an(&a[0],0,0);
  for(int i=1;i<n;i++){double v=_an(&a[i],0,m);if(v<m)m=v;} lualike_pushnumber(r,m);
}

#define MC(name,fn) static void _c_m##name(lua_State* L, lua_Value* a, int n, lua_Value* r) { (void)L; if(n<1||a[0].type!=LUA_TNUMBER){lualike_pushnil(r);return;} lualike_pushnumber(r,fn(a[0].payload.n)); }
MC(sin,sin) MC(cos,cos) MC(tan,tan) MC(asin,asin) MC(acos,acos) MC(atan,atan)
MC(sqrt,sqrt) MC(log,log) MC(exp,exp)
static void _c_matan2(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; if(n<2||a[0].type!=LUA_TNUMBER||a[1].type!=LUA_TNUMBER){lualike_pushnil(r);return;} lualike_pushnumber(r,atan2(a[0].payload.n,a[1].payload.n));
}

static unsigned int _rand = 1;
static void _c_mrandom(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L; _rand=_rand*1103515245+12345; double v=(double)(_rand&0x7FFFFFFF)/2147483648.0;
  if(n==0)lualike_pushnumber(r,v);
  else if(n==1)lualike_pushnumber(r,1.0+(int)(v*_an(&a[0],0,1)));
  else{int m=(int)_an(&a[0],0,1),M=(int)_an(&a[1],0,100);lualike_pushnumber(r,m+(int)(v*(M-m+1)));}
}
static void _c_mrandseed(lua_State* L, lua_Value* a, int n, lua_Value* r) {
  (void)L;(void)r; if(n>=1&&a[0].type==LUA_TNUMBER)_rand=(unsigned int)a[0].payload.n;
}

// ===========================================================================
// lualike_openlibs
// ===========================================================================
static void _regf(lua_State* L, const char* t, const char* n, lua_CFunction fn) {
  lua_Value tv,fv; memset(&tv,0,sizeof(tv)); memset(&fv,0,sizeof(fv));
  if(t&&t[0]){lualike_getfield(L,&tv,&L->globals,t);if(tv.type!=LUA_TTABLE){lualike_newtable(&tv);lualike_setfield(L,&L->globals,t,&tv);}}
  else{tv=L->globals;lualike_retain(&tv);}
  lualike_pushcfunction(&fv,fn,n); lualike_setfield(L,&tv,n,&fv);
  if(t&&t[0])lualike_setfield(L,&L->globals,t,&tv);
  lualike_release(&tv); lualike_release(&fv);
}
static void _regn(lua_State* L, const char* t, const char* n, double vv) {
  lua_Value v; memset(&v,0,sizeof(v)); v.type=LUA_TNUMBER; v.payload.n=vv;
  lua_Value tv; memset(&tv,0,sizeof(tv)); lualike_getfield(L,&tv,&L->globals,t);
  if(tv.type!=LUA_TTABLE){lualike_newtable(&tv);lualike_setfield(L,&L->globals,t,&tv);}
  lualike_setfield(L,&tv,n,&v); lualike_setfield(L,&L->globals,t,&tv); lualike_release(&tv);
}

void lualike_openlibs(lua_State* L) {
  _regf(L,"","print",_c_print); _regf(L,"","type",_c_type);
  _regf(L,"","tonumber",_c_tonumber); _regf(L,"","tostring",_c_tostring);
  _regf(L,"table","insert",_c_tinsert); _regf(L,"table","remove",_c_tremove);
  _regf(L,"string","byte",_c_sbyte); _regf(L,"string","char",_c_schar);
  _regf(L,"string","sub",_c_ssub); _regf(L,"string","reverse",_c_srev);
  _regf(L,"string","lower",_c_slower); _regf(L,"string","upper",_c_supper);
  _regf(L,"string","rep",_c_srep);
  _regf(L,"math","abs",_c_mabs); _regf(L,"math","floor",_c_mfloor);
  _regf(L,"math","ceil",_c_mceil); _regf(L,"math","max",_c_mmax);
  _regf(L,"math","min",_c_mmin); _regf(L,"math","sin",_c_msin);
  _regf(L,"math","cos",_c_mcos); _regf(L,"math","tan",_c_mtan);
  _regf(L,"math","asin",_c_masin); _regf(L,"math","acos",_c_macos);
  _regf(L,"math","atan",_c_matan); _regf(L,"math","atan2",_c_matan2);
  _regf(L,"math","sqrt",_c_msqrt); _regf(L,"math","log",_c_mlog);
  _regf(L,"math","exp",_c_mexp); _regf(L,"math","random",_c_mrandom);
  _regf(L,"math","randomseed",_c_mrandseed);
  _regn(L,"math","pi",3.14159265358979323846); _regn(L,"math","huge",HUGE_VAL);
}

// ===========================================================================
// State lifecycle
// ===========================================================================

lua_State* lualike_newstate(void) {
  lua_State* L = (lua_State*)xcalloc(1, sizeof(lua_State));
  lualike_newtable(&L->globals);
  L->print_fn = NULL;
  lualike_openlibs(L);
  return L;
}

void lualike_freestate(lua_State* L) {
  if (!L) return;
  lualike_release(&L->globals);
  free(L->traceback);
  free(L);
}
