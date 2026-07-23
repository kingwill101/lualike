-- Peephole: redundant instructions that the peephole pass cleans up
-- (the source looks normal; the peephole pass optimizes the emitted IR)

-- Self-copy: compiler may emit LOADK r, k; MOVE r, r → peephole removes MOVE
local x = 42
local y = x

-- Dead store: LOADNIL followed by LOADK → peephole removes LOADNIL
local z
z = 99

-- Copy chain: MOVE r1, r2; MOVE r3, r1 → MOVE r1, r2; MOVE r3, r2
local a = x
local b = a
print(x, y, z, a, b)
