-- Multi-return with function calls
local function three() return 1, 2, 3 end
local function two() return 'a', 'b' end

local a, b, c = three()
local d, e = two()
local f, g, h = three(), two()
return a, b, c, d, e, f, g, h
