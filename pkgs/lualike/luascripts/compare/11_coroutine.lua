-- Coroutine basics
local function prod(n)
  return coroutine.create(function()
    for i = 1, n do
      coroutine.yield(i)
    end
  end)
end
local co = prod(3)
local r1 = {coroutine.resume(co)}
local r2 = {coroutine.resume(co)}
local r3 = {coroutine.resume(co)}
local r4 = {coroutine.resume(co)}
return r1[1], r1[2], r2[1], r2[2], r3[1], r3[2], r4[1], r4[2]
