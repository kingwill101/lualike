-- Level 3: String concatenation folding
-- Compile time: "a" .. "b" → "ab", "hello " .. "world" → "hello world"

local a <const> = "hello" .. " " .. "world"
local b <const> = "ab" .. "cd" .. "ef"
local c <const> = "one" .. " " .. "two" .. " " .. "three"
local d <const> = "---" .. "====" .. "---"

-- Mixed: number coerced to string at compile time
local e <const> = "value: " .. 42
local f <const> = 3.14 .. " is pi"

print("a =", a)       -- hello world
print("b =", b)       -- abcdef
print("c =", c)       -- one two three
print("d =", d)       -- ---====---
print("e =", e)       -- value: 42
print("f =", f)       -- 3.14 is pi
