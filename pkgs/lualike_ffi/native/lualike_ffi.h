// Copyright (c) 2026, the lualike authors.
// Use of this source code is governed by the MIT license in the LICENSE file.

#ifndef LUALIKE_FFI_H_
#define LUALIKE_FFI_H_

// Compiler-provided integer types keep binding generation independent of a
// host sysroot while preserving the target ABI widths.
typedef __INT8_TYPE__ int8_t;
typedef __UINT8_TYPE__ uint8_t;
typedef __INT16_TYPE__ int16_t;
typedef __UINT16_TYPE__ uint16_t;
typedef __INT32_TYPE__ int32_t;
typedef __UINT32_TYPE__ uint32_t;
typedef __INT64_TYPE__ int64_t;
typedef __UINT64_TYPE__ uint64_t;
typedef __SIZE_TYPE__ size_t;

#if defined(_WIN32)
#define LUALIKE_FFI_EXPORT __declspec(dllexport)
#else
#define LUALIKE_FFI_EXPORT __attribute__((visibility("default")))
#endif

typedef union lualike_ffi_value {
  int8_t i8;
  uint8_t u8;
  int16_t i16;
  uint16_t u16;
  int32_t i32;
  uint32_t u32;
  int64_t i64;
  uint64_t u64;
  float f32;
  double f64;
  void *pointer;
} lualike_ffi_value;

LUALIKE_FFI_EXPORT void *lualike_ffi_open(const char *path, char *error,
                                          size_t error_capacity);
LUALIKE_FFI_EXPORT void lualike_ffi_close(void *library);
LUALIKE_FFI_EXPORT void *lualike_ffi_symbol(void *library, const char *name,
                                            char *error,
                                            size_t error_capacity);
LUALIKE_FFI_EXPORT int32_t lualike_ffi_call(
    void *symbol, int32_t result_type, const int32_t *argument_types,
    size_t argument_count, const lualike_ffi_value *arguments,
    lualike_ffi_value *result, char *error, size_t error_capacity);

#endif  // LUALIKE_FFI_H_
