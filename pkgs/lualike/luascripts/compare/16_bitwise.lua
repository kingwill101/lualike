-- Bitwise operations
local a = 7 & 3     -- 3 (band)
local b = 5 | 2     -- 7 (bor)
local c = 6 ~ 3     -- 5 (bxor)
local d = ~7        -- -8 (bnot)
local e = 8 << 2    -- 32 (shl)
local f = 32 >> 3   -- 4 (shr)
local g = 2 ^ 3     -- 8 (pow)
return a, b, c, d, e, f, g
