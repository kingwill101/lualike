-- Const propagation: `x` is assigned once, no `<const>` needed
local x = 10
local y = x * 2      -- propagated to y = 10 * 2 = 20
local z = y + 5       -- propagated to z = 20 + 5 = 25
print("z =", z)       -- 25
