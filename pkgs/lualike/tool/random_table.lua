local function main(limit)
  print('limit', limit)
  local counts = {}
  for i=1,64 do counts[i]=0 end
  local start = os.clock()
  for i = 1, limit do
    local idx = (i % 64) + 1
    counts[idx] = counts[idx] + 1
  end
  print(string.format('counts update elapsed %.6fs', os.clock() - start))
end

local argLimit = tonumber(arg[1] or '10000')
main(argLimit)
