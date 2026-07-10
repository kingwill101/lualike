-- Level 4: Boolean logic & short-circuit folding
-- Compile time: true and false → false, false or expensive() → false (short-circuit), etc.

local a <const> = true and false
local b <const> = true or false
local c <const> = not true
local d <const> = not false
local e <const> = (1 < 2) and (3 > 4)
local f <const> = (1 > 2) or (3 < 4)

-- Short-circuit: false and X → false (X never evaluated)
local g <const> = false and (error("should not run") == nil)
local h <const> = true or (error("should not run") == nil)

-- Combined with comparisons
local i <const> = (10 * 5) > (3 + 4) and type("hi") == "string"

-- Unary
local j <const> = -42
local k <const> = ~0xFF

print("a =", a)       -- false
print("b =", b)       -- true
print("c =", c)       -- false
print("d =", d)       -- true
print("e =", e)       -- false
print("f =", f)       -- true
print("g =", g)       -- false (short-circuit)
print("h =", h)       -- true (short-circuit)
print("i =", i)       -- true
print("j =", j)       -- -42
print("k =", k)       -- -256
