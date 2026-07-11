-- Level 5: Table constructor & table access folding
-- Compile time: local T <const> = {x=5, y=10}; T.x → 5; T[2] → 20

local COLOR <const> = {r = 255, g = 128, b = 64, a = 1.0}
local ARRAY <const> = {10, 20, 30, 40, 50}

-- Accessing table fields at compile time
local red   <const> = COLOR.r
local green <const> = COLOR.g
local blue  <const> = COLOR.b
local alpha <const> = COLOR.a

-- Accessing array indices at compile time
local first  <const> = ARRAY[1]
local second <const> = ARRAY[2]
local last   <const> = ARRAY[5]

-- Composited from table lookups
local half_green <const> = COLOR.g / 2
local r_plus_g   <const> = COLOR.r + COLOR.g

print("red   =", red)         -- 255
print("green =", green)       -- 128
print("blue  =", blue)        -- 64
print("alpha =", alpha)       -- 1.0
print("first =", first)       -- 10
print("second =", second)     -- 20
print("last  =", last)        -- 50
print("half_green =", half_green)  -- 64
print("r_plus_g   =", r_plus_g)    -- 383
