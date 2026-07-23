-- LLVM pipeline test: for loop
local sum = 0
for i = 1, 5 do
  sum = sum + i
end
if sum == 15 then print("pass") else print("fail") end
