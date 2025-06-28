-- Function that returns multiple values
local function f()
    return 10, 20, 30
end

local function g() 
    return 40, 50
end

-- Test vararg functions
local function test_varargs(...)
    print("\nlocal x = ...      -- x gets the first vararg argument.")
    local x = ...
    print("x =", x)
    
    print("\nx,y = ...          -- x gets the first vararg argument, y gets the second")
    local x2, y2 = ...
    print("x =", x2, "y =", y2)
    
    print("\nreturn x, ...      -- returns x and all received vararg arguments.")
    return 999, ...
end

-- Test multiple assignment
local function multiple_assignment()
    print("\nx,y,z = w, f()     -- x gets w, y gets first result from f(), z gets second")
    local w = 5
    local x, y, z = w, f()
    print("x =", x, "y =", y, "z =", z)
    
    print("\nx,y,z = f()        -- x gets first result, y gets second, z gets third")
    local x2, y2, z2 = f()
    print("x =", x2, "y =", y2, "z =", z2)
    
    print("\nx,y,z = f(), g()   -- x gets first from f, y and z get first and second from g")
    local x3, y3, z3 = f(), g()
    print("x =", x3, "y =", y3, "z =", z3)
    
    print("\nx,y,z = (f())      -- x gets first result from f(), y and z get nil")
    local x4, y4, z4 = (f())
    print("x =", x4, "y =", y4, "z =", z4)
end

-- Run the tests
print("Testing varargs:")
print("Result:", test_varargs(100, 200, 300))

print("\nTesting multiple assignment:")
multiple_assignment()

-- Test return
local function test_returns()
    print("\nreturn f()         -- returns all results from f().")
    return f()
end

local function test_returns2()
    print("\nreturn x,y,f()     -- returns x, y, and all results from f().")
    return 1, 2, f()
end

print("\nTesting returns:")
print(test_returns())
print(test_returns2())