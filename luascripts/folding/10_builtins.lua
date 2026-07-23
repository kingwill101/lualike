-- Level 10: Built-in function folding (math.*, string.*)
-- These are all computed at compile time

-- math.*
local a1 <const> = math.abs(-10)
local a2 <const> = math.floor(3.7)
local a3 <const> = math.ceil(3.2)
local a4 <const> = math.max(1, 5, 3, 9, 2)
local a5 <const> = math.min(1, 5, 3)
local a6 <const> = math.sqrt(144)
local a7 <const> = math.sin(0)
local a8 <const> = math.cos(0)
local a9 <const> = math.deg(math.pi)
local a10 <const> = math.rad(180)

-- string.*
local s1 <const> = string.len("hello world")
local s2 <const> = string.byte("ABC", 2)
local s3 <const> = string.char(72, 73, 33)  -- "HI!"
local s4 <const> = string.sub("hello world", 1, 5)
local s5 <const> = string.upper("hello")
local s6 <const> = string.lower("WORLD")
local s7 <const> = string.rep("ab", 3)

-- Expression reassociation: (x + 2) + 3 → x + 5
local x = 10
local y = (x + 2) + 3   -- reassociates to x + 5, but runtime gives 15

print("math.abs(-10)   =", a1)        -- 10
print("math.floor(3.7) =", a2)        -- 3
print("math.ceil(3.2)  =", a3)        -- 4
print("math.max(...)   =", a4)        -- 9
print("math.min(...)   =", a5)        -- 1
print("math.sqrt(144)  =", a6)        -- 12.0
print("math.sin(0)     =", a7)        -- 0.0
print("math.cos(0)     =", a8)        -- 1.0
print("math.deg(pi)    =", a9)        -- 180.0
print("math.rad(180)   =", a10)       -- 3.14159...
print("string.len      =", s1)        -- 11
print("string.byte     =", s2)        -- 66
print("string.char     =", s3)        -- HI!
print("string.sub      =", s4)        -- hello
print("string.upper    =", s5)        -- HELLO
print("string.lower    =", s6)        -- world
print("string.rep      =", s7)        -- ababab
print("(x + 2) + 3     =", y)         -- 15
