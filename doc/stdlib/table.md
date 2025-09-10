# Table Library Implementation

This document details the Dart implementation of the `lualike` table library, found in `lib/src/stdlib/lib_table.dart`.

## Overview

The table library provides functions for manipulating tables. In `lualike`, it is loaded as a module, and its functions are typically accessed through a table, e.g., `table.insert(my_table, "value")`.

## Function Implementations

### `table.concat`

**Lualike Usage:**
```lua
local t = {"a", "b", "c"}
print(table.concat(t, ":")) --> "a:b:c"
```

**Implementation Details:**
Joins the string elements of a table's array part into a single string. It takes the table as the first argument, an optional separator string (defaulting to an empty string), and optional start and end indices for the concatenation range. The implementation iterates from the start index to the end index, collecting the values (which must be strings or numbers) and joining them with the specified separator.

### `table.insert`

**Lualike Usage:**
```lua
local t = {"a", "c"}
table.insert(t, 2, "b")
-- t is now {"a", "b", "c"}
```

**Implementation Details:**
Inserts an element into a table's array part at a specified position, shifting existing elements to make space. If no position is provided, it inserts the element at the end of the array part. The implementation finds the length of the table's array sequence, then iterates backwards from that length down to the insertion position, shifting each element one position to the right before placing the new value at the desired spot.

### `table.move`

**Lualike Usage:**
```lua
local t1 = {1, 2, 3, 4, 5}
local t2 = {}
table.move(t1, 1, 5, 1, t2)
-- t2 is now {1, 2, 3, 4, 5}
```

**Implementation Details:**
Copies elements from a source table to a destination table. It can copy within the same table as well. The implementation handles overlapping moves correctly by checking if the destination position is within the source range and, if so, iterating in reverse to prevent overwriting elements before they are copied.

### `table.pack`

**Lualike Usage:**
```lua
local t = table.pack(1, "a", nil, "b")
print(t.n) -- 4
print(t[3]) -- nil
```

**Implementation Details:**
Creates a new table from a variable number of arguments. It packs all arguments into the array part of the new table, including any `nil` values. It also adds a field `n` to the table, set to the total number of arguments received.

### `table.remove`

**Lualike Usage:**
```lua
local t = {"a", "b", "c"}
print(table.remove(t, 2)) --> "b"
-- t is now {"a", "c"}
```

**Implementation Details:**
Removes an element from a table's array part at a specified position, shifting subsequent elements to fill the gap. If no position is given, it removes the last element. The implementation shifts elements from the position upwards to the left and sets the last element of the sequence to `nil`. It returns the value of the element that was removed.

### `table.sort`

**Lualike Usage:**
```lua
local t = {3, 1, 2}
table.sort(t)
-- t is now {1, 2, 3}

local t2 = {"c", "a", "b"}
table.sort(t2, function(a, b) return a < b end)
-- t2 is now {"a", "b", "c"}
```

**Implementation Details:**
Sorts the elements in a table's array part in place. It can take an optional custom comparison function. If no function is provided, it uses the standard `<` operator for comparison. The implementation retrieves all elements from the table's array part into a Dart `List`, sorts that list using Dart's `List.sort`, and then writes the sorted elements back into the original `lualike` table. The sort is not guaranteed to be stable.

### `table.unpack`

**Lualike Usage:**
```lua
local t = {"a", "b", "c"}
print(table.unpack(t)) --> "a", "b", "c"
```

**Implementation Details:**
Returns the elements from a table's array part as a list of multiple return values. It can take optional start and end indices to specify a sub-range of elements to unpack. The implementation iterates from the start to end index, collects the values, and returns them as a multi-value result.