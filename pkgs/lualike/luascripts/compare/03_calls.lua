-- Function calls: fixed args, open returns, method calls
local function add(a, b) return a + b end
local function multi() return 1, 2, 3 end
local a, b, c = multi()
return add(a, b), c, add(1, 2)
