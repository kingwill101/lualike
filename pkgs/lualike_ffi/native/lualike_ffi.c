// Copyright (c) 2026, the lualike authors.
// Use of this source code is governed by the MIT license in the LICENSE file.

#include "lualike_ffi.h"

#include <dlfcn.h>
#include <ffi.h>
#include <stdio.h>
#include <string.h>

enum lualike_ffi_type {
  LUALIKE_FFI_VOID = 0,
  LUALIKE_FFI_BOOL = 1,
  LUALIKE_FFI_I8 = 2,
  LUALIKE_FFI_U8 = 3,
  LUALIKE_FFI_I16 = 4,
  LUALIKE_FFI_U16 = 5,
  LUALIKE_FFI_I32 = 6,
  LUALIKE_FFI_U32 = 7,
  LUALIKE_FFI_I64 = 8,
  LUALIKE_FFI_U64 = 9,
  LUALIKE_FFI_F32 = 10,
  LUALIKE_FFI_F64 = 11,
  LUALIKE_FFI_POINTER = 12,
  LUALIKE_FFI_STRING = 13,
};

static void set_error(char *target, size_t capacity, const char *message) {
  if (target == NULL || capacity == 0) {
    return;
  }
  snprintf(target, capacity, "%s", message == NULL ? "unknown error" : message);
}

static ffi_type *ffi_type_for(int32_t type) {
  switch (type) {
    case LUALIKE_FFI_VOID:
      return &ffi_type_void;
    case LUALIKE_FFI_BOOL:
    case LUALIKE_FFI_U8:
      return &ffi_type_uint8;
    case LUALIKE_FFI_I8:
      return &ffi_type_sint8;
    case LUALIKE_FFI_I16:
      return &ffi_type_sint16;
    case LUALIKE_FFI_U16:
      return &ffi_type_uint16;
    case LUALIKE_FFI_I32:
      return &ffi_type_sint32;
    case LUALIKE_FFI_U32:
      return &ffi_type_uint32;
    case LUALIKE_FFI_I64:
      return &ffi_type_sint64;
    case LUALIKE_FFI_U64:
      return &ffi_type_uint64;
    case LUALIKE_FFI_F32:
      return &ffi_type_float;
    case LUALIKE_FFI_F64:
      return &ffi_type_double;
    case LUALIKE_FFI_POINTER:
    case LUALIKE_FFI_STRING:
      return &ffi_type_pointer;
    default:
      return NULL;
  }
}

static void *value_address(lualike_ffi_value *value, int32_t type) {
  switch (type) {
    case LUALIKE_FFI_BOOL:
    case LUALIKE_FFI_U8:
      return &value->u8;
    case LUALIKE_FFI_I8:
      return &value->i8;
    case LUALIKE_FFI_I16:
      return &value->i16;
    case LUALIKE_FFI_U16:
      return &value->u16;
    case LUALIKE_FFI_I32:
      return &value->i32;
    case LUALIKE_FFI_U32:
      return &value->u32;
    case LUALIKE_FFI_I64:
      return &value->i64;
    case LUALIKE_FFI_U64:
      return &value->u64;
    case LUALIKE_FFI_F32:
      return &value->f32;
    case LUALIKE_FFI_F64:
      return &value->f64;
    case LUALIKE_FFI_POINTER:
    case LUALIKE_FFI_STRING:
      return &value->pointer;
    default:
      return NULL;
  }
}

void *lualike_ffi_open(const char *path, char *error, size_t error_capacity) {
  dlerror();
  void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (library == NULL) {
    set_error(error, error_capacity, dlerror());
  }
  return library;
}

void lualike_ffi_close(void *library) {
  if (library != NULL) {
    dlclose(library);
  }
}

void *lualike_ffi_symbol(void *library, const char *name, char *error,
                         size_t error_capacity) {
  if (library == NULL) {
    set_error(error, error_capacity, "library is closed");
    return NULL;
  }
  dlerror();
  void *symbol = dlsym(library, name);
  const char *message = dlerror();
  if (message != NULL) {
    set_error(error, error_capacity, message);
    return NULL;
  }
  return symbol;
}

int32_t lualike_ffi_call(void *symbol, int32_t result_type,
                         const int32_t *argument_types,
                         size_t argument_count,
                         const lualike_ffi_value *arguments,
                         lualike_ffi_value *result, char *error,
                         size_t error_capacity) {
  if (symbol == NULL) {
    set_error(error, error_capacity, "native symbol is null");
    return 1;
  }
  if (argument_count > 64) {
    set_error(error, error_capacity, "native calls are limited to 64 arguments");
    return 1;
  }

  ffi_type *return_type = ffi_type_for(result_type);
  if (return_type == NULL) {
    set_error(error, error_capacity, "unsupported result type");
    return 1;
  }

  ffi_type *ffi_argument_types[64];
  void *ffi_argument_values[64];
  for (size_t i = 0; i < argument_count; i++) {
    ffi_argument_types[i] = ffi_type_for(argument_types[i]);
    ffi_argument_values[i] = value_address(
        (lualike_ffi_value *)&arguments[i], argument_types[i]);
    if (ffi_argument_types[i] == NULL || ffi_argument_values[i] == NULL ||
        argument_types[i] == LUALIKE_FFI_VOID) {
      set_error(error, error_capacity, "unsupported argument type");
      return 1;
    }
  }

  ffi_cif call_interface;
  ffi_status status = ffi_prep_cif(&call_interface, FFI_DEFAULT_ABI,
                                   (unsigned int)argument_count, return_type,
                                   ffi_argument_types);
  if (status != FFI_OK) {
    set_error(error, error_capacity, "ffi_prep_cif failed");
    return 1;
  }

  memset(result, 0, sizeof(*result));
  ffi_call(&call_interface, FFI_FN(symbol),
           result_type == LUALIKE_FFI_VOID ? NULL
                                           : value_address(result, result_type),
           ffi_argument_values);
  return 0;
}
