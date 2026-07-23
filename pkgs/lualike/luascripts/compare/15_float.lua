-- Floating-point and edge-case arithmetic
local huge = math.huge
local nan = 0/0
local inf = 1/0

local a = 1.5 + 2.5       -- 4.0 (float)
local b = 1/3              -- 0.333...
local c = 10 // 3          -- 3 (integer division)
local d = 10 % 3           -- 1
local e = 2 ^ 10           -- 1024
local f = -huge            -- -inf
local g = nan ~= nan       -- true (NaN != NaN)
return a, c, d, e, f, g
