-- Test script for arithmetic with function return values

-- Function that returns multiple values
local function f()
    return 10, 20, 30
end

-- Test case 1: Adding a number to a function call
print("Result of 1 + f() =", 1 + f())

-- Test case 2: Adding two function calls together
print("Result of f() + f() =", f() + f())

-- Test case 3: Adding function call to a number 
print("Result of f() + 5 =", f() + 5)

-- Test case 4: Subtracting function calls
print("Result of f() - f() =", f() - f())

-- Test case 5: Multiplying function calls
print("Result of f() * f() =", f() * f())

-- Test case 6: Using function calls in complex expressions
print("Result of (f() + 5) * 2 =", (f() + 5) * 2)

-- Test case 7: Using function calls with multiple operations
print("Result of f() + f() * 2 =", f() + f() * 2)