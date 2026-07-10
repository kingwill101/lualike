-- Level 7: User-defined function inlining
-- Compile time: local function add(a,b) return a+b end; add(3,4) → 7
-- Chained calls: double(triple(5)) → 30

local function add(a, b)
    return a + b
end

local function mul(a, b)
    return a * b
end

local function compose(f, g, x)
    return f(g(x))
end

local function double(x)
    return x * 2
end

local function triple(x)
    return x * 3
end

local function describe(n)
    return "the value " .. tostring(n) .. " is a " .. type(n)
end

-- Direct inlining
local r1 <const> = add(3, 4)
local r2 <const> = mul(10, 5)
local r3 <const> = add(mul(2, 3), mul(4, 5))
local r4 <const> = double(triple(5))

-- Function inlining with builtins inside
local r5 <const> = describe(42)

-- Table + function combo
local T <const> = {a = 10, b = 20}
local r6 <const> = add(T.a, T.b)

print("add(3, 4)       =", r1)       -- 7
print("mul(10, 5)      =", r2)       -- 50
print("add(mul, mul)   =", r3)       -- 26
print("double(triple)  =", r4)       -- 30
print("describe(42)    =", r5)       -- the value 42 is a number
print("T.a + T.b       =", r6)       -- 30
