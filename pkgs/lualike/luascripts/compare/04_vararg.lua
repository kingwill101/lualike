-- Vararg: ... in various positions
local function pack(...) return ... end
local function first(...) return ... end
local function wrap(a, b, ...) return a, b, ... end
return pack(1, 2, 3), first(10, 20), wrap('x', 'y', 'z', 'w')
