-- Loop unrolling benchmark: Lua bytecode VM
-- RUNS: const-bounded loop gets unrolled when fold=ON
--       fold=OFF keeps the loop

local N <const> = 50000
local COUNT <const> = 4

local s = 0
local t = os.clock()
for i = 1, N do
    local sum = 0
    for j = 1, COUNT do sum = sum + j end
    s = s + sum
end
t = os.clock() - t
print(string.format("time=%.2fms sum=%d", t * 1000, s))
