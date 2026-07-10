-- Level 2: Arithmetic & comparison folding
-- Compile time: 2 + 3 * 4 - 1 → 13, 5 > 3 → true, etc.

local a <const> = 2 + 3
local b <const> = 10 * 5 + 3
local c <const> = 100 / 4 - 5
local d <const> = 2 + 3 * 4 - 1
local e <const> = 10 % 3
local f <const> = 2 ^ 10

local cmp1 <const> = 5 > 3
local cmp2 <const> = 10 <= 5
local cmp3 <const> = 7 == 7
local cmp4 <const> = 3 ~= 4

print("a =", a)       -- 5
print("b =", b)       -- 53
print("c =", c)       -- 20
print("d =", d)       -- 13
print("e =", e)       -- 1
print("f =", f)       -- 1024
print("5 > 3 =", cmp1)     -- true
print("10 <= 5 =", cmp2)   -- false
print("7 == 7 =", cmp3)    -- true
print("3 ~= 4 =", cmp4)    -- true
