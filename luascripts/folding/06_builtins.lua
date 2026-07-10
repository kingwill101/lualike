-- Level 6: Built-in function folding (type, tostring, tonumber)
-- Compile time: type(42) → "number", tonumber("3.14") → 3.14, tostring(true) → "true"

local t1 <const> = type(42)
local t2 <const> = type("hello")
local t3 <const> = type(true)
local t4 <const> = type(nil)
local t5 <const> = type({})
local t6 <const> = type(3.14)

local s1 <const> = tostring(42)
local s2 <const> = tostring(true)
local s3 <const> = tostring(nil)
local s4 <const> = tostring(3.14)

local n1 <const> = tonumber("42")
local n2 <const> = tonumber("3.14")
local n3 <const> = tonumber("not a number")
local n4 <const> = tonumber("FF", 16)

-- Combined with string concat
local msg <const> = "The type of 42 is " .. type(42)

print("type(42)     =", t1)              -- number
print("type(str)    =", t2)              -- string
print("type(bool)   =", t3)              -- boolean
print("type(nil)    =", t4)              -- nil
print("type({})     =", t5)              -- table
print("type(3.14)   =", t6)              -- number
print("tostring(42) =", s1)              -- 42
print("tostring(true) =", s2)            -- true
print("tostring(nil) =", s3)             -- nil
print("tonumber(42) =", n1)              -- 42
print("tonumber(3.14) =", n2)            -- 3.14
print("tonumber(bad) =", n3)             -- nil
print("hex FF =", n4)                    -- 255
print("msg =", msg)                      -- The type of 42 is number
