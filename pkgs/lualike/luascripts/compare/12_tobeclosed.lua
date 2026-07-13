-- To-be-closed variables (basic)
local function mk(v)
  return setmetatable({v}, {__close = function(t) t[1] = t[1] + 1 end})
end

local function test()
  local x <close> = mk(10)
  local y <close> = mk(20)
  return x[1], y[1]
end

local r1, r2 = test()
return r1, r2
