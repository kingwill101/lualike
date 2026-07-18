-- LLVM pipeline test: pairs iteration
local t = {}
t["a"] = 10
t["b"] = 20
local sum = 0
for k, v in pairs(t) do
  sum = sum + v
end
if sum == 30 then print("pass") else print("fail") end
