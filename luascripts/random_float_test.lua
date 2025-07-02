local random, max, min = math.random, math.max, math.min
local function eq(a, b, limit)
  limit = limit or 1e-5
  return a == b or math.abs(a-b) <= limit
end
local randbits = math.min(53, 64)
local mult = 2^randbits
local counts = {}
for i = 1, randbits do counts[i] = 0 end
local up = -math.huge
local low = math.huge
local rounds = 10
local totalrounds = 0
::doagain::
print('loop start', totalrounds)
for i = 0, rounds do
  local t = random()
  up = max(up, t)
  low = min(low, t)
  local bit = i % randbits
  if (t * 2^bit) % 1 >= 0.5 then
    counts[bit + 1] = counts[bit + 1] + 1
  end
end
totalrounds = totalrounds + rounds
if not (eq(up, 1, 0.001) and eq(low, 0, 0.001)) then
  goto doagain
end
print('passed range check')
local expected = (totalrounds / randbits / 2)
for i = 1, randbits do
  if not (math.abs(counts[i] - expected) < expected * 0.10) then
    goto doagain
  end
end
print('finished after', totalrounds)
