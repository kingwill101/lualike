-- Functions that return multiple values
local function f()
    return 10, 20, 30
end

-- Function to print table contents
local function print_table(t)
    local result = "{"
    for k, v in pairs(t) do
        result = result .. tostring(k) .. " = " .. tostring(v) .. ", "
    end
    return result .. "}"
end

-- Test cases for table constructors
print("{f()}              -- creates a list with all results from f().")
print(print_table({f()}))

-- Test with varargs
local function test_with_varargs(...)
    print("\n{...}              -- creates a list with all vararg arguments.")
    print(print_table({...}))
    
    print("\n{f(), 5}           -- creates a list with the first result from f() and 5.")
    print(print_table({f(), 5}))
end

-- Run the vararg tests
test_with_varargs(100, 200, 300)

-- Additional test cases
print("\nAdditional table constructor tests:")
print("t1 = {f(), f()}", print_table({f(), f()}))
print("t2 = {5, f(), 6}", print_table({5, f(), 6}))
print("t3 = {f(), ...}", print_table({f(), 100, 200, 300}))
print("t4 = {f(), ..., f()}", print_table({f(), 100, 200, 300, f()}))