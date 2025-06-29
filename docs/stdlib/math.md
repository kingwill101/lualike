# Math Library Implementation

This document details the Dart implementation of the `lualike` math library, found in `lib/src/stdlib/lib_math.dart`.

## Overview

The math library provides a collection of standard mathematical functions. In `lualike`, it is loaded as a module and its functions are typically accessed through a table, e.g., `math.sin(x)`. It also provides constants like `math.pi` and `math.huge`.

## Function and Constant Implementations

### Constants

**Lualike Usage:**
```lua
print(math.pi)   -- 3.141592653589793
print(math.huge) -- inf
print(math.maxinteger) -- 9223372036854775807
print(math.mininteger) -- -9223372036854775808
```

**Implementation Details:**
- `math.pi`: Implemented using the `pi` constant from Dart's `dart:math` library.
- `math.huge`: Represents infinity. Implemented using Dart's `double.infinity`.
- `math.maxinteger` and `math.mininteger`: Represent the maximum and minimum values for a `lualike` integer. In the Dart implementation, these correspond to the limits of a 64-bit signed integer.

### `math.abs`

**Lualike Usage:**
```lua
print(math.abs(-10)) -- 10
```

**Implementation Details:**
Calculates the absolute value of a number. It's implemented by calling the `.abs()` method on the Dart number object.

### `math.acos`, `math.asin`, `math.atan`

**Lualike Usage:**
```lua
print(math.acos(0)) -- 1.5707963267948966
```

**Implementation Details:**
These are the standard trigonometric functions for arc cosine, arc sine, and arc tangent. They are implemented by directly calling their counterparts (`acos`, `asin`, `atan`) from the `dart:math` library.

### `math.ceil`

**Lualike Usage:**
```lua
print(math.ceil(5.1)) -- 6
```

**Implementation Details:**
Returns the smallest integer greater than or equal to `x`. This is implemented using the `.ceil()` method on the Dart number object.

### `math.cos`, `math.sin`, `math.tan`

**Lualike Usage:**
```lua
print(math.cos(math.pi)) -- -1
```

**Implementation Details:**
Standard trigonometric functions implemented by calling `cos`, `sin`, and `tan` from `dart:math`.

### `math.deg` and `math.rad`

**Lualike Usage:**
```lua
print(math.deg(math.pi)) -- 180
print(math.rad(180))     -- 3.14159...
```

**Implementation Details:**
Convert between degrees and radians. `math.deg` converts radians to degrees, and `math.rad` converts degrees to radians. The implementation uses the standard mathematical formulas for conversion.

### `math.exp`

**Lualike Usage:**
```lua
print(math.exp(1)) -- 2.71828... (e)
```

**Implementation Details:**
Computes *e* raised to the power of `x`. Implemented using `exp` from `dart:math`.

### `math.floor`

**Lualike Usage:**
```lua
print(math.floor(5.9)) -- 5
```

**Implementation Details:**
Returns the largest integer less than or equal to `x`. This is implemented using the `.floor()` method on the Dart number object.

### `math.fmod`

**Lualike Usage:**
```lua
print(math.fmod(10, 3)) -- 1
print(10 % 3)           -- 1
```

**Implementation Details:**
Returns the remainder of the division of `x` by `y` that rounds the quotient towards zero. This is equivalent to the Lua `%` operator. The implementation uses the `%` operator in Dart.

### `math.log`

**Lualike Usage:**
```lua
print(math.log(math.exp(1))) -- 1
print(math.log(100, 10))     -- 2
```

**Implementation Details:**
Computes the logarithm of `x`. If a second argument `base` is provided, it computes the logarithm in that base. If no base is provided, it computes the natural logarithm. Implemented using `log` from `dart:math` and the change of base formula (`log(x) / log(base)`) if a base is specified.

### `math.max` and `math.min`

**Lualike Usage:**
```lua
print(math.max(1, 10, -5, 20)) -- 20
print(math.min(1, 10, -5, 20)) -- -5
```

**Implementation Details:**
Return the maximum or minimum value from a list of arguments. The implementation iterates through the provided arguments, keeping track of the greatest (for `max`) or least (for `min`) value seen so far.

### `math.modf`

**Lualike Usage:**
```lua
local int, frac = math.modf(3.14)
print(int, frac) -- 3, 0.14000000000000012
```

**Implementation Details:**
Splits a number into its integer and fractional parts. The implementation uses `.truncate()` on the Dart number to get the integer part and subtraction to find the fractional part. It returns both values.

### `math.random`

**Lualike Usage:**
```lua
-- A float between 0.0 and 1.0
print(math.random())
-- An integer between 1 and 100
print(math.random(100))
-- An integer between 50 and 100
print(math.random(50, 100))
```

**Implementation Details:**
Generates pseudo-random numbers.
- Called without arguments, it returns a float between 0.0 and 1.0.
- Called with one integer argument `m`, it returns an integer in the range `[1, m]`.
- Called with two integer arguments `m` and `n`, it returns an integer in the range `[m, n]`.
The implementation uses Dart's `Random` class.

### `math.randomseed`

**Lualike Usage:**
```lua
math.randomseed(os.time())
```

**Implementation Details:**
Sets the seed for the pseudo-random number generator. This allows for reproducible sequences of random numbers. The implementation re-initializes Dart's `Random` object with the given seed.

### `math.sqrt`

**Lualike Usage:**
```lua
print(math.sqrt(16)) -- 4
```

**Implementation Details:**
Computes the square root of a number, implemented by calling `sqrt` from `dart:math`.

### `math.type`

**Lualike Usage:**
```lua
print(math.type(3))   -- "integer"
print(math.type(3.0)) -- "float"
```

**Implementation Details:**
Returns "integer" if the value is an integer, "float" if it is a float, or `nil` if it is not a number. The implementation checks the runtime type of the Dart object.

### `math.ult`

**Lualike Usage:**
```lua
-- Compare two numbers as if they were unsigned integers
print(math.ult(-1, 0)) -- true (-1 is larger than 0 in unsigned)
```

**Implementation Details:**
Performs an unsigned less-than comparison between two integers. The implementation uses Dart's `BigInt.toUnsigned` to convert the numbers before comparing them, correctly handling the wrap-around behavior of unsigned 64-bit integers.