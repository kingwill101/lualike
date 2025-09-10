# Number Handling in LuaLike

This guide covers how numbers work in LuaLike, focusing on the `NumberUtils` class, Lua number semantics, and proper number handling.

## Core Concepts

### Lua Number Types

Lua 5.4 has two number types with automatic selection:

```dart
// Integers (64-bit signed)
42        // int
-123      // int
0x7FFFFFFFFFFFFFFF  // max int (9223372036854775807)

// Floats (IEEE 754 double-precision)
3.14      // float
1e10      // float
10 / 3    // float (division always produces float)
10 // 3   // int (floor division)
```

### NumberUtils Class

LuaLike uses `NumberUtils` for all number operations to ensure Lua-compatible semantics. Internally, LuaLike works with various Dart numeric types (`int`, `double`, `BigInt`, `num`) and the `NumberUtils` class makes sense of all these different types and their expectations, providing a unified interface that follows Lua number semantics.

```dart
class NumberUtils {
  // Type checking - handles int, double, BigInt, num
  static bool isInteger(dynamic value);
  static bool isZero(dynamic value);
  static bool isFinite(dynamic value);

  // Conversions - unified handling of all numeric types
  static double toDouble(dynamic value);
  static int toInt(dynamic value);
  static int? tryToInteger(dynamic value);

  // Arithmetic with overflow handling - works with mixed types
  static dynamic add(dynamic a, dynamic b);
  static dynamic subtract(dynamic a, dynamic b);
  static dynamic multiply(dynamic a, dynamic b);
  static dynamic divide(dynamic a, dynamic b);
  static dynamic floorDivide(dynamic a, dynamic b);
  static dynamic modulo(dynamic a, dynamic b);

  // Bitwise operations - converts to appropriate integer types
  static int bitwiseAnd(dynamic a, dynamic b);
  static int bitwiseOr(dynamic a, dynamic b);
  static int bitwiseXor(dynamic a, dynamic b);

  // Comparison - handles cross-type comparisons
  static int compare(dynamic a, dynamic b);
}
```

## Number Semantics

### Integer vs Float Selection

```dart
await lua.execute('''
  local a = 42        -- integer
  local b = 42.0      -- float
  local c = 10 / 2    -- 5.0 (float - division produces float)
  local d = 10 // 2   -- 5 (integer - floor division)
  local e = 2 ^ 3     -- 8.0 (float - exponentiation produces float)
''');
```

### Precision and Limits

```dart
// Integer limits (64-bit signed)
const minInteger = -9223372036854775808;  // -2^63
const maxInteger = 9223372036854775807;   //  2^63-1

// Float precision (IEEE 754 double)
// ~15-17 decimal digits of precision
// Special values: Infinity, -Infinity, NaN
```

### Automatic Coercion

```dart
await lua.execute('''
  -- String to number in arithmetic
  local result1 = "42" + 8     -- 50
  local result2 = "3.14" * 2   -- 6.28
  local result3 = "0xFF" + 1   -- 256

  -- Number to string in concatenation
  local result4 = 42 .. " items"  -- "42 items"
''');
```

## Using NumberUtils

### In Custom Functions

Always use `NumberUtils` for number operations and wrap results:

```dart
lua.expose('safeAdd', (List<Object?> args) {
  final a = args[0] is Value ? (args[0] as Value).unwrap() : args[0];
  final b = args[1] is Value ? (args[1] as Value).unwrap() : args[1];
  final result = NumberUtils.add(a, b);
  return Value(result);  // Always wrap in Value
});

lua.expose('isInteger', (List<Object?> args) {
  final value = args[0] is Value ? (args[0] as Value).unwrap() : args[0];
  final result = NumberUtils.isInteger(value);
  return Value(result);
});
```

### Arithmetic Operations

```dart
// Use NumberUtils for precise arithmetic
final result = NumberUtils.add(0.1, 0.2);  // Handles precision correctly
final quotient = NumberUtils.divide(10, 3);  // Returns 3.3333...
final floorDiv = NumberUtils.floorDivide(10, 3);  // Returns 3 (integer)
```

### Type Conversions

```dart
// Safe conversions
final intValue = NumberUtils.tryToInteger(value);  // Returns null if not convertible
final doubleValue = NumberUtils.toDouble(value);   // Always returns double
final isInt = NumberUtils.isInteger(value);        // Type checking
```

## Number Formatting

### String Conversion

```dart
await lua.execute('''
  local num = 42
  local str1 = tostring(num)     -- "42"
  local str2 = string.format("%d", num)  -- "42"
  local str3 = string.format("%.2f", 3.14159)  -- "3.14"
''');
```

