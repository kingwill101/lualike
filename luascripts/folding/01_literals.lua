-- Level 1: Literal folding
-- All of these expressions are fully computed at compile time.

local a <const> = 42
local b <const> = 3.14
local c <const> = true
local d <const> = nil
local e <const> = "hello world"

print("a =", a)
print("b =", b)
print("c =", c)
print("d =", d)
print("e =", e)
