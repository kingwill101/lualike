-- Numeric for, generic for
local sum = 0
for i = 1, 10 do
  sum = sum + i
end
local t = {a = 1, b = 2, c = 3}
for k, v in pairs(t) do
  sum = sum + v
end
return sum
