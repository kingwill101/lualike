-- Tail calls
local function f(x) return x + 1 end
local function g(x) return f(x) end
local function h(x) return g(x) end
return h(10)
