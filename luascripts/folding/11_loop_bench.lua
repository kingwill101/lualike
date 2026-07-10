-- Minimal loop unrolling benchmark (no function call overhead)
local REPEAT <const> = 50000

-- This loop is unrolled (fold ON) or looped (fold OFF)
local s = 0
local start = os.clock()
for j = 1, REPEAT do
    s = s + 1 + 2 + 3 + 4 + 5
end
local elapsed = os.clock() - start
print(string.format("time=%.2fms result=%d", elapsed * 1000, s))
