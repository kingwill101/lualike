local random, max, min = math.random, math.max, math.min
local intbits = math.floor(math.log(math.maxinteger,2)+0.5)+1
local maxint = math.maxinteger
local minint = math.mininteger
local counts = {}
for i = 1, intbits do counts[i] = 0 end
local up = 0
local low = 0
local rounds = 10
local totalrounds = 0
::doagain::
print('loop start', totalrounds)
for i=0, rounds do
  local t = random(0)
  up = max(up, t)
  low = min(low, t)
  local bit = i % intbits
  counts[bit+1] = counts[bit+1] + ((t >> bit) & 1)
end
totalrounds = totalrounds + rounds
local lim = maxint >> 10
if not (maxint - up < lim and low - minint < lim) then
  goto doagain
end
print('passed range check')
local expected = totalrounds / intbits / 2
for i=1,intbits do
  if not (math.abs(counts[i]-expected) < expected*0.10) then
    goto doagain
  end
end
print('finished after', totalrounds)