### Format Specifiers

```dart
await lua.execute('''
  local n = 255

  -- Integer formats
  local dec = string.format("%d", n)    -- "255"
  local hex = string.format("%x", n)    -- "ff"
  local oct = string.format("%o", n)    -- "377"

  -- Float formats
  local f = 3.14159
  local fixed = string.format("%.2f", f)    -- "3.14"
  local sci = string.format("%.2e", f)      -- "3.14e+00"
  local gen = string.format("%.2g", f)      -- "3.1"
''');
```

## Working with Large Numbers

### Integer Overflow

```dart
await lua.execute('''
  local max_int = 9223372036854775807
  local overflow = max_int + 1  -- Becomes float: 9.223372036854776e+18

  -- Use // for integer operations that should stay integers
  local big_div = max_int // 2  -- Integer result
''');
```

### BigInt Conversion

```dart
// Dart BigInt to Lua (may lose precision if too large)
final bigInt = BigInt.parse('12345678901234567890');
lua.setGlobal('bigNum', bigInt);  // Converted to Lua number

// Check if value fits in Lua integer
final fitsInInt = NumberUtils.tryToInteger(bigInt) != null;
```

## Bitwise Operations

```dart
await lua.execute('''
  local a = 0xFF
  local b = 0x0F

  local and_result = a & b    -- 15 (0x0F)
  local or_result = a | b     -- 255 (0xFF)
  local xor_result = a ~ b    -- 240 (0xF0)
  local not_result = ~a       -- -256 (two's complement)
  local shift_left = a << 1   -- 510 (0x1FE)
  local shift_right = a >> 1  -- 127 (0x7F)
''');
```

### Custom Bitwise Functions

```dart
lua.expose('bitwiseAnd', (List<Object?> args) {
  final a = args[0] is Value ? (args[0] as Value).unwrap() : args[0];
  final b = args[1] is Value ? (args[1] as Value).unwrap() : args[1];
  final result = NumberUtils.bitwiseAnd(a, b);
  return Value(result);
});
```

## Special Values

### Infinity and NaN

```dart
await lua.execute('''
  local inf = 1/0          -- Infinity
  local neg_inf = -1/0     -- -Infinity
  local nan = 0/0          -- NaN

  -- Checking special values
  local is_inf = inf == math.huge
  local is_nan = nan ~= nan  -- NaN is not equal to itself
''');
```

### Handling in Custom Functions

```dart
lua.expose('safeDivide', (List<Object?> args) {
  final a = NumberUtils.toDouble(args[0] is Value ? (args[0] as Value).unwrap() : args[0]);
  final b = NumberUtils.toDouble(args[1] is Value ? (args[1] as Value).unwrap() : args[1]);

  if (NumberUtils.isZero(b)) {
    return Value(double.infinity);
  }

  final result = NumberUtils.divide(a, b);
  return Value(result);
});
```

## Common Patterns

### Safe Number Extraction

```dart
dynamic extractNumber(Value value) {
  final raw = value.unwrap();
  if (NumberUtils.isInteger(raw)) {
    return raw;
  } else if (raw is num) {
    return raw;
  }
  throw LuaError.typeError('Expected number, got ${raw.runtimeType}');
}
```

### Number Validation

```dart
lua.expose('validateRange', (List<Object?> args) {
  final value = extractNumber(args[0] as Value);
  final min = extractNumber(args[1] as Value);
  final max = extractNumber(args[2] as Value);

  final inRange = NumberUtils.compare(value, min) >= 0 &&
                  NumberUtils.compare(value, max) <= 0;

  return Value(inRange);
});
```

### ValueClass Integration

```dart
// Use ValueClass.number() for automatic number metatable
lua.expose('createNumber', (List<Object?> args) {
  final value = NumberUtils.toDouble(args[0] is Value ? (args[0] as Value).unwrap() : args[0]);
  return ValueClass.number(value);  // Automatic number metamethods
});
```

## Key Differences from Dart Numbers

1. **Division**: `/` always produces float, `//` produces integer
2. **Exponentiation**: `^` always produces float
3. **Modulo**: `%` follows Lua semantics (sign of divisor)
4. **Comparison**: Uses Lua comparison rules
5. **Coercion**: Automatic string-number conversion in arithmetic
6. **Precision**: IEEE 754 double precision for floats
7. **Integer range**: 64-bit signed integers

This is the core of number handling in LuaLike - use `NumberUtils` for all operations, understand integer vs float selection, and always wrap results in `Value` objects.